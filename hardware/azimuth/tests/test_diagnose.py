"""Synthetic serial fixtures. No physical wiring verification is claimed."""
import io,json,sys,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from diagnose import inspect,parse_inputs
from launcher import build_command
class Device:
 def __init__(self,lines):self.lines=iter(lines);self.writes=[];self.closed=False
 def reset_input_buffer(self):pass
 def write(self,data):self.writes.append(data)
 def readline(self):return (next(self.lines,'')+'\n').encode()
 def close(self):self.closed=True
class Clock:
 def __init__(self):self.value=0
 def __call__(self):self.value+=.05;return self.value
class DiagnoseTests(unittest.TestCase):
 def test_parse(self):
  self.assertEqual(parse_inputs('INPUTS 1 0 1 0'),(0,1,0))
  for s in ['INPUTS 0 0 1 0','INPUTS 1 0 2 0','INPUTS 1 0 1','INPUTS 1 true 0 0']:
   with self.assertRaises(ValueError):parse_inputs(s)
 def test_observations_and_only_safe_commands(self):
  d=Device(['INFO 2 4096 3072','STATE 0 POS 0 HOMED 0','INPUTS 1 0 0 0','INPUTS 1 1 0 0','INPUTS 1 0 1 0','INPUTS 1 0 0 1','INPUTS 1 0 0 0'])
  with tempfile.TemporaryDirectory() as folder,patch('serial.Serial',return_value=d),patch('sys.stdout',new=io.StringIO()):
   result=inspect('TEST',3,Path(folder)/'report.json',clock=Clock(),sleep=lambda _:None)
   self.assertEqual(result['status'],'OBSERVATIONS_ONLY');self.assertEqual(len(result['inputs_seen']),4)
   self.assertEqual(json.loads((Path(folder)/'report.json').read_text())['physical_verification'],'NOT_VERIFIED')
  self.assertTrue(d.closed);self.assertEqual(d.writes[-1],b'STOP\n')
  self.assertTrue(set(d.writes)<={b'STOP\n',b'PING\n',b'STATUS\n'})
 def test_old_firmware_missing_inputs(self):
  d=Device(['INFO 2 4096 3072'])
  with tempfile.TemporaryDirectory() as folder,patch('serial.Serial',return_value=d):
   p=Path(folder)/'report.json'
   with self.assertRaises(ValueError):inspect('TEST',3,p,clock=Clock(),sleep=lambda _:None)
   self.assertEqual(json.loads(p.read_text())['status'],'NOT_READY')
  self.assertTrue(d.closed);self.assertEqual(d.writes[-1],b'STOP\n')
 def test_unexpected_motion_stops_and_records_error(self):
  d=Device(['INFO 2 4096 3072','STATE 4 POS 15 HOMED 1'])
  with tempfile.TemporaryDirectory() as folder,patch('serial.Serial',return_value=d):
   p=Path(folder)/'report.json'
   with self.assertRaises(ValueError):inspect('TEST',3,p,clock=Clock(),sleep=lambda _:None)
   self.assertIn('armed/moving',json.loads(p.read_text())['error'])
  self.assertTrue(d.closed);self.assertEqual(d.writes[-1],b'STOP\n')
 def test_malformed_inputs_stops(self):
  d=Device(['INFO 2 4096 3072','INPUTS 1 7 0 0'])
  with tempfile.TemporaryDirectory() as folder,patch('serial.Serial',return_value=d):
   with self.assertRaises(ValueError):inspect('TEST',3,Path(folder)/'report.json',clock=Clock(),sleep=lambda _:None)
  self.assertTrue(d.closed)
class LauncherTests(unittest.TestCase):
 def test_no_automatic_motor_commands(self):
  for mode in ('1','2','3','4','5'):
   command=build_command(mode,'COM5','COM7','!a1b2c3d4')
   self.assertFalse(set(command)&{'ARM','SCAN','JOG'})
 def test_separate_ports_and_valid_peer(self):
  for radio,peer in [('COM5','!a1b2c3d4'),('com5','!a1b2c3d4'),('COM7','abc'),('','!a1b2c3d4')]:
   with self.assertRaises(ValueError):build_command('3','COM5',radio,peer)
 def test_argument_is_not_shell_code(self):
  command=build_command('2','COM5 & echo unsafe')
  self.assertIn('COM5 & echo unsafe',command)
if __name__=='__main__':unittest.main()
