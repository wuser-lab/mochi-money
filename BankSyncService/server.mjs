import http from 'node:http';
import https from 'node:https';
import {readFile, writeFile, mkdir, rename} from 'node:fs/promises';
import {createPrivateKey, sign, randomBytes, createHash, createCipheriv, createDecipheriv, timingSafeEqual} from 'node:crypto';
import {pathToFileURL} from 'node:url';

const digest = value => createHash('sha256').update(value).digest('hex');
export function normalize(t, account, ownIBANs, bank) {
  if (t.status !== 'BOOK') return null;
  if (!t.entry_reference) throw Error('A bank transaction has no stable entry reference; sync stopped to avoid duplicates.');
  const amount = Number(t.transaction_amount?.amount);
  const date = t.booking_date || t.value_date;
  if (!Number.isFinite(amount) || amount === 0 || !/^\d{4}-\d{2}-\d{2}$/.test(date || '') || !['DBIT','CRDT'].includes(t.credit_debit_indicator)) throw Error('Bank returned an unsupported transaction.');
  const outgoing = t.credit_debit_indicator === 'DBIT';
  const other = outgoing ? t.creditor : t.debtor;
  const counterpart = outgoing ? t.creditor_account?.iban : t.debtor_account?.iban;
  return {
    bankID: digest(account.identification_hash + '\0' + t.entry_reference),
    accountID: digest(account.identification_hash), currency: t.transaction_amount.currency,
    title: other?.name || t.remittance_information?.[0] || 'Bank payment',
    amount: Math.abs(amount), kind: outgoing ? 'Expense' : 'Income',
    date: date + 'T12:00:00Z', note: ['Bank sync: ' + bank, ...(t.remittance_information || []), t.note || ''].filter(Boolean).join(' | '),
    isInternalTransfer: Boolean(counterpart && ownIBANs.has(counterpart.replace(/\s/g, '').toUpperCase()))
  };
}

