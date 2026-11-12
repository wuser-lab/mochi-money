import http from 'node:http';
import {readFile, writeFile, mkdir, rename, rm} from 'node:fs/promises';
import {createHash, createHmac, randomBytes, createPublicKey, verify, createCipheriv, createDecipheriv} from 'node:crypto';
import {Readable} from 'node:stream';
import {pathToFileURL} from 'node:url';
import {createService} from './server.mjs';
import {verifyAppleNotification} from './apple-notifications.mjs';
import {beginTracking,measureProgress,publicBoard,monthStart,shiftMonth,monthKey,countryCodes} from './community.mjs';

const hash = v => createHash('sha256').update(v).digest('hex');
const random = () => randomBytes(32).toString('base64url');
const fail = (status, message) => Object.assign(Error(message), {status});
export async function verifyAppleToken(token, audience, nonce, keys, now = Date.now()) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) throw Error();
    const header = JSON.parse(Buffer.from(parts[0], 'base64url'));
    const claims = JSON.parse(Buffer.from(parts[1], 'base64url'));
    const key = keys.find(k => k.kid === header.kid && k.kty === 'RSA' && k.alg === 'RS256' && k.use === 'sig');
    if (header.alg !== 'RS256' || !key || !verify('RSA-SHA256', Buffer.from(parts.slice(0,2).join('.')), createPublicKey({key, format:'jwk'}), Buffer.from(parts[2], 'base64url'))) throw Error();
    if (claims.iss !== 'https://appleid.apple.com' || claims.aud !== audience || typeof claims.sub !== 'string' || !claims.sub || claims.sub.length > 256 || !Number.isFinite(claims.exp) || claims.exp * 1000 <= now || !Number.isFinite(claims.iat) || claims.iat * 1000 > now + 60000 || claims.nonce !== nonce) throw Error();
    return claims.sub;
  } catch { throw fail(401, 'Apple sign-in could not be verified. Please try again.'); }
}

