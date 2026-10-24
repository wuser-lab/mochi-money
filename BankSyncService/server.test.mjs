import http from 'node:http';
import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp, readFile, rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {createService,normalize} from './server.mjs';

const account = {uid:'account-1',identification_hash:'stable-account',account_id:{iban:'BE00000000000001'}};
const transaction = {entry_reference:'entry-1',transaction_id:'unstable',status:'BOOK',transaction_amount:{amount:'12.34',currency:'EUR'},credit_debit_indicator:'DBIT',booking_date:'2026-10-24',creditor:{name:'Test groceries'},creditor_account:{iban:'BE00000000000002'}};
test('uses stable references, detects own accounts and ignores pending',()=>{
  const record = normalize(transaction,account,new Set(['BE00000000000002']),'Test bank');
  assert.equal(record.isInternalTransfer,true); assert.equal(record.kind,'Expense'); assert.equal(record.amount,12.34);
  assert.equal(record.bankID,normalize({...transaction,transaction_id:'changed'}, {...account,uid:'new-session-uid'},new Set(),'Test bank').bankID);
  assert.equal(normalize({...transaction,status:'PDNG'},account,new Set(),'Test bank'),null);
  assert.throws(()=>normalize({...transaction,entry_reference:null},account,new Set(),'Test bank'),/stable entry/);
});
test('authorization, state replay protection, pagination, cache, encryption and revocation',async()=>{
  const dir = await mkdtemp(tmpdir()+'/mochi-bank-test-');
  const token = 'test-only-connection-key-'.repeat(3); let nonce; let calls = []; let loop = false;
  const provider = async(path,method,body)=>{
    calls.push(path);
    if (path.startsWith('/aspsps')) return {aspsps:[{name:'Test bank',country:'BE',maximum_consent_validity:86400}]};
    if (path === '/auth') {nonce=body.state;assert.equal(body.access.transactions,true);assert.equal(body.access.balances,false);return {url:'https://auth.enablebanking.com/test'};}
    if (path === '/sessions') return {session_id:'session-1',accounts:[account]};
    if (path === '/sessions/session-1') return method === 'DELETE' ? {} : {status:'AUTHORIZED'};
    if (path.includes('/transactions?')) {
      const page = new URL('https://example.test'+path).searchParams.get('continuation_key');
      return page ? {transactions:[{...transaction,entry_reference:'entry-2'}],continuation_key:loop ? 'page2':null} : {transactions:[transaction,{...transaction,status:'PDNG'}],continuation_key:'page2'};
    }
    throw Error('Unexpected mock request');
  };
  const config = {token,origin:'http://127.0.0.1:8787',dataDir:dir};
  const server = await createService(config,provider); await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const base = 'http://127.0.0.1:'+server.address().port;
  const request = (path,body,auth=true,host='127.0.0.1:8787') => new Promise((resolve,reject)=>{
    const req = http.request(base+path,{method:body ? 'POST':'GET',headers:{Host:host,...(auth ? {Authorization:'Bearer '+token} : {}),'Content-Type':'application/json'}},res=>{
      let data='';res.on('data',piece=>data+=piece);res.on('end',()=>resolve({status:res.statusCode,json:async()=>JSON.parse(data)}));
    });req.on('error',reject);req.end(body ? JSON.stringify(body):undefined);
  });
  try {
    assert.equal((await request('/status',null,false)).status,401);assert.equal(calls.length,0);
    assert.equal((await request('/status',null,true,'attacker.test')).status,403);
    assert.equal((await request('/connect',{name:'Unknown',country:'BE'})).status,400);
    assert.equal((await request('/connect',{name:'Test bank',country:'BE'})).status,200);
    assert.equal((await request('/callback?state=wrong&code=fake',null,false)).status,400);
    assert.equal((await request('/callback?state='+nonce+'&code=fake',null,false)).status,200);
    assert.equal((await request('/callback?state='+nonce+'&code=fake',null,false)).status,400);
    const result = await (await request('/sync',{dateFrom:'2026-10-24'})).json();
    assert.equal(result.transactions.length,2);
    const count = calls.length;assert.equal((await request('/sync',{dateFrom:'2026-10-24'})).status,200);assert.equal(calls.length,count);
    assert.equal((await readFile(dir+'/sessions.enc')).includes(Buffer.from('session-1')),false);
    loop = true;
    const failure = await request('/sync',{dateFrom:'2026-10-23'});assert.equal(failure.status,502);assert.match((await failure.json()).error,/pagination/);
    assert.equal((await request('/disconnect',{})).status,200);
    assert.equal((await (await request('/status')).json()).accountCount,0);
  } finally {await new Promise(r=>server.close(r));await rm(dir,{recursive:true,force:true});}
});
