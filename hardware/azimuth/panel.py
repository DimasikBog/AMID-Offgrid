"""Loopback-only control panel around the tested USB bridge; no synthetic radio data."""
import argparse,collections,json,secrets,subprocess,sys,threading,time,os
from pathlib import Path
from http.server import BaseHTTPRequestHandler,ThreadingHTTPServer
ROOT=Path(__file__).resolve().parent
COMMANDS={'STATUS','STOP','ARM','SCAN','PROBE','JOG 16','JOG -16'}
class Controller:
 def __init__(self,mode,clock=time.monotonic):
  self.mode=mode;self.clock=clock;self.lock=threading.RLock();self.process=None;self.logs=collections.deque(maxlen=150)
  self.maximum=None;self.ready=False;self.state=None;self.position=None;self.homed=None;self.inputs=None;self.result=None;self.state_at=None;self.lease=None;self.expired=False
 def feed(self,line):
  with self.lock:
   self.logs.append(line[:1000])
   if line.startswith('Connected;'):self.ready=True
   if not line.startswith('MEGA: '):return
   a=line[6:].split()
   try:
    if len(a)==4 and a[:2]==['INFO','2']:self.maximum=int(a[3])
    if len(a)==6 and a[0]=='STATE':self.state=int(a[1]);self.position=int(a[3]);self.homed=bool(int(a[5]));self.state_at=self.clock()
    if len(a)==5 and a[:2]==['INPUTS','1']:self.inputs=list(map(int,a[2:]));
    if a and a[0]=='DISARMED':self.state=0;self.homed=False;self.state_at=self.clock()
    if a and a[0]=='FAULT':self.state=9;self.homed=False;self.state_at=self.clock()
    if a and a[0]=='RESULT':self.result=' '.join(a)
   except (ValueError,IndexError):self.logs.append('Unparsed firmware telemetry')
 def alive(self):return self.process is not None and self.process.poll() is None
 def write(self,command):
  if not self.alive():raise ValueError('Bridge is not running')
  self.process.stdin.write(command+'\n');self.process.stdin.flush()
 def heartbeat(self):
  with self.lock:self.lease=self.clock();self.expired=False
 def command(self,command):
  with self.lock:
   if command not in COMMANDS:raise ValueError('Command not allowed')
   if command!='STOP' and (not self.ready or self.lease is None or self.clock()-self.lease>3):raise ValueError('Wait for bridge and an active panel connection')
   if command in ('ARM','SCAN','JOG 16','JOG -16') and (self.state_at is None or self.clock()-self.state_at>3):raise ValueError('Fresh Mega status required')
   if command in ('SCAN','PROBE') and self.mode!='radio':raise ValueError('Real radio mode required')
   self.write(command);self.logs.append('USER: '+command)
 def watchdog(self):
  with self.lock:
   if self.lease is not None and self.clock()-self.lease>3 and not self.expired:
    self.expired=True
    if self.alive():self.write('STOP');self.logs.append('PANEL: browser heartbeat lost; STOP requested')
 def snapshot(self):
  with self.lock:
   return {'alive':self.alive(),'ready':self.ready,'mode':self.mode,'state':self.state,'position':self.position,'nominal_angle':None if not self.maximum or self.position is None or not self.homed else round(self.position/self.maximum*270-135,1),'homed':self.homed,'inputs':self.inputs,'last_result':self.result,'state_age_s':None if self.state_at is None else round(self.clock()-self.state_at,1),'lease_expired':self.expired,'logs':list(self.logs),'physical_verification':'NOT_VERIFIED'}

