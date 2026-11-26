"""Local HTTP and process fixtures, never physical measurements."""
import io,json,sys,threading,unittest,http.client
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from panel import Controller,handler,ThreadingHTTPServer
class Process:
 def __init__(self):self.stdin=io.StringIO();self.dead=False
 def poll(self):return 0 if self.dead else None
class Clock:
 def __init__(self):self.now=100
 def __call__(self):return self.now
class ControlTests(unittest.TestCase):
 def setUp(self):
  self.clock=Clock();self.c=Controller('motor',self.clock);self.c.process=Process()
 def ready(self):self.c.feed('Connected; motor is DISARMED.');self.c.feed('MEGA: STATE 0 POS 0 HOMED 0');self.c.heartbeat()
 def test_no_motion_on_connect(self):self.ready();self.assertEqual(self.c.process.stdin.getvalue(),'')
 def test_requires_heartbeat_and_ready(self):
  with self.assertRaises(ValueError):self.c.command('ARM')
  self.assertEqual(self.c.process.stdin.getvalue(),'')
 def test_stop_without_lease(self):self.c.command('STOP');self.assertEqual(self.c.process.stdin.getvalue(),'STOP\n')
 def test_unknown_and_radio_commands(self):
  self.ready()
  for cmd in ['S 1 1 -900 50','ARM\nSCAN','SCAN','PROBE']:
   with self.assertRaises(ValueError):self.c.command(cmd)
 def test_watchdog_once_and_no_auto_resume(self):
  self.ready();self.c.command('ARM');self.clock.now+=4;self.c.watchdog();self.c.watchdog()
  self.assertEqual(self.c.process.stdin.getvalue(),'ARM\nSTOP\n');self.c.heartbeat()
  self.assertEqual(self.c.process.stdin.getvalue(),'ARM\nSTOP\n')
 def test_fresh_status_required(self):
  self.ready();self.clock.now+=4;self.c.heartbeat()
  with self.assertRaises(ValueError):self.c.command('ARM')
 def test_telemetry_no_initial_angle(self):
  self.assertIsNone(self.c.snapshot()['nominal_angle']);self.c.feed('MEGA: INFO 2 4096 3072');self.c.feed('MEGA: STATE 3 POS 1536 HOMED 1');self.c.feed('MEGA: INPUTS 1 0 1 0')
  self.assertEqual(self.c.snapshot()['nominal_angle'],0);self.assertEqual(self.c.snapshot()['inputs'],[0,1,0])
 def test_log_bounded(self):
  for _ in range(500):self.c.feed('x'*2000)
  self.assertEqual(len(self.c.snapshot()['logs']),150);self.assertEqual(len(self.c.snapshot()['logs'][0]),1000)
class HttpTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.c=Controller('motor');cls.c.process=Process();cls.server=ThreadingHTTPServer(('127.0.0.1',0),handler(cls.c,'test-secret'));cls.thread=threading.Thread(target=cls.server.serve_forever,daemon=True);cls.thread.start()
 @classmethod
 def tearDownClass(cls):cls.server.shutdown();cls.server.server_close();cls.thread.join()
 def request(self,path,body=None,token='test-secret',origin=True,host=None):
  port=self.server.server_port;conn=http.client.HTTPConnection('127.0.0.1',port,timeout=2)
  headers={'Authorization':'Bearer '+token}
  if host:headers['Host']=host
  if body is not None:
   headers['Content-Type']='application/json'
   if origin:headers['Origin']=f'http://127.0.0.1:{port}'
  conn.request('POST' if body is not None else 'GET',path,body=json.dumps(body) if body is not None else None,headers=headers)
  r=conn.getresponse();result=(r.status,dict(r.getheaders()),r.read());conn.close();return result
 def test_state_requires_token(self):self.assertEqual(self.request('/api/state',token='wrong')[0],403)
 def test_origin_required(self):self.assertEqual(self.request('/api/command',{'command':'STOP'},origin=False)[0],403)
 def test_host_required(self):self.assertEqual(self.request('/api/state',host='evil.example')[0],403)
 def test_static_csp_no_secret(self):
  code,headers,body=self.request('/');self.assertEqual(code,200);self.assertIn("frame-ancestors 'none'",headers['Content-Security-Policy']);self.assertNotIn(b'test-secret',body)
 def test_authorized_heartbeat_and_stop(self):
  self.assertEqual(self.request('/api/heartbeat',{})[0],200);self.assertEqual(self.request('/api/command',{'command':'STOP'})[0],200)
 def test_unknown_command_rejected(self):self.assertEqual(self.request('/api/command',{'command':'OTHER'})[0],400)
if __name__=='__main__':unittest.main()
