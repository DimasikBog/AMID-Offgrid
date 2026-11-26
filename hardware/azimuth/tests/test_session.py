import sys,unittest,tempfile,json,csv
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from feedback import WindowGate
from journal import Journal,parse_info,parse_result

def packet(i=77):return {'from':123,'decoded':{'portnum':'ROUTING_APP','routing':{},'requestId':i},'rxRssi':-91,'rxSnr':4.5}
class GateTests(unittest.TestCase):
 def test_old_window_and_duplicate(self):
  g=WindowGate();g.open(1,0,3072);old=g.begin_request();old['id']=77
  g.open(2,100,3072);self.assertIsNone(g.accept(packet(),123))
  new=g.begin_request();new['id']=78;self.assertIsNone(g.accept(packet(),123))
  self.assertIsNotNone(g.accept(packet(78),123));self.assertIsNone(g.accept(packet(78),123))
 def test_reset_reused_token(self):
  g=WindowGate();g.open(1,0,3072);g.begin_request()['id']=77;g.close();g.open(1,0,3072)
  self.assertIsNone(g.accept(packet(),123))
 def test_nak_does_not_consume_ack(self):
  g=WindowGate();g.open(1,0,3072);g.begin_request()['id']=77;p=packet();p['decoded']['routing']['errorReason']='NO_ROUTE'
  self.assertIsNone(g.accept(p,123));self.assertIsNotNone(g.accept(packet(),123))
 def test_invalid_position(self):
  with self.assertRaises(ValueError):WindowGate().open(1,3073,3072)
class JournalTests(unittest.TestCase):
 def test_protocol(self):
  self.assertEqual(parse_info('INFO 2 4096 3072'),(4096,3072))
  for s in ['INFO 1 4096 3072','INFO 2 4096 999','INFO 2 -1 -1']:
   with self.assertRaises(ValueError):parse_info(s)
 def test_valid_and_missing(self):
  self.assertEqual(parse_result('RESULT 1 0 0 2 1 -910 45 ENOUGH',3072)['rssi_dbm'],-91)
  r=parse_result('RESULT 1 0 0 1 0 NA NA TIMEOUT',3072);self.assertIsNone(r['rssi_dbm'])
 def test_reject_contradictions(self):
  for s in ['RESULT 1 0 0 1 1 -910 45 ENOUGH','RESULT 1 0 0 0 0 0 0 TIMEOUT','RESULT 1 3073 0 2 1 -910 45 ENOUGH','RESULT 1 0 9 2 1 -910 45 ENOUGH']:
   with self.assertRaises(ValueError):parse_result(s,3072)
 def test_report_and_dedup(self):
  with tempfile.TemporaryDirectory() as d:
   j=Journal(Path(d)/'session',{'mode':'motor'},3072)
   self.assertIn('ще немає',(j.path/'report.html').read_text())
   r=parse_result('RESULT 1 0 0 0 0 NA NA TIMEOUT',3072)
   self.assertTrue(j.record(r,1));self.assertFalse(j.record(r,1));self.assertTrue(j.record(r,2))
   r={**r,'finish_reason':'<script>alert(1)</script>'};j.record(r,3)
   page=(j.path/'report.html').read_text();self.assertNotIn('<script>',page);self.assertIn('&lt;script&gt;',page)
   j.event('stop',reason='test');j.close()
   with (Path(d)/'session/measurements.csv').open(encoding='utf-8-sig') as f:rows=list(csv.DictReader(f))
   self.assertEqual(len(rows),3);self.assertEqual(rows[0]['rssi_dbm'],'');self.assertEqual(rows[0]['nominal_azimuth_deg'],'-135.0')
   self.assertEqual(json.loads((Path(d)/'session/events.jsonl').read_text())['kind'],'stop')
if __name__=='__main__':unittest.main()