def handler(controller,token):
 class Handler(BaseHTTPRequestHandler):
  def log_message(self,*args):pass
  def reply(self,code,data,kind='application/json'):
   content=data.encode('utf-8') if isinstance(data,str) else json.dumps(data,ensure_ascii=False).encode('utf-8')
   self.send_response(code);self.send_header('Content-Type',kind+'; charset=utf-8');self.send_header('Content-Length',str(len(content)))
   self.send_header('Cache-Control','no-store');self.send_header('X-Content-Type-Options','nosniff');self.send_header('Referrer-Policy','no-referrer')
   self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'")
   self.end_headers();self.wfile.write(content)
  def trusted_host(self):return self.headers.get('Host')==f'127.0.0.1:{self.server.server_port}'
  def authorized(self):return secrets.compare_digest(self.headers.get('Authorization',''),'Bearer '+token)
  def do_GET(self):
   if not self.trusted_host():self.reply(403,{'error':'Invalid host'});return
   if self.path in ('/','/panel.js','/panel.css'):
    name={'/':'index.html','/panel.js':'panel.js','/panel.css':'panel.css'}[self.path]
    kind={'/':'text/html','/panel.js':'text/javascript','/panel.css':'text/css'}[self.path]
    self.reply(200,(ROOT/'web'/name).read_text(encoding='utf-8'),kind);return
   if self.path=='/api/state' and self.authorized():self.reply(200,controller.snapshot());return
   self.reply(403,{'error':'Unauthorized'})
  def do_POST(self):
   origin=f'http://127.0.0.1:{self.server.server_port}'
   if not self.trusted_host() or not self.authorized() or self.headers.get('Origin')!=origin:self.reply(403,{'error':'Unauthorized origin/token'});return
   try:
    n=int(self.headers.get('Content-Length','0'))
    if not 0<n<=256 or self.headers.get('Content-Type')!='application/json':raise ValueError('Invalid request body')
    payload=json.loads(self.rfile.read(n))
    if not isinstance(payload,dict):raise ValueError('Object required')
    if self.path=='/api/heartbeat':controller.heartbeat()
    elif self.path=='/api/command':controller.command(payload.get('command'))
    else:self.reply(404,{'error':'Unknown path'});return
    self.reply(200,{'ok':True})
   except (ValueError,TypeError,OSError) as ex:self.reply(400,{'error':str(ex)})
 return Handler

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--mega-port',required=True);p.add_argument('--mode',choices=['motor','radio'],default='motor');p.add_argument('--radio-port');p.add_argument('--peer');p.add_argument('--channel',type=int,default=0);p.add_argument('--port',type=int,default=0)
 a=p.parse_args()
 started=False;c=Controller(a.mode);token=secrets.token_urlsafe(32);server=ThreadingHTTPServer(('127.0.0.1',a.port),handler(c,token));server.daemon_threads=True
 command=[sys.executable,'-u',str(ROOT/'bridge.py'),'--mega-port',a.mega_port,'--mode',a.mode,'--external-control','--channel',str(a.channel)]
 if a.radio_port:command+=['--radio-port',a.radio_port]
 if a.peer:command+=['--peer',a.peer]
 try:
  c.process=subprocess.Popen(command,cwd=ROOT,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,encoding='utf-8',errors='replace',bufsize=1,env={**os.environ,'PYTHONIOENCODING':'utf-8'})
  def reader():
   for line in c.process.stdout:c.feed(line.strip())
  threading.Thread(target=reader,daemon=True).start();threading.Thread(target=server.serve_forever,daemon=True).start();started=True
  print(f'Open on this laptop: http://127.0.0.1:{server.server_port}/#{token}',flush=True)
  print('No automatic movement. Keep this terminal open; Ctrl+C stops the bridge.',flush=True)
  last_status=0
  while c.alive():
   c.watchdog()
   if c.ready and time.monotonic()-last_status>=1:
    with c.lock:c.write('CONTROL_PING');c.write('STATUS')
    last_status=time.monotonic()
   time.sleep(.1)
  for line in list(c.logs)[-12:]:print(line,flush=True)
  print('Bridge exited. Review panel event log or use the console to diagnose the serial connection.',flush=True)
 except KeyboardInterrupt:pass
 finally:
  if c.alive():
   try:
    with c.lock:c.write('STOP');c.process.stdin.close()
    c.process.wait(timeout=4)
   except (OSError,subprocess.TimeoutExpired):c.process.terminate()
  if started:server.shutdown()
  server.server_close()
if __name__=='__main__':main()
