import test from 'node:test';
import assert from 'node:assert/strict';
import {beginTracking,measureProgress,publicBoard} from './community.mjs';
const row=(date,kind,amount,currency='EUR',transfer=false)=>({date:date+'T12:00:00Z',kind,amount,currency,isInternalTransfer:transfer});
const baseline=['2026-08-15','2026-09-15','2026-10-15'].flatMap(date=>[row(date,'Income',1000),row(date,'Expense',900)]);
const start=new Date('2026-11-10T12:00:00Z');
const tracking=beginTracking(baseline,['account-a'],'EUR',start);
test('compares complete UTC months, excludes internal transfers and normalizes currencies by rate',()=>{
  assert.equal(tracking.baselineRate,10);
  assert.equal(tracking.eligibleMonth,'2026-12');
  const records=[...baseline,row('2026-12-15','Income',2000),row('2026-12-15','Expense',1500),row('2026-12-16','Expense',99999,'EUR',true),row('2027-01-01','Expense',99999)];
  assert.equal(measureProgress(tracking,records,['account-a'],new Date('2026-12-31T23:59:59Z')),null);
  assert.deepEqual(measureProgress(tracking,records,['account-a'],new Date('2027-01-01T00:00:00Z')),{month:'2026-12',improvement:15,updatedAt:'2027-01-01T00:00:00.000Z'});
  const usd=baseline.map(r=>({...r,currency:'USD',amount:r.amount*50}));
  assert.equal(beginTracking(usd,['a'],'USD',start).baselineRate,10,'absolute currency units do not change rates');
});
test('rejects incomplete, mixed-currency and changed account coverage',()=>{
  assert.throws(()=>beginTracking(baseline.slice(2),['a'],'EUR',start),/history/);
  assert.throws(()=>beginTracking([...baseline,row('2026-09-20','Expense',5,'USD')],['a'],'EUR',start),/one currency/);
  assert.throws(()=>measureProgress(tracking,baseline,['different'],new Date('2027-01-01')),/coverage/);
  assert.throws(()=>measureProgress(tracking,baseline,['account-a'],new Date('2027-01-01')),/history/);
});
test('public allowlist, consent, period filtering, shared ranks and negative progress',()=>{
  const entry=(sharing,improvement,month='2026-12')=>({community:{sharing,nickname:'Mochi-test',country:'BE',tracking:{baselineRate:10},score:{improvement,month,updatedAt:'2027-01-01T00:00:00Z'}},refreshToken:'secret'});
  const people={a:entry(true,15),b:entry(false,99),c:entry(true,-5),d:entry(true,15),e:entry(true,99,'2026-11')};
  const board=publicBoard(people,'2026-12');
  assert.deepEqual(board.map(r=>r.rank),[1,1,3]);
  assert.equal(board.at(-1).improvement,-5);
  assert.ok(board.every(r=>Object.keys(r).sort().join(',')==='country,improvement,month,nickname,rank,updatedAt'));
  assert.deepEqual(publicBoard(people,'2026-12','US'),[]);
  people.a.community.sharing=false;
  assert.equal(publicBoard(people,'2026-12').length,2);
});
