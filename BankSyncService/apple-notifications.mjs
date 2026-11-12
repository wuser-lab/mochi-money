import {createPublicKey,verify} from 'node:crypto';

// Apple's account notifications have iat/jti/events, but need not have exp.
// See https://developer.apple.com/documentation/signinwithapple/processing-changes-for-sign-in-with-apple-accounts
export function verifyAppleNotification(token,audience,keys,now=Date.now()) {
  try {
    if (typeof token !== 'string') throw Error();
    const parts=token.split('.');if(parts.length!==3) throw Error();
    const header=JSON.parse(Buffer.from(parts[0],'base64url'));
    const claims=JSON.parse(Buffer.from(parts[1],'base64url'));
    const key=keys.find(k=>k.kid===header.kid && k.kty==='RSA' && k.alg==='RS256' && k.use==='sig');
    if(header.alg!=='RS256' || !key || !verify('RSA-SHA256',Buffer.from(parts.slice(0,2).join('.')),createPublicKey({key,format:'jwk'}),Buffer.from(parts[2],'base64url'))) throw Error();
    if(claims.iss!=='https://appleid.apple.com' || claims.aud!==audience || !Number.isFinite(claims.iat) || claims.iat<0 || claims.iat*1000>now+60000 || typeof claims.jti!=='string' || !claims.jti || claims.jti.length>512) throw Error();
    if(claims.exp!==undefined && (!Number.isFinite(claims.exp) || claims.exp*1000<=now)) throw Error();
    const event=typeof claims.events==='string' ? JSON.parse(claims.events) : claims.events;
    if(!event || !['email-enabled','email-disabled','consent-revoked','account-deleted'].includes(event.type) || typeof event.sub!=='string' || !event.sub || event.sub.length>256 || !Number.isFinite(event.event_time) || event.event_time<0 || event.event_time*1000>now+60000) throw Error();
    return {type:event.type,sub:event.sub,eventTime:event.event_time*1000,jti:claims.jti};
  } catch { throw Object.assign(Error('Apple notification could not be verified.'),{status:401}); }
}
