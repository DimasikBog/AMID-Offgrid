"""Serial protocol fixtures only; no motor or RF measurements are performed."""
import sys,tempfile,unittest,io,csv
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
import bridge
class SerialFixture:
 def __init__(self,lines):self.lines=iter(lines);self.writes=[];self.closed=False
 def write(self,data):self.writes.append(data)
 def reset_input_buffer(self):pass
 def readline(self):
  try:return (next(self.lines)+'\n').encode()
  except StopIteration:raise KeyboardInterrupt
 def close(self):self.closed=True
class SessionTests(unittest.TestCase):
 def run_bridge(self,serial,d):
  with patch('serial.Serial',return_value=serial),patch.object(bridge.time,'sleep'),patch.object(bridge.threading.Thread,'start'),patch.object(sys,'argv',['bridge.py','--mega-port','TEST','--log-dir',d]),patch('sys.stdout',new=io.StringIO()):bridge.main()
 def test_old_firmware_stops(self):
  s=SerialFixture(['INFO 1 4096 3072'])
  with tempfile.TemporaryDirectory() as d:
   with self.assertRaises(ValueError):self.run_bridge(s,d)
  self.assertTrue(s.closed);self.assertEqual(s.writes[-1],b'STOP\n');self.assertNotIn(b'ARM\n',s.writes)
 def test_complete_and_incomplete_window(self):
  s=SerialFixture(['INFO 2 4096 3072','WINDOW 1 0','RESULT 1 0 0 2 1 -910 45 ENOUGH','CLOSE 1','WINDOW 2 100','DISARMED'])
  with tempfile.TemporaryDirectory() as d:
   self.run_bridge(s,d)
   p=next(Path(d).glob('*/measurements.csv'))
   with p.open(encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
   self.assertEqual(len(rows),1);self.assertEqual(rows[0]['window'],'1');self.assertEqual(rows[0]['verification'],'unverified')
  self.assertTrue(s.closed);self.assertEqual(s.writes[-1],b'STOP\n');self.assertNotIn(b'ARM\n',s.writes)
 def test_orphan_result_not_recorded(self):
  s=SerialFixture(['INFO 2 4096 3072','WINDOW 1 0','RESULT 2 0 0 2 1 -910 45 ENOUGH'])
  with tempfile.TemporaryDirectory() as d:
   self.run_bridge(s,d)
   with next(Path(d).glob('*/measurements.csv')).open(encoding='utf-8-sig') as f:self.assertEqual(list(csv.DictReader(f)),[])
   self.assertIn('orphan_result',next(Path(d).glob('*/events.jsonl')).read_text())
if __name__=='__main__':unittest.main()
