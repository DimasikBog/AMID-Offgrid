// No runtime dependencies. Secrets exist only in the Edge Function environment.
const encoder = new TextEncoder();
const usernamePattern = /^[a-z0-9_]{3,32}$/;
const allowedOrigin = 'https://dimasikbog.github.io';
const hex = bytes => Array.from(new Uint8Array(bytes), b => b.toString(16).padStart(2, '0')).join('');
export const hash = async value => hex(await crypto.subtle.digest('SHA-256', encoder.encode(value)));
export function validUsername(value) { return typeof value === 'string' && usernamePattern.test(value); }
export function validPassword(value) {
  return typeof value === 'string' && Array.from(value).length >= 16 && encoder.encode(value).length <= 72 && new Set(Array.from(value)).size >= 5 &&
    !['passwordpassword', '1234567890123456', 'abcdefghijklmnop'].includes(value.toLowerCase());
}
const random = () => hex(crypto.getRandomValues(new Uint8Array(16)));
const b64 = value => btoa(value).replaceAll('+','-').replaceAll('/','_').replaceAll('=','');
const unb64 = value => atob(value.replaceAll('-','+').replaceAll('_','/').padEnd(Math.ceil(value.length/4)*4,'='));
const equal = (a,b) => {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0; for (let i=0; i<a.length; i++) diff |= a.charCodeAt(i)^b.charCodeAt(i); return diff===0;
};
export function hasWork(digest, bits = 18) {
  const zeros = Math.floor(bits/4), rest = bits%4;
  return digest.startsWith('0'.repeat(zeros)) && (!rest || parseInt(digest[zeros],16) < (1 << (4-rest)));
}
export async function sign(secret, value) {
  const key = await crypto.subtle.importKey('raw',encoder.encode(secret),{name:'HMAC',hash:'SHA-256'},false,['sign']);
  return hex(await crypto.subtle.sign('HMAC',key,encoder.encode(value)));
}
export async function makeChallenge(secret, username, purpose, now = Date.now()) {
  const payload = b64(JSON.stringify({v:1,sub:await hash(username),purpose,exp:Math.floor(now/1000)+180,nonce:random()}));
  return {token:payload+'.'+await sign(secret,'offgrid-work:'+payload),bits:18};
}
export async function verifyWork(secret, username, purpose, proof, now = Date.now()) {
  if (!proof || typeof proof.token !== 'string' || proof.token.length > 700 || !Number.isSafeInteger(proof.counter) || proof.counter<0 || proof.counter>16777216) return false;
  const [payload,signature,extra] = proof.token.split('.');
  if (extra || !equal(signature,await sign(secret,'offgrid-work:'+payload))) return false;
  let data; try {data=JSON.parse(unb64(payload));} catch {return false;}
  if (data.v!==1 || data.sub!==await hash(username) || data.purpose!==purpose || data.exp<Math.floor(now/1000) || data.exp>Math.floor(now/1000)+180) return false;
  return hasWork(await hash(proof.token+'.'+proof.counter));
}
export async function compromisedPassword(password, fetcher = fetch) {
  // SHA-1 is used only for the HIBP range lookup, never for stored passwords.
  const digest=hex(await crypto.subtle.digest('SHA-1',encoder.encode(password))).toUpperCase();
  const response=await fetcher('https://api.pwnedpasswords.com/range/'+digest.slice(0,5),{
    headers:{'Add-Padding':'true','User-Agent':'AMID-Offgrid-Account/0.7'},signal:AbortSignal.timeout(7000),
  });
  if(!response.ok)throw new Error('Password range check unavailable');
  const text=await response.text();if(text.length>300000)throw new Error('Password range response too large');
  return text.split('\n').some(line=>{const [suffix,count]=line.trim().split(':');return suffix===digest.slice(5)&&Number(count)>0;});
}
class Failure extends Error { constructor(status,code){super(code);this.status=status;this.code=code;} }
export async function readBoundedBody(request, timeoutMs=8000) {
  const reader=request.body?.getReader();
  if (!reader) throw new Failure(400,'invalid_request');
  let timer,bytes=0;const chunks=[];
  const deadline=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Failure(408,'request_timeout')),timeoutMs);});
  try {
    for (;;) {
      const {value,done}=await Promise.race([reader.read(),deadline]);
      if(done)break;
      bytes+=value.length;
      if(bytes>16384)throw new Failure(413,'request_too_large');
      chunks.push(value);
    }
    const raw=new Uint8Array(bytes);let offset=0;
    for(const chunk of chunks){raw.set(chunk,offset);offset+=chunk.length;}
    return raw;
  } catch(error) {
    void reader.cancel().catch(()=>{});
    throw error;
  } finally {clearTimeout(timer);reader.releaseLock();}
}
const fields={info:[],challenge:['username','purpose'],register:['username','password','proof'],
  login:['username','password','proof'],recover:['username','password','proof','recoveryCode'],
  codes:[],export:[],logout_all:[],delete:['confirmUsername']};