// A single process owns these encrypted files. Scale with a transactional database,
// shared rate limiter and distributed locks before running multiple replicas.
export async function createAccountService(config, dependencies = {}) {
  const origin = new URL(config.origin);
  if (origin.protocol !== 'https:' && !(origin.protocol === 'http:' && ['127.0.0.1','localhost'].includes(origin.hostname))) throw Error('Use HTTPS.');
  if (!config.masterKey || config.masterKey.length < 43 || !config.appleAudience || !config.appleClientSecret || !config.dataDir) throw Error('Set master key, Apple audience/client secret, and private data directory.');
  const fetcher = dependencies.fetch || fetch;
  const cipherKey = createHash('sha256').update(config.masterKey).digest();
  await mkdir(config.dataDir, {recursive:true,mode:0o700});
  const file = config.dataDir + '/accounts.enc';
  let state = {users:{},sessions:{},callbacks:{}};
  try {
    const bytes = await readFile(file), decipher = createDecipheriv('aes-256-gcm', cipherKey, bytes.subarray(0,12));
    decipher.setAuthTag(bytes.subarray(12,28));
    state = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]));
  } catch (e) { if (e.code !== 'ENOENT') throw Error('Unable to decrypt account storage.'); }
  async function save() {
    const iv = randomBytes(12), cipher = createCipheriv('aes-256-gcm',cipherKey,iv);
    const bytes = Buffer.concat([cipher.update(JSON.stringify(state)),cipher.final()]);
    await writeFile(file+'.tmp',Buffer.concat([iv,cipher.getAuthTag(),bytes]),{mode:0o600});
    await rename(file+'.tmp',file);
  }
  state.callbacks ||= {};
  state.appleEvents ||= {};
  let queue = Promise.resolve();
  const serial = fn => { const next = queue.then(fn); queue = next.catch(()=>{}); return next; };
  const challenges = new Map(), services = new Map(), locks = new Map(), limits = new Map();
  const locked = (id, fn) => {
    const next = (locks.get(id) || Promise.resolve()).then(fn);
    const settled = next.catch(()=>{}); locks.set(id,settled);
    settled.then(()=>{if(locks.get(id) === settled) locks.delete(id);});
    return next;
  };
  let appleKeys = [], keysUntil = 0;
  async function keys() {
    if (Date.now() >= keysUntil) {
      const response = await fetcher('https://appleid.apple.com/auth/keys', {signal:AbortSignal.timeout(15000),redirect:'error'});
      if (!response.ok) throw fail(503, 'Apple sign-in is temporarily unavailable.');
      appleKeys = (await response.json()).keys; keysUntil = Date.now()+3600000;
    }
    return appleKeys;
  }
  async function apple(path, params) {
    const response = await fetcher('https://appleid.apple.com/auth/'+path, {method:'POST',redirect:'error',signal:AbortSignal.timeout(15000),headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({client_id:config.appleAudience,client_secret:config.appleClientSecret,...params})});
    if (!response.ok) throw fail(502, 'Apple authorization could not be completed. Please try signing in again.');
    return path === 'revoke' ? {} : response.json();
  }
  async function service(id) {
    if (!services.has(id)) {
      const promise = createService({...config, token:createHmac('sha256',config.masterKey).update('bank:'+id).digest('hex'),dataDir:config.dataDir+'/'+id,callbackPath:'/callback/'+id, callbackRedirectURL:origin.origin+'/callback', onAuthorizationState:nonce=>serial(async()=>{
        for (const [key,value] of Object.entries(state.callbacks)) if (value.expires <= Date.now()) delete state.callbacks[key];
        state.callbacks[nonce] = {user:id,expires:Date.now()+900000}; await save();
      })}, dependencies.provider);
      services.set(id,promise);
      promise.catch(()=>services.delete(id));
    }
    return services.get(id);
  }
  async function forward(id, req, res) {
    req.headers.authorization = 'Bearer '+createHmac('sha256',config.masterKey).update('bank:'+id).digest('hex');
    const bank = await service(id);
    await new Promise((resolve,reject)=>{
      res.once('finish',resolve); res.once('close',resolve); res.once('error',reject);
      bank.emit('request', req, res);
    });
  }
  async function bankCall(id, path, body) {
    const bank = await service(id);
    const req = Readable.from(body ? [JSON.stringify(body)] : []);
    req.method = body ? 'POST' : 'GET'; req.url = '/'+path;
    req.headers = {host:origin.host, authorization:'Bearer '+createHmac('sha256',config.masterKey).update('bank:'+id).digest('hex')};
    return new Promise((resolve,reject)=>bank.emit('request',req,{
      writeHead(status) { this.status = status; },
      end(text) {
        try {
          const data = JSON.parse(text);
          this.status === 200 ? resolve(data) : reject(fail(this.status,data.error || 'Bank request failed.'));
        } catch(e) { reject(e); }
      }
    }));
  }
  async function finishAppleRevocation(id) {
    await bankCall(id,'disconnect',{});
    await serial(async()=>{
      for (const eventID of state.users[id]?.applePending?.ids || []) state.appleEvents[eventID]=Date.now();
      delete state.users[id];
      for (const [key,value] of Object.entries(state.sessions)) if(value.user===id) delete state.sessions[key];
      for (const [key,value] of Object.entries(state.callbacks)) if(value.user===id) delete state.callbacks[key];
      await save();
    });
    services.delete(id);
    await rm(config.dataDir+'/'+id,{recursive:true,force:true});
  }
  const clock = () => dependencies.now ? dependencies.now() : new Date();
  const communityValue = id => {
    const value = state.users[id].community;
    return value ? {tracking:true,sharing:value.sharing,nickname:value.nickname,country:value.country || null,
      eligibleMonth:value.tracking.eligibleMonth,baselineRate:value.tracking.baselineRate,score:value.score || null} : {tracking:false,sharing:false,nickname:'',country:null,eligibleMonth:null,baselineRate:null,score:null};
  };
  const json = (res,status,value) => {res.writeHead(status, {'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(value));};
  async function body(req) {
    const chunks = []; let size = 0;
    for await (const chunk of req) { size += chunk.length; if (size > 16384) throw fail(413,'Request too large.'); chunks.push(chunk); }
    try { return JSON.parse(Buffer.concat(chunks).toString() || '{}'); } catch { throw fail(400,'Invalid request.'); }
  }
  function current(req) {
    const token = req.headers.authorization?.match(/^Bearer ([A-Za-z0-9_-]{43})$/)?.[1];
    const session = token && state.sessions[hash(token)];
    if (!session || session.expires <= Date.now() || !Object.hasOwn(state.users,session.user) || state.users[session.user]?.appleRevoked) throw fail(401,'Sign in to Mochi again.');
    return {user:session.user,key:hash(token)};
  }
  return http.createServer(async(req,res)=>{
    try {
      if (req.headers.host !== origin.host || req.headers.origin) throw fail(403,'Use the Mochi app.');
      const url = new URL(req.url,origin);
      // Do not trust forwarded IP headers. Reverse proxy must also enforce per-IP limits.
      const address = req.socket.remoteAddress || 'unknown';
      const now = Date.now();
      for (const [key,value] of limits) if (value.until <= now) limits.delete(key);
      const limit = limits.get(address) || {count:0,until:now+60000};
      if (++limit.count > 120) throw fail(429,'Too many requests. Try again shortly.');
      if (limits.size >= 10000 && !limits.has(address)) throw fail(503,'Please try again shortly.');
      limits.set(address,limit);
      if (url.pathname === '/callback' && req.method === 'GET') {
        const nonce = url.searchParams.get('state');
        const callback = await serial(async()=>{
          const found = /^[a-f0-9]{64}$/.test(nonce || '') && Object.hasOwn(state.callbacks,nonce) ? state.callbacks[nonce] : null;
          if (!found || found.expires <= Date.now()) throw fail(400,'Connection request expired.');
          delete state.callbacks[nonce]; await save(); return found;
        });
        return await locked(callback.user, async()=>{
          if (!Object.hasOwn(state.users,callback.user)) throw fail(400,'Connection request expired.');
          req.url = '/callback/'+callback.user+url.search;
          await forward(callback.user,req,res);
        });
      }
      if(url.pathname==='/auth/apple/notifications' && req.method==='POST') {
        const input=await body(req);
        const event=verifyAppleNotification(input.payload,config.appleAudience,await keys());
        if(event.type==='email-enabled' || event.type==='email-disabled') return json(res,200,{ok:true}); // No email is stored or sent.
        const id=createHmac('sha256',config.masterKey).update('apple:'+event.sub).digest('hex');
        const eventID=hash(event.jti);
        return await locked(id,async()=>{
          if(Object.hasOwn(state.appleEvents,eventID)) return json(res,200,{ok:true});
          const user=state.users[id];
          if(!user || event.eventTime+1000<(user.lastAuthenticatedAt || 0)) {
            await serial(async()=>{state.appleEvents[eventID]=Date.now();await save();});
            return json(res,200,{ok:true});
          }
          // Deny app sessions and hide sharing BEFORE provider revocation. Failures
          // retain encrypted cleanup state so an Apple retry can finish safely.
          await serial(async()=>{
            const ids=new Set(user.applePending?.ids || []);ids.add(eventID);
            if(ids.size>128) throw fail(503,'Account cleanup is pending. Retry shortly.');
            user.appleRevoked=true;user.applePending={ids:[...ids]};
            if(user.community) user.community.sharing=false;
            for(const [key,value] of Object.entries(state.sessions)) if(value.user===id) delete state.sessions[key];
            for(const [key,value] of Object.entries(state.callbacks)) if(value.user===id) delete state.callbacks[key];
            for(const [key,time] of Object.entries(state.appleEvents)) if(time<Date.now()-90*86400000) delete state.appleEvents[key];
            await save();
          });
          await finishAppleRevocation(id);
          return json(res,200,{ok:true});
        });
      }
      if (url.pathname === '/auth/challenge' && req.method === 'POST') {
        for (const [key,value] of challenges) if (value.expires <= now) challenges.delete(key);
        if (challenges.size >= 10000) throw fail(429,'Please try again shortly.');
        const challenge = random(), nonce = random();
        challenges.set(challenge,{nonce,expires:now+300000});
        return json(res,200,{challenge,nonce});
      }
      if (url.pathname === '/auth/apple' && req.method === 'POST') {
        const input = await body(req), challenge = challenges.get(input.challenge);
        challenges.delete(input.challenge); // Single use, including failed sign-ins.
        if (!challenge || challenge.expires <= now || typeof input.identityToken !== 'string' || typeof input.authorizationCode !== 'string') throw fail(401,'Sign-in expired. Try again.');
        const sub = await verifyAppleToken(input.identityToken,config.appleAudience,challenge.nonce,await keys());
        const tokens = await apple('token',{grant_type:'authorization_code',code:input.authorizationCode});
        const exchangedSub = await verifyAppleToken(tokens.id_token,config.appleAudience,challenge.nonce,await keys());
        if (sub !== exchangedSub || !tokens.refresh_token) throw fail(401,'Apple sign-in could not be verified.');
        const id = createHmac('sha256',config.masterKey).update('apple:'+sub).digest('hex');
        return await locked(id,async()=>{
          if(state.users[id]?.appleRevoked) await finishAppleRevocation(id);
          return serial(async()=>{
          state.users[id] = {...state.users[id],refreshToken:tokens.refresh_token,lastAuthenticatedAt:Date.now()};
          for (const [key,s] of Object.entries(state.sessions)) if (s.expires <= now) delete state.sessions[key];
          // A bounded set of device sessions per account.
          const previous = Object.entries(state.sessions).filter(([,s])=>s.user === id).sort((a,b)=>a[1].expires-b[1].expires);
          while (previous.length >= 10) delete state.sessions[previous.shift()[0]];
          const token = random(), expires = now+30*86400000;
          state.sessions[hash(token)] = {user:id,expires};
          await save(); json(res,200,{token,userID:id,expiresAt:new Date(expires).toISOString()});
          });
        });
      }
      if (url.pathname === '/community/leaderboard' && req.method === 'GET') {
        const month = url.searchParams.get('month') || monthKey(shiftMonth(monthStart(clock()),-1));
        const country = url.searchParams.get('country') || null;
        if (!/^\d{4}-(0[1-9]|1[0-2])$/.test(month) || (country && !/^[A-Z]{2}$/.test(country))) throw fail(400,'Choose a valid comparison month and country.');
        await queue;
        return json(res,200,{month,entries:publicBoard(state.users,month,country)});
      }
      const session = current(req);
      return await locked(session.user,async()=>{
        current(req); // Recheck after waiting on account deletion/sign-out.
        if (url.pathname === '/community/me' && req.method === 'GET') return json(res,200,communityValue(session.user));
        if (url.pathname === '/community/start' && req.method === 'POST') {
          const input = await body(req);
          if (!/^[A-Z]{3}$/.test(input.currency || '')) throw fail(400,'Choose your ledger currency.');
          if (state.users[session.user].community) throw fail(409,'A plan is already being tracked.');
          const date = clock(), dateFrom = shiftMonth(monthStart(date),-3).toISOString().slice(0,10);
          const status = await bankCall(session.user,'status');
          const ledger = await bankCall(session.user,'sync',{dateFrom});
          const tracking = beginTracking(ledger.transactions,status.accountIDs,input.currency,date);
          await serial(async()=>{
            state.users[session.user].community={tracking,sharing:false,nickname:'W-'+randomBytes(3).toString('hex'),country:null,score:null};
            await save();
          });
          return json(res,200,communityValue(session.user));
        }
        if (url.pathname === '/community/privacy' && req.method === 'POST') {
          const input=await body(req), c=state.users[session.user].community;
          if (!c) throw fail(409,'Start tracking a plan first.');
          if (typeof input.sharing !== 'boolean') throw fail(400,'Choose whether to share publicly.');
          // Withdrawing consent needs no profile fields and immediately unlists.
          if (input.sharing) {
            // Country is selected, never inferred from IP.
            const country = input.country || null;
            if (country && !countryCodes.has(country)) throw fail(400,'Choose a country or keep it hidden.');
            await serial(async()=>{const previous={...c};c.country=country;c.sharing=true;try{await save();}catch(e){Object.assign(c,previous);throw e;}});
          } else { await serial(async()=>{c.sharing=false;c.country=null;await save();}); }
          return json(res,200,communityValue(session.user));
        }
        if (url.pathname === '/community/refresh' && req.method === 'POST') {
          const c=state.users[session.user].community;
          if (!c) throw fail(409,'Start tracking a plan first.');
          // Remove an old public score before recomputing; failed/changed coverage must not leave a misleading rank.
          await serial(async()=>{c.score=null;await save();});
          const status=await bankCall(session.user,'status');
          const records=await bankCall(session.user,'sync',{dateFrom:c.tracking.baselineStart.slice(0,10)});
          const score=measureProgress(c.tracking,records.transactions,status.accountIDs,clock());
          await serial(async()=>{c.score=score;await save();});
          return json(res,200,communityValue(session.user));
        }
        if (url.pathname === '/community/tracking' && req.method === 'DELETE') {
          await serial(async()=>{delete state.users[session.user].community;await save();});
          return json(res,200,communityValue(session.user));
        }
        if (url.pathname === '/auth/logout' && req.method === 'POST') {
          return serial(async()=>{delete state.sessions[session.key];await save();json(res,200,{ok:true});});
        }
        if (url.pathname === '/account' && req.method === 'DELETE') {
          if (state.users[session.user].community) await serial(async()=>{state.users[session.user].community.sharing=false;await save();});
          await bankCall(session.user,'disconnect',{});
          await apple('revoke',{token:state.users[session.user].refreshToken,token_type_hint:'refresh_token'});
          await serial(async()=>{
            delete state.users[session.user];
            for (const [key,value] of Object.entries(state.callbacks)) if (value.user === session.user) delete state.callbacks[key];
            for (const [key,value] of Object.entries(state.sessions)) if (value.user === session.user) delete state.sessions[key];
            await save();
          });
          services.delete(session.user);
          await rm(config.dataDir+'/'+session.user,{recursive:true,force:true});
          return json(res,200,{ok:true});
        }
        if (url.pathname === '/disconnect' && req.method === 'POST' && state.users[session.user].community) {
          await serial(async()=>{state.users[session.user].community.sharing=false;state.users[session.user].community.score=null;await save();});
        }
        if (!['/banks','/status','/connect','/sync','/disconnect'].includes(url.pathname)) throw fail(404,'Not found.');
        await forward(session.user,req,res);
      });
    } catch(e) { if (!res.writableEnded) json(res,e.status || 502,{error:e.status ? e.message : 'Connection failed. Please try again.'}); }
  });
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = await createAccountService({origin:process.env.MOCHI_SYNC_ORIGIN,masterKey:process.env.MOCHI_MASTER_KEY,dataDir:process.env.MOCHI_SYNC_DATA_DIR,appleAudience:process.env.APPLE_CLIENT_ID,appleClientSecret:process.env.APPLE_CLIENT_SECRET,appID:process.env.ENABLE_BANKING_APP_ID,keyFile:process.env.ENABLE_BANKING_KEY_FILE});
  server.listen(Number(process.env.PORT || 8787),'127.0.0.1',()=>console.log('Mochi account service ready.'));
}
