import test from 'node:test';
import http from 'node:http';
import assert from 'node:assert/strict';
import {generateKeyPairSync, sign, randomBytes} from 'node:crypto';
import {mkdtemp, rm, readFile} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {createAccountService, verifyAppleToken} from './accounts.mjs';
import {verifyAppleNotification} from './apple-notifications.mjs';

const pair = generateKeyPairSync('rsa',{modulusLength:2048});
const jwk = {...pair.publicKey.export({format:'jwk'}),kid:'test',alg:'RS256',use:'sig'};
const audience = 'dev.wwwwwwww.mochimoney';
function identity(sub,nonce,claims={},header={}) {
  const enc = x=>Buffer.from(JSON.stringify(x)).toString('base64url');
  const payload = enc({alg:'RS256',kid:'test',...header})+'.'+enc({iss:'https://appleid.apple.com',aud:audience,sub,nonce,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+300,...claims});
  return payload+'.'+sign('RSA-SHA256',Buffer.from(payload),pair.privateKey).toString('base64url');
}
test('Apple identity verification rejects forged, expired and mismatched claims',async()=>{
  assert.equal(await verifyAppleToken(identity('alice','nonce'),audience,'nonce',[jwk]),'alice');
  for (const token of [identity('alice','other'),identity('alice','nonce',{aud:'wrong'}),identity('alice','nonce',{iss:'wrong'}),identity('alice','nonce',{exp:1}),identity('alice','nonce',{}, {alg:'none'}),identity('alice','nonce')+'x']) {
    await assert.rejects(verifyAppleToken(token,audience,'nonce',[jwk]));
  }
});
function notification(sub,type,jti,extra={}) {
  return identity('', '', {sub:undefined,nonce:undefined,exp:undefined,jti,events:{type,sub,event_time:Math.floor(Date.now()/1000),...extra}});
}
test('Apple notifications accept signed events without exp and reject forged/incorrect claims',()=>{
  const valid=notification('alice','consent-revoked','event-1');
  assert.equal(verifyAppleNotification(valid,audience,[jwk]).type,'consent-revoked');
  for(const value of [valid+'x',notification('alice','unknown','event-2'),notification('alice','account-deleted','event-3',{event_time:Math.floor(Date.now()/1000)+3600})]) {
    assert.throws(()=>verifyAppleNotification(value,audience,[jwk]));
  }
  assert.throws(()=>verifyAppleNotification(valid,'another-app',[jwk]));
});
test('accounts isolate banks, bind callback state, persist sessions and revoke deletion',async(t)=>{
  const dataDir = await mkdtemp(tmpdir()+'/mochi-accounts-');
  t.after(()=>rm(dataDir,{recursive:true,force:true}));
  const codes = new Map(), authorizations = [], revoked = [];
  let failBankRevocation = false;
  let progressRows = false, comparisonNow = new Date('2026-11-10T12:00:00Z');
  const fetcher = async(url,options)=>{
    if (url.endsWith('/keys')) return {ok:true,json:async()=>({keys:[jwk]})};
    if (url.endsWith('/token')) {
      const input = new URLSearchParams(options.body), token = codes.get(input.get('code'));
      return {ok:Boolean(token),json:async()=>({id_token:token,refresh_token:'private-refresh'})};
    }
    if (url.endsWith('/revoke')) { revoked.push('apple'); return {ok:true}; }
    throw Error('Unexpected Apple endpoint');
  };
  const provider = async(path,method,body)=>{
    if (path.startsWith('/aspsps')) return {aspsps:[{name:'Test Bank',country:'BE'}]};
    if (path === '/auth') {authorizations.push(body);return {url:'https://bank.example/approve'};}
    if (path === '/sessions') return {session_id:'session-'+body.code,accounts:[{uid:body.code,identification_hash:body.code,account_id:{iban:body.code}}]};
    if (method === 'DELETE') {if(failBankRevocation) throw Error('Provider temporarily unavailable');revoked.push(path);return {};}
    if (path.startsWith('/sessions/')) return {status:'AUTHORIZED'};
    if (path.startsWith('/accounts/') && progressRows) return {transactions:['2026-08-15','2026-09-15','2026-10-15','2026-12-15'].flatMap((date,index)=>['CRDT','DBIT'].map(kind=>({status:'BOOK',entry_reference:date+kind,booking_date:date,transaction_amount:{amount:String(kind === 'CRDT' ? 1000 : index === 3 ? 750 : 900),currency:'EUR'},credit_debit_indicator:kind,creditor:{name:'Bank merchant'}})))};
    if (path.startsWith('/accounts/')) return {transactions:[{status:'BOOK',entry_reference:'one',booking_date:'2026-10-10',transaction_amount:{amount:'10',currency:'EUR'},credit_debit_indicator:'DBIT',creditor:{name:path.split('/')[2]}}]};
    throw Error('Unexpected provider endpoint');
  };
  const config = {origin:'https://mochi.test',masterKey:randomBytes(32).toString('base64url'),dataDir,appleAudience:audience,appleClientSecret:'test-only'};
  let server = await createAccountService(config,{fetch:fetcher,provider,now:()=>comparisonNow});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  let port = server.address().port;
  t.after(()=>new Promise(resolve=>server.close(resolve)));
  function request(path,{token,body,method}={}) {
    return new Promise((resolve,reject)=>{
      const req = http.request('http://127.0.0.1:'+port+path,{method:method || (body ? 'POST':'GET'),headers:{Host:'mochi.test',...(token ? {Authorization:'Bearer '+token}:{}),'Content-Type':'application/json'}},res=>{
        let text='';res.on('data',chunk=>text+=chunk);res.on('end',()=>{let data;try{data=JSON.parse(text);}catch{data=text;}resolve({status:res.statusCode,data});});
      });req.on('error',reject);req.end(body ? JSON.stringify(body):undefined);
    });
  }
  async function login(sub) {
    const {data:c} = await request('/auth/challenge',{body:{}});
    const token = identity(sub,c.nonce);codes.set(sub,token);
    const input={challenge:c.challenge,identityToken:token,authorizationCode:sub};
    const result=await request('/auth/apple',{body:input});assert.equal(result.status,200);
    assert.equal((await request('/auth/apple',{body:input})).status,401,'challenge single use');
    return result.data;
  }
  const alice=await login('alice'), bob=await login('bob');
  assert.notEqual(alice.userID,bob.userID);
  assert.equal((await request('/status')).status,401);
  await request('/connect',{token:alice.token,body:{name:'Test Bank',country:'BE'}});
  const consent=authorizations.at(-1);
  const callback=new URL(consent.redirect_url);
  assert.equal(callback.pathname,'/callback');
  assert.equal((await request('/callback/'+bob.userID+'?state='+consent.state+'&code=stolen')).status,401);
  assert.equal((await request(callback.pathname+'?state='+consent.state+'&code=alice-bank&userID='+bob.userID)).status,200);
  assert.equal((await request(callback.pathname+'?state='+consent.state+'&code=replay')).status,400);
  assert.equal((await request('/status',{token:alice.token})).data.accountCount,1);
  assert.equal((await request('/status',{token:bob.token})).data.accountCount,0);
  const payments=await request('/sync',{token:alice.token,body:{dateFrom:'2026-08-01'}});
  assert.equal(payments.data.transactions[0].title,'alice-bank');
  assert.deepEqual((await request('/sync',{token:bob.token,body:{dateFrom:'2026-08-01'}})).data.transactions,[]);
  assert.ok(!(await readFile(dataDir+'/accounts.enc')).includes(Buffer.from(alice.token)));
  await request('/connect',{token:bob.token,body:{name:'Test Bank',country:'BE'}});
  const bobConsent = authorizations.at(-1);
  await new Promise(resolve=>server.close(resolve));
  server=await createAccountService(config,{fetch:fetcher,provider,now:()=>comparisonNow});
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));port=server.address().port;
  assert.equal((await request('/status',{token:alice.token})).data.accountCount,1,'restart keeps isolated state');
  assert.equal((await request('/callback?state='+bobConsent.state+'&code=bob-bank')).status,200,'callback routing survives restart');
  assert.equal((await request('/status',{token:bob.token})).data.accountCount,1);
  progressRows = true;
  assert.deepEqual((await request('/community/leaderboard?month=2026-12')).data.entries,[]);
  assert.equal((await request('/community/start',{token:alice.token,body:{currency:'EUR'}})).data.sharing,false,'tracking defaults private');
  assert.equal((await request('/community/me',{token:bob.token})).data.tracking,false);
  assert.equal((await request('/community/privacy',{token:alice.token,body:{sharing:'true',country:'BE'}})).status,400);
  assert.equal((await request('/community/privacy',{token:alice.token,body:{sharing:true,country:'ZZ'}})).status,400);
  const shared = await request('/community/privacy',{token:alice.token,body:{sharing:true,country:'BE',nickname:'Real Apple Name'}});
  assert.equal(shared.status,200);assert.ok(shared.data.nickname.startsWith('W-'),'public alias is generated, not caller name');
  assert.deepEqual((await request('/community/leaderboard?month=2026-12')).data.entries,[],'incomplete comparisons are not ranked');
  comparisonNow = new Date('2027-01-01T00:00:00Z');
  assert.equal((await request('/community/refresh',{token:alice.token,body:{}})).data.score.improvement,15);
  const board=await request('/community/leaderboard?month=2026-12&country=BE');
  assert.equal(board.data.entries.length,1);
  assert.equal(board.data.entries[0].improvement,15);
  assert.deepEqual(Object.keys(board.data.entries[0]).sort(),['country','improvement','month','nickname','rank','updatedAt']);
  await request('/community/privacy',{token:alice.token,body:{sharing:false}});
  assert.deepEqual((await request('/community/leaderboard?month=2026-12')).data.entries,[],'withdrawal removes result immediately');
  assert.equal((await request('/community/me',{token:alice.token})).data.country,null,'withdrawal clears country');
  await login('alice');
  assert.equal((await request('/community/me',{token:alice.token})).data.tracking,true,'Apple sign-in preserves tracking and consent');
  await request('/community/privacy',{token:alice.token,body:{sharing:true,country:''}});
  assert.equal((await request('/community/leaderboard?month=2026-12')).data.entries[0].country,null,'country can remain hidden');
  assert.equal((await request('/community/tracking',{token:alice.token,method:'DELETE'})).data.tracking,false);
  assert.deepEqual((await request('/community/leaderboard?month=2026-12')).data.entries,[],'deleting tracking removes public result');
  assert.equal((await request('/account',{token:alice.token,method:'DELETE'})).status,200);
  assert.ok(revoked.includes('/sessions/session-alice-bank') && revoked.includes('apple'));
  assert.equal((await request('/status',{token:alice.token})).status,401);
  assert.equal((await request('/status',{token:bob.token})).status,200);
  assert.equal((await request('/auth/logout',{token:bob.token,body:{}})).status,200);
  assert.equal((await request('/status',{token:bob.token})).status,401);
  const charlie=await login('charlie'), dave=await login('dave');
  await request('/connect',{token:charlie.token,body:{name:'Test Bank',country:'BE'}});
  const charlieConsent=authorizations.at(-1);
  await request('/callback?state='+charlieConsent.state+'&code=charlie-bank');
  const sendEvent=payload=>request('/auth/apple/notifications',{body:{payload}});
  assert.equal((await sendEvent(notification('charlie','email-disabled','mail-event'))).status,200);
  assert.equal((await request('/status',{token:charlie.token})).status,200,'email changes do not remove accounts');
  const revoke=notification('charlie','consent-revoked','revocation-event');
  failBankRevocation=true;
  assert.equal((await sendEvent(revoke)).status,502,'failed provider revocation is retryable');
  assert.equal((await request('/status',{token:charlie.token})).status,401,'sessions fail closed before provider cleanup');
  failBankRevocation=false;
  assert.equal((await sendEvent(revoke)).status,200);
  assert.ok(revoked.includes('/sessions/session-charlie-bank'));
  assert.equal((await request('/status',{token:dave.token})).status,200,'other accounts remain isolated');
  const charlieAgain=await login('charlie');
  assert.equal((await sendEvent(revoke)).status,200,'duplicate event is idempotent');
  assert.equal((await request('/status',{token:charlieAgain.token})).status,200,'old event cannot delete a new authorization');
  assert.equal((await sendEvent(notification('dave','consent-revoked','out-of-order',{event_time:Math.floor(Date.now()/1000)-120}))).status,200);
  assert.equal((await request('/status',{token:dave.token})).status,200,'out-of-order events do not undo newer authentication');
  assert.equal((await sendEvent(notification('charlie','account-deleted','delete-event'))).status,200);
  assert.equal((await request('/status',{token:charlieAgain.token})).status,401,'Apple account deletion removes app sessions');

});
