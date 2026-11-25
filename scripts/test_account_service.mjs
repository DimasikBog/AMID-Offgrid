import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {createAccountHandler,validUsername,validPassword,makeChallenge,verifyWork,hasWork,compromisedPassword} from '../supabase/functions/account/handler.mjs';
const secret='fixture-only-secret-'.repeat(3);
function proof(challenge){for(let counter=0;counter<16777216;counter++){if(hasWork(createHash('sha256').update(challenge.token+'.'+counter).digest('hex')))return {token:challenge.token,counter};}throw Error('No proof');}
test('credentials are bounded and do not interpret Unicode or injection as usernames',()=>{
 for(const name of ['aa','ADMIN','../file',"a' or true--",'користувач','user@example.com','a'.repeat(33)])assert(!validUsername(name));
 assert(validUsername('amid_123'));assert(!validPassword('short'));assert(!validPassword('passwordpassword'));assert(!validPassword('💚'.repeat(19)));assert(validPassword('a unique long passphrase'));
});
test('work proof binds username, action, deadline and HMAC, and cannot accept arbitrary counter types',async()=>{
 const now=1800000000000;
 const challenge=await makeChallenge(secret,'alice_123','register',now),work=proof(challenge);
 assert(await verifyWork(secret,'alice_123','register',work,now));
 assert(!await verifyWork(secret,'bob_123','register',work,now));
 assert(!await verifyWork(secret,'alice_123','recover',work,now));
 assert(!await verifyWork(secret,'alice_123','register',work,now+181000));
 assert(!await verifyWork(secret,'alice_123','register',{...work,token:work.token+'x'},now));
 assert(!await verifyWork(secret,'alice_123','register',{...work,counter:'0'},now));
});
const make=fetcher=>createAccountHandler({url:'https://example.supabase.co',serviceKey:secret,publicKey:'fixture-public',fetcher});
function req(body,extra={}){return new Request('https://example.supabase.co/functions/v1/account',{method:'POST',headers:{'Content-Type':'application/json',...extra},body:JSON.stringify(body)});}
test('protected actions fail without contacting upstream when no session exists',async()=>{
 const handler=make(()=>{throw Error('must not contact upstream');});
 for(const action of ['codes','export','delete','logout_all'])assert.equal((await handler(req({action}))).status,401);
});
test('CORS rejects unapproved origins and never enables wildcard credential access',async()=>{
 const handler=make(()=>{throw Error('must not contact upstream');});
 const denied=await handler(req({action:'info'},{Origin:'https://attacker.test'}));assert.equal(denied.status,403);assert(!denied.headers.has('Access-Control-Allow-Origin'));
 const allowed=await handler(req({action:'info'},{Origin:'https://dimasikbog.github.io'}));assert.equal(allowed.status,200);assert.equal(allowed.headers.get('Access-Control-Allow-Origin'),'https://dimasikbog.github.io');assert(!allowed.headers.has('Access-Control-Allow-Credentials'));
});
test('body limit applies without Content-Length and raw errors are not exposed',async()=>{
 const handler=make(()=>{throw Error('secret service database stack trace');});
 assert.equal((await handler(req({action:'info',padding:'a'.repeat(17000)}))).status,413);
 const response=await handler(req({action:'challenge',username:'alice_123',purpose:'register'}));assert.equal(response.status,503);assert.deepEqual(await response.json(),{error:'service_unavailable'});
});
test('registration rate and replay rejection are enforced by the server, not the UI',async()=>{
 const now=Date.now(),challenge=await makeChallenge(secret,'alice_123','register',now),work=proof(challenge);
 const handler=make(async(url)=>new Response(JSON.stringify(url.endsWith('offgrid_auth_limit')?true:false),{status:200,headers:{'Content-Type':'application/json'}}));
 const response=await handler(req({action:'register',username:'alice_123',password:'a unique long passphrase',proof:work}));assert.equal(response.status,409);assert.equal((await response.json()).error,'proof_already_used');
 const limited=make(async()=>new Response('false',{status:200}));assert.equal((await limited(req({action:'challenge',username:'alice_123',purpose:'register'}))).status,429);
});

test('breached-password lookup sends only a padded hash prefix; padding does not count as a breach',async()=>{
 const password='fixture long password';const digest=createHash('sha1').update(password).digest('hex').toUpperCase();
 const fetcher=async(url,options)=>{assert.equal(url,'https://api.pwnedpasswords.com/range/'+digest.slice(0,5));assert.equal(options.headers['Add-Padding'],'true');assert(!JSON.stringify(options).includes(password));return new Response(digest.slice(5)+':42\r\n');};
 assert(await compromisedPassword(password,fetcher));
 assert(!await compromisedPassword(password,async()=>new Response(digest.slice(5)+':0\r\n')));
 await assert.rejects(compromisedPassword(password,async()=>new Response('',{status:503})));
});