export async function createService(config, providerOverride) {
  if (!config.token || config.token.length < 32) throw Error('MOCHI_SYNC_TOKEN must contain at least 32 characters.');
  const origin = new URL(config.origin);
  if (origin.protocol !== 'https:' && !(origin.protocol === 'http:' && ['localhost','127.0.0.1'].includes(origin.hostname))) throw Error('Use HTTPS or a loopback URL.');
  const key = createHash('sha256').update('mochi-state-v1\0' + config.token).digest();
  const privateKey = providerOverride ? null : createPrivateKey(await readFile(config.keyFile));
  async function provider(path, method = 'GET', body) {
    if (providerOverride) return providerOverride(path, method, body);
    const now = Math.floor(Date.now()/1000);
    const enc = x => Buffer.from(JSON.stringify(x)).toString('base64url');
    const unsigned = enc({typ:'JWT',alg:'RS256',kid:config.appID}) + '.' + enc({iss:'enablebanking.com',aud:'api.enablebanking.com',iat:now,exp:now+300});
    const jwt = unsigned + '.' + sign('RSA-SHA256', Buffer.from(unsigned), privateKey).toString('base64url');
    const response = await fetch('https://api.enablebanking.com' + path, {method, redirect:'error', signal:AbortSignal.timeout(60000), headers:{Authorization:'Bearer '+jwt,'Content-Type':'application/json'},body:body ? JSON.stringify(body) : undefined});
    if (method === 'DELETE' && [404,410].includes(response.status)) return {};
    if (!response.ok) throw Error(response.status === 401 || response.status === 403 ? 'Bank authorization expired or access was denied. Reconnect your bank.' : `Bank provider request failed (${response.status}). Try again later.`);
    return response.status === 204 ? {} : response.json();
  }
  await mkdir(config.dataDir, {recursive:true,mode:0o700});
  const file = config.dataDir + '/sessions.enc';
  let state = {sessions:[],pending:{}};
  try {
    const bytes = await readFile(file); const decipher = createDecipheriv('aes-256-gcm',key,bytes.subarray(0,12));
    decipher.setAuthTag(bytes.subarray(12,28)); state = JSON.parse(Buffer.concat([decipher.update(bytes.subarray(28)),decipher.final()]));
  } catch (e) { if (e.code !== 'ENOENT') throw Error('Unable to decrypt bank sessions. Restore the original sync token.'); }
  let saving = Promise.resolve();
  function save() {
    saving = saving.then(async () => {
    const iv = randomBytes(12); const cipher = createCipheriv('aes-256-gcm',key,iv);
    const payload = Buffer.concat([cipher.update(JSON.stringify(state)),cipher.final()]);
    await writeFile(file+'.tmp',Buffer.concat([iv,cipher.getAuthTag(),payload]),{mode:0o600}); await rename(file+'.tmp',file);
    });
    return saving;
  }
  let syncing = false, lastSync = 0, cached = null;
  const json = (res,status,data) => {res.writeHead(status,{'Content-Type':'application/json','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'});res.end(JSON.stringify(data));};
  const authorized = req => {
    const received = Buffer.from(req.headers.authorization || ''); const expected = Buffer.from('Bearer ' + config.token);
    return received.length === expected.length && timingSafeEqual(received,expected);
  };
  async function body(req) {
    let text = ''; for await (const piece of req) {text += piece; if (text.length > 4096) throw Error('Request too large.');} return JSON.parse(text || '{}');
  }
  const handler = async (req,res) => {
    try {
      // Reject DNS rebinding and browser-based cross-origin requests. No CORS is enabled.
      if (req.headers.host !== origin.host) return json(res,403,{error:'Invalid host.'});
      const url = new URL(req.url,origin);
      if (url.pathname === '/callback' && req.method === 'GET') {
        const callbackState = url.searchParams.get('state');
        const pending = Object.hasOwn(state.pending,callbackState) ? state.pending[callbackState] : null;
        if (!pending || pending.expires < Date.now()) return json(res,400,{error:'Connection request expired. Start again in Mochi Money.'});
        delete state.pending[url.searchParams.get('state')]; await save();
        if (url.searchParams.has('error') || !url.searchParams.get('code')) return json(res,400,{error:'Bank connection was not approved. Return to Mochi Money to retry.'});
        const session = await provider('/sessions','POST',{code:url.searchParams.get('code')});
        if (!session.session_id || !Array.isArray(session.accounts) || session.accounts.some(a=>!a.identification_hash || !a.uid)) throw Error('Bank returned an invalid session.');
        state.retired = [...(state.retired || []), ...state.sessions.filter(s=>s.bank.name === pending.bank.name && s.bank.country === pending.bank.country)];
        state.sessions = state.sessions.filter(s=>s.bank.name !== pending.bank.name || s.bank.country !== pending.bank.country);
        state.sessions.push({...session,bank:pending.bank}); state.revision = randomBytes(16).toString("hex"); await save(); cached = null; lastSync = 0;
        res.writeHead(200,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'",'Referrer-Policy':'no-referrer'});
        return res.end('<!doctype html><title>Mochi Money</title><h1>Bank connected</h1><p>Return to Mochi Money. Your payments will sync shortly.</p>');
      }
      if (!authorized(req)) return json(res,401,{error:'Connection service key is missing or incorrect.'});
      if (req.headers.origin) return json(res,403,{error:'Use the Mochi Money app.'});
      if (url.pathname === '/banks' && req.method === 'GET') {
        const result = await provider('/aspsps?country=BE&psu_type=personal&service=AIS');
        const france = await provider('/aspsps?country=FR&psu_type=personal&service=AIS');
        const banks = [...(result.aspsps || []), ...(france.aspsps || []).filter(b=>b.name === 'Revolut')];
        return json(res,200,{banks:banks.map(b=>({name:b.name,country:b.country}))});
      }
      if (url.pathname === '/status' && req.method === 'GET') return json(res,200,{revision:state.revision || "",connectedBanks:state.sessions.map(s=>s.bank.name),accountCount:state.sessions.reduce((n,s)=>n+s.accounts.length,0)});
      if (url.pathname === '/connect' && req.method === 'POST') {
        const input = await body(req);
        if (!['BE','FR'].includes(input.country) || (input.country === 'FR' && input.name !== 'Revolut')) return json(res,400,{error:'Unsupported bank country.'});
        const available = await provider('/aspsps?country='+input.country+'&psu_type=personal&service=AIS');
        const bank = (available.aspsps || []).find(b=>b.name === input.name && b.country === input.country);
        if (!bank) return json(res,400,{error:'Choose a bank from the available list.'});
        const nonce = randomBytes(32).toString('hex');
        const result = await provider('/auth','POST',{access:{transactions:true,balances:false,valid_until:new Date(Date.now()+1000*Math.min(90*86400,Number(bank.maximum_consent_validity) || 86400)).toISOString()},aspsp:{name:bank.name,country:bank.country},state:nonce,redirect_url:origin.origin+'/callback',psu_type:'personal'});
        const authURL = new URL(result.url); if (authURL.protocol !== 'https:') throw Error('Provider returned an unsafe authorization URL.');
        state.pending = Object.fromEntries(Object.entries(state.pending).filter(([,v])=>v.expires>Date.now()));
        state.pending[nonce] = {bank:{name:bank.name,country:bank.country},expires:Date.now()+900000}; await save();
        return json(res,200,{url:result.url});
      }
      if (url.pathname === '/sync' && req.method === 'POST') {
        const {dateFrom} = await body(req);
        if (!/^\d{4}-\d{2}-\d{2}$/.test(dateFrom || '')) return json(res,400,{error:'A valid sync start date is required.'});
        if (syncing) return json(res,409,{error:'A sync is already running.'});
        if (cached && cached.dateFrom === dateFrom && Date.now()-lastSync<300000) return json(res,200,cached);
        syncing = true;
        try {
          const ownIBANs = new Set(state.sessions.flatMap(s=>s.accounts.map(a=>a.account_id?.iban?.replace(/\s/g,'').toUpperCase()).filter(Boolean)));
          const records = new Map();
          for (const session of state.sessions) {
            const status = await provider('/sessions/'+encodeURIComponent(session.session_id));
            if (status.status !== 'AUTHORIZED') throw Error('Bank permission expired. Reconnect '+session.bank.name+'.');
            for (const account of session.accounts) {
              let continuation; const seen = new Set(); let pages = 0;
              do {
                const params = new URLSearchParams({date_from:dateFrom,transaction_status:'BOOK'});
                if (continuation) params.set('continuation_key',continuation);
                const page = await provider('/accounts/'+encodeURIComponent(account.uid)+'/transactions?'+params);
                if (!Array.isArray(page.transactions)) throw Error('Bank returned an invalid transaction page.');
                for (const t of page.transactions) { const record = normalize(t,account,ownIBANs,session.bank.name); if (record) records.set(record.bankID,record); }
                continuation = page.continuation_key;
                if (continuation && (seen.has(continuation) || ++pages>1000)) throw Error('Bank pagination did not finish; no transactions were imported.');
                seen.add(continuation);
              } while (continuation);
            }
          }
          cached = {dateFrom,transactions:[...records.values()],syncedAt:new Date().toISOString()}; lastSync = Date.now();
          return json(res,200,cached);
        } finally {syncing = false;}
      }
      if (url.pathname === '/disconnect' && req.method === 'POST') {
        if (syncing) return json(res,409,{error:'Wait for the current sync to finish.'});
        // Persist each successful revocation so partial failures can be retried.
        while (state.sessions.length) {await provider('/sessions/'+encodeURIComponent(state.sessions[0].session_id),'DELETE');state.sessions.shift();await save();}
        while (state.retired?.length) {await provider('/sessions/'+encodeURIComponent(state.retired[0].session_id),'DELETE');state.retired.shift();await save();}
        state.pending = {}; await save(); cached = null; return json(res,200,{ok:true});
      }
      return json(res,404,{error:'Not found.'});
    } catch (e) {json(res,502,{error:e.message || 'Connection service failed.'});}
  };
  if (config.tlsCertFile && config.tlsKeyFile) {
    return https.createServer({cert:await readFile(config.tlsCertFile),key:await readFile(config.tlsKeyFile),minVersion:"TLSv1.2"},handler);
  }
  return http.createServer(handler);
}
if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const config = {token:process.env.MOCHI_SYNC_TOKEN,appID:process.env.ENABLE_BANKING_APP_ID,keyFile:process.env.ENABLE_BANKING_KEY_FILE,origin:process.env.MOCHI_SYNC_ORIGIN || 'http://127.0.0.1:8787',dataDir:process.env.MOCHI_SYNC_DATA_DIR,tlsCertFile:process.env.MOCHI_TLS_CERT_FILE,tlsKeyFile:process.env.MOCHI_TLS_KEY_FILE};
  if (!config.appID || !config.keyFile || !config.dataDir) throw Error('Set ENABLE_BANKING_APP_ID, ENABLE_BANKING_KEY_FILE and MOCHI_SYNC_DATA_DIR.');
  const server = await createService(config); server.listen(Number(process.env.PORT || 8787),'127.0.0.1',()=>console.log('Mochi bank connection service is ready.'));
}
