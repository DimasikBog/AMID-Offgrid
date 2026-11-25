#!/usr/bin/env python3
"""Opt-in live probe: creates disposable username accounts, verifies RLS/MFA,
and deletes them through the normal authenticated endpoint. Never logs secrets.
Run only against an authorized test/development deployment.
"""
import argparse,base64,hashlib,hmac,json,re,secrets,struct,time,urllib.request,urllib.error
from pathlib import Path

root=Path(__file__).resolve().parents[1]
config=(root/'lib/services/account_config.dart').read_text()
url=re.search(r'accountProjectUrl = "([^"]+)"',config).group(1)
key=re.search(r'accountPublishableKey = "([^"]+)"',config).group(1)
def call(path,data=None,token=None,expected=200,method='POST'):
 headers={'apikey':key,'Content-Type':'application/json'}
 if token:headers['Authorization']='Bearer '+token
 request=urllib.request.Request(url+path,data=None if data is None else json.dumps(data).encode(),headers=headers,method=method)
 try:
  with urllib.request.urlopen(request,timeout=40) as response:status=response.status;raw=response.read()
 except urllib.error.HTTPError as error:status=error.code;raw=error.read()
 parsed=json.loads(raw) if raw else None
 if status!=expected:
  # This endpoint's errors are sanitized; never print Auth response bodies/tokens.
  raise RuntimeError(f'Unexpected status {status} at {path.split("?")[0]}; expected {expected}; code={parsed.get("error") if isinstance(parsed,dict) else "none"}')
 return parsed

def account(data,**kwargs):return call('/functions/v1/account',data,**kwargs)
def work(username,purpose):
 c=account({'action':'challenge','username':username,'purpose':purpose})
 for counter in range(16777217):
  digest=hashlib.sha256((c['token']+'.'+str(counter)).encode()).digest()
  if digest[0]==0 and digest[1]==0 and digest[2]<64:return {'token':c['token'],'counter':counter}
 raise RuntimeError('Proof budget exhausted')
def token_for(username,password):
 result=account({'action':'login','username':username,'password':password})
 session=call('/auth/v1/token?grant_type=refresh_token',{'refresh_token':result['refresh_token']})
 return session['access_token']
def totp(secret):
 key_bytes=base64.b32decode(secret+'='*((8-len(secret)%8)%8))
 value=hmac.new(key_bytes,struct.pack('>Q',int(time.time())//30),hashlib.sha1).digest();offset=value[-1]&15
 return str((int.from_bytes(value[offset:offset+4],'big')&0x7fffffff)%1000000).zfill(6)
def verify_mfa(token):
 factor=call('/auth/v1/factors',{'factor_type':'totp','friendly_name':'Disposable acceptance probe','issuer':'AMID Offgrid'},token=token)
 challenge=call('/auth/v1/factors/'+factor['id']+'/challenge',{},token=token)
 verified=call('/auth/v1/factors/'+factor['id']+'/verify',{'challenge_id':challenge['id'],'code':totp(factor['totp']['secret'])},token=token)
 return verified['access_token']
def main():
 info=account({'action':'info'});assert info['mandatoryMfa'] and info['sessionStorage']=='memory'
 account({'action':'export'},expected=401)
 names=[];sessions=[]
 try:
  for _ in range(2):
   username='offgrid_check_'+secrets.token_hex(4);password=secrets.token_urlsafe(24)
   # Track exact fixture name in stdout only if a failure needs authorized cleanup.
   names.append(username)
   account({'action':'register','username':username,'password':password,'proof':work(username,'register')},expected=201)
   token=token_for(username,password)
   assert call('/rest/v1/offgrid_profiles?select=username',token=token,method='GET')==[]
   token=verify_mfa(token)
   own=call('/rest/v1/offgrid_profiles?select=username',token=token,method='GET')
   assert own==[{'username':username}],own
   sessions.append((username,password,token))
  print('PASS live: registration; password sign-in; AAL1 denied; TOTP; cross-user profile isolation',flush=True)
  username,password,token=sessions[0]
  codes=account({'action':'codes'},token=token)['codes'];assert len(codes)==8
  exported=account({'action':'export'},token=token);assert exported['profile']['username']==username
  account({'action':'logout_all'},token=token)
  account({'action':'export'},token=token,expected=401)
  new_password=secrets.token_urlsafe(24)
  account({'action':'recover','username':username,'password':new_password,'recoveryCode':codes[0],'proof':work(username,'recover')})
  # A used recovery code may never reset the account a second time.
  account({'action':'recover','username':username,'password':secrets.token_urlsafe(24),'recoveryCode':codes[0],'proof':work(username,'recover')},expected=400)
  token=verify_mfa(token_for(username,new_password));sessions[0]=(username,new_password,token)
  print('PASS live: recovery-code issuance; export; revoked-session denial; recovery; replay rejection',flush=True)
  for username,password,token in sessions:
   account({'action':'delete','confirmUsername':username},token=token)
  names=[]
  print('PASS live: both disposable accounts deleted; no email or external messages sent',flush=True)
 except Exception:
  print('Disposable fixture names requiring cleanup:',','.join(names),flush=True)
  raise
if __name__=='__main__':
 parser=argparse.ArgumentParser(description=__doc__)
 parser.add_argument('--allow-live',action='store_true',help='Authorize disposable accounts in the configured deployment')
 args=parser.parse_args()
 if not args.allow_live:parser.error('Explicit --allow-live is required; this creates and deletes disposable accounts.')
 main()