export function createAccountHandler({url, serviceKey, publicKey, fetcher=fetch, now=Date.now, bodyTimeoutMs=8000}) {
  if (!url?.startsWith('https://') || !serviceKey || !publicKey) throw new Error('Account service configuration missing');
  const serviceHeaders = {apikey:serviceKey,Authorization:'Bearer '+serviceKey,'Content-Type':'application/json'};
  async function api(path,body,method='POST',headers=serviceHeaders) {
    const response = await fetcher(url+path,{method,headers,body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
    const data = await response.json().catch(()=>null);
    if (!response.ok) throw new Failure(response.status===429?429:400,response.status===429?'rate_limited':'request_failed');
    return data;
  }
  const rpc = (name,body) => api('/rest/v1/rpc/'+name,body);
  async function limit(bucket,count,seconds) {
    if (!await rpc('offgrid_auth_limit',{p_bucket:bucket,p_limit:count,p_seconds:seconds})) throw new Failure(429,'rate_limited');
  }
  async function profile(username) {
    const rows = await api('/rest/v1/offgrid_profiles?username=eq.'+encodeURIComponent(username)+'&select=user_id,username,display_name,created_at',undefined,'GET');
    return rows?.[0]??null;
  }
  async function verified(request,recent=false) {
    const bearer = request.headers.get('authorization')??'';
    if (!/^Bearer [A-Za-z0-9_.-]{50,8192}$/.test(bearer)) throw new Failure(401,'sign_in_required');
    const token=bearer.slice(7);
    // Validate with Auth before reading any JWT claim; decoded data alone is never trusted.
    let user; try {user=await api('/auth/v1/user',undefined,'GET',{apikey:publicKey,Authorization:bearer});} catch {throw new Failure(401,'sign_in_required');}
    let claims; try {claims=JSON.parse(unb64(token.split('.')[1]));} catch {throw new Failure(401,'sign_in_required');}
    if (claims.sub!==user.id || claims.aal!=='aal2') throw new Failure(403,'mfa_required');
    const current = await api('/rest/v1/rpc/offgrid_session_ok',{},'POST',{apikey:publicKey,Authorization:bearer,'Content-Type':'application/json'});
    if (current!==true) throw new Failure(401,'sign_in_required');
    if (recent && !claims.amr?.some(a=>a.method==='totp' && a.timestamp>Math.floor(now()/1000)-300)) throw new Failure(403,'fresh_mfa_required');
    return user;
  }
  return async request => {
    const origin=request.headers.get('origin');
    const headers = {'Content-Type':'application/json; charset=utf-8','Cache-Control':'no-store','X-Content-Type-Options':'nosniff','Referrer-Policy':'no-referrer','Vary':'Origin'};
    if (origin===allowedOrigin) Object.assign(headers,{'Access-Control-Allow-Origin':origin,'Access-Control-Allow-Headers':'authorization, apikey, content-type, x-client-info','Access-Control-Allow-Methods':'POST, OPTIONS','Access-Control-Max-Age':'600'});
    const reply=(data,status=200)=>new Response(JSON.stringify(data),{status,headers});
    if (origin && origin!==allowedOrigin) return reply({error:'origin_not_allowed'},403);
    if (request.method==='OPTIONS') return new Response(null,{status:204,headers});
    if (request.method!=='POST') return reply({error:'method_not_allowed'},405);
    try {
      const type=request.headers.get('content-type')??'';
      if (!/^application\/json(?:\s*;.*)?$/i.test(type)) throw new Failure(415,'json_required');
      if (Number(request.headers.get('content-length')??0)>16384) throw new Failure(413,'request_too_large');
      // Stream bound also covers absent or forged Content-Length.
      const raw=await readBoundedBody(request,bodyTimeoutMs);
      let body;try {body=JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(raw));}catch{throw new Failure(400,'invalid_request');}
      if (!body || typeof body!=='object' || Array.isArray(body)) throw new Failure(400,'invalid_request');
      const action=body.action;
      if (typeof action!=='string' || !Object.hasOwn(fields,action)) throw new Failure(404,'unknown_action');
      if(Object.keys(body).some(key=>key!=='action'&&!fields[action].includes(key)))throw new Failure(400,'invalid_request');
      if (action==='info') return reply({version:2,registration:true,mandatoryMfa:true,proofBits:18,loginProofRequired:true,sessionStorage:'memory',contactEmailCollected:false});
      if (['challenge','register','login','recover'].includes(action)) {
        if (!validUsername(body.username)) throw new Failure(400,'invalid_username');
        const subject=await hash(body.username);
        if(action==='challenge') {
          if(!['register','recover','login'].includes(body.purpose)) throw new Failure(400,'invalid_request');
          await limit('challenge:global',1200,3600);
          await limit('challenge:'+subject,20,900);
          return reply(await makeChallenge(serviceKey,body.username,body.purpose,now()));
        }
        if (!validPassword(body.password)) throw new Failure(400,'invalid_credentials');
        if(!await verifyWork(serviceKey,body.username,action,body.proof,now())) throw new Failure(400,'invalid_proof');
        if(!await rpc('offgrid_auth_consume_proof',{p_hash:await hash(body.proof.token)}))throw new Failure(409,'proof_already_used');
        // Invalid/replayed work must not exhaust a victim's sign-in budget.
        await limit(action+':global',action==='login'?600:60,3600);
        await limit(action+':'+subject,action==='login'?10:4,900);
        if(action!=='login' && await compromisedPassword(body.password,fetcher))throw new Failure(400,'password_compromised');
        if(action==='register') {
          if(await profile(body.username)) throw new Failure(409,'username_unavailable');
          const email=crypto.randomUUID()+'@accounts.amid.invalid';
          const nonce=random()+random();
          await rpc('offgrid_auth_prepare',{p_email:email,p_nonce_hash:await hash(nonce)});
          const created=await api('/auth/v1/admin/users',{email,password:body.password,email_confirm:true,app_metadata:{amid_username:body.username},user_metadata:{registration_nonce:nonce}});
          try {
            await api('/rest/v1/offgrid_profiles',{user_id:created.id,username:body.username});
          } catch(error) {
            // A username race never leaves a new usable, unmapped account behind.
            await api('/auth/v1/admin/users/'+created.id,{},'DELETE');throw error;
          }
          return reply({created:true,needsMfa:true},201);
        }
        const own=await profile(body.username);
        if(!own) throw new Failure(400,'invalid_credentials');
        const user=await api('/auth/v1/admin/users/'+own.user_id,undefined,'GET');
        if(action==='login') {
          try {
            const session=await api('/auth/v1/token?grant_type=password',{email:user.email,password:body.password},'POST',{apikey:publicKey,'Content-Type':'application/json'});
            return reply({refresh_token:session.refresh_token});
          } catch {throw new Failure(400,'invalid_credentials');}
        }
        if(typeof body.recoveryCode!=='string' || !/^[a-f0-9]{32}$/.test(body.recoveryCode))throw new Failure(400,'invalid_credentials');
        if(!await rpc('offgrid_consume_code',{p_user:own.user_id,p_hash:body.recoveryCode}))throw new Failure(400,'invalid_credentials');
        await rpc('offgrid_revoke_sessions',{p_user:own.user_id});
        const factors=await api('/auth/v1/admin/users/'+own.user_id+'/factors',undefined,'GET');
        for(const factor of (Array.isArray(factors)?factors:factors?.factors??[]))await api('/auth/v1/admin/users/'+own.user_id+'/factors/'+factor.id,{},'DELETE');
        await api('/auth/v1/admin/users/'+own.user_id,{password:body.password},'PUT');
        return reply({recovered:true,needsMfa:true});
      }
      if(['codes','export','delete','logout_all'].includes(action)) {
        const user=await verified(request,['codes','delete'].includes(action));
        await limit(action+':'+user.id,action==='codes'?5:30,3600);
        if(action==='codes') {
          const codes=Array.from({length:8},()=>random());
          await rpc('offgrid_replace_codes',{p_user:user.id,p_hashes:codes});return reply({codes});
        }
        if(action==='export') {
          const rows=await api('/rest/v1/offgrid_profiles?user_id=eq.'+user.id+'&select=username,display_name,created_at',undefined,'GET');
          return reply({format:'AMID_ACCOUNT_EXPORT',version:1,profile:rows[0]??null});
        }
        if(action==='delete' && body.confirmUsername!==user.app_metadata?.amid_username)throw new Failure(400,'confirmation_required');
        await rpc('offgrid_revoke_sessions',{p_user:user.id});
        if(action==='delete')await api('/auth/v1/admin/users/'+user.id,{},'DELETE');
        return reply({done:true});
      }
      throw new Failure(404,'unknown_action');
    } catch(error) {
      // Do not return upstream bodies, SQL messages, email aliases or credentials.
      if(error instanceof Failure)return reply({error:error.code},error.status);
      return reply({error:'service_unavailable'},503);
    }
  };
}
