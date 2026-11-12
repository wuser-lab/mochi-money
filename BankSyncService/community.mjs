// ISO 3166-1 codes from the public-domain IANA tzdb iso3166.tab.
export const countryCodes = new Set('AD AE AF AG AI AL AM AO AQ AR AS AT AU AW AX AZ BA BB BD BE BF BG BH BI BJ BL BM BN BO BQ BR BS BT BV BW BY BZ CA CC CD CF CG CH CI CK CL CM CN CO CR CU CV CW CX CY CZ DE DJ DK DM DO DZ EC EE EG EH ER ES ET FI FJ FK FM FO FR GA GB GD GE GF GG GH GI GL GM GN GP GQ GR GS GT GU GW GY HK HM HN HR HT HU ID IE IL IM IN IO IQ IR IS IT JE JM JO JP KE KG KH KI KM KN KP KR KW KY KZ LA LB LC LI LK LR LS LT LU LV LY MA MC MD ME MF MG MH MK ML MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ NA NC NE NF NG NI NL NO NP NR NU NZ OM PA PE PF PG PH PK PL PM PN PR PS PT PW PY QA RE RO RS RU RW SA SB SC SD SE SG SH SI SJ SK SL SM SN SO SR SS ST SV SX SY SZ TC TD TF TG TH TJ TK TL TM TN TO TR TT TV TW TZ UA UG UM US UY UZ VA VC VE VG VI VN VU WF WS YE YT ZA ZM ZW'.split(' '));
// UTC calendar months keep every participant in the same comparison period.
export const monthStart = date => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1));
export const shiftMonth = (date, n) => new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth()+n, 1));
export const monthKey = date => date.toISOString().slice(0,7);
const error = message => Object.assign(Error(message),{status:422});
export function rateFor(records, start, end, currency, requiredMonths) {
  const rows = records.filter(r=>new Date(r.date)>=start && new Date(r.date)<end && !r.isInternalTransfer);
  if (rows.some(r=>r.currency !== currency || !Number.isFinite(r.amount) || r.amount<=0 || !['Income','Expense'].includes(r.kind))) throw error('Comparison needs valid payments in one currency. Currency conversion is not supported.');
  const incomes = rows.filter(r=>r.kind === 'Income');
  if (new Set(incomes.map(r=>r.date.slice(0,7))).size < requiredMonths) throw error('Not enough income history for a complete comparison yet.');
  const income = incomes.reduce((sum,r)=>sum+r.amount,0);
  const spending = rows.filter(r=>r.kind === 'Expense').reduce((sum,r)=>sum+r.amount,0);
  if (!(income>0) || !Number.isFinite(income) || !Number.isFinite(spending)) throw error('Income is needed to calculate a savings rate.');
  const rate = (income-spending)/income*100;
  if (!Number.isFinite(rate)) throw error("Income and spending do not produce a usable savings rate.");
  return rate;
}
export function beginTracking(records, accountIDs, currency, now) {
  const end = monthStart(now), start = shiftMonth(end,-3);
  if (!accountIDs.length) throw error('Connect and sync your banks first.');
  return {
    startedAt:now.toISOString(),baselineStart:start.toISOString(),
    baselineRate:rateFor(records,start,end,currency,3),currency,
    accountIDs:[...new Set(accountIDs)].sort(),eligibleMonth:monthKey(shiftMonth(end,1))
  };
}
export function measureProgress(tracking, records, accountIDs, now) {
  if (JSON.stringify([...new Set(accountIDs)].sort()) !== JSON.stringify(tracking.accountIDs)) throw error('Your connected accounts changed. Comparisons need the same account coverage; this result cannot be ranked.');
  const end = monthStart(now), start = shiftMonth(end,-1);
  if (monthKey(start)<tracking.eligibleMonth) return null;
  const savingsRate = rateFor(records,start,end,tracking.currency,1);
  const improvement=Math.round((savingsRate-tracking.baselineRate)*10)/10;
  if (!Number.isFinite(improvement)) throw error('The change cannot be compared reliably.');
  return {month:monthKey(start),improvement,updatedAt:now.toISOString()};
}
export function publicBoard(users, month, country) {
  const scores = Object.values(users).flatMap(user=>{
    const c=user.community;
    if (!c?.sharing || !c.score || c.score.month !== month || (country && c.country !== country)) return [];
    // An explicit allowlist prevents accidental leakage of IDs, rates and balances.
    return [{nickname:c.nickname,country:c.country || null,improvement:c.score.improvement,month:c.score.month,updatedAt:c.score.updatedAt}];
  }).sort((a,b)=>b.improvement-a.improvement || a.nickname.localeCompare(b.nickname));
  let rank=0,previous;
  return scores.slice(0,100).map((entry,i)=>{
    if (entry.improvement !== previous) rank=i+1;
    previous=entry.improvement;
    return {...entry,rank};
  });
}
