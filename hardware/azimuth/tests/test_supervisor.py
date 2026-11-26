import io,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import bridge
class Device:
 def __init__(self):self.first=True;self.writes=[];self.closed=False
 def reset_input_buffer(self):pass
 def readline(self):
  if self.first:self.first=False;return b'INFO 2 4096 3072\n'
  return b''
 def write(self,data):self.writes.append(data)
 def close(self):self.closed=True
class Clock:
 def __init__(self):self.now=0
 def __call__(self):self.now+=.1;return self.now
class SupervisorTests(unittest.TestCase):
 def test_missing_parent_heartbeat_stops_bridge(self):
  d=Device();clock=Clock()
  with tempfile.TemporaryDirectory() as folder,patch('serial.Serial',return_value=d),patch.object(bridge.time,'sleep'),patch.object(bridge.time,'monotonic',clock),patch.object(bridge.threading.Thread,'start'),patch.object(sys,'argv',['bridge.py','--mega-port','TEST','--external-control','--log-dir',folder]),patch('sys.stdout',new=io.StringIO()) as output:
   bridge.main();self.assertIn('Supervisor heartbeat lost',output.getvalue())
  self.assertTrue(d.closed);self.assertEqual(d.writes[-1],b'STOP\n');self.assertNotIn(b'ARM\n',d.writes)
if __name__=='__main__':unittest.main()
