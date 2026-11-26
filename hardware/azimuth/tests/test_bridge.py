import sys,unittest,copy
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]));from bridge import accepted_ack
class AckTests(unittest.TestCase):
 def setUp(self):self.p={'from':123,'decoded':{'portnum':'ROUTING_APP','routing':{},'requestId':77},'rxRssi':-91,'rxSnr':4.5,'hopStart':0,'hopLimit':0}
 def test_direct_ack(self):self.assertEqual(accepted_ack(self.p,123,77),(-910,45))
 def test_wrong_request(self):self.assertIsNone(accepted_ack(self.p,123,78))
 def test_wrong_peer(self):self.assertIsNone(accepted_ack(self.p,124,77))
 def test_mqtt(self):self.p['viaMqtt']=True;self.assertIsNone(accepted_ack(self.p,123,77))
 def test_relayed(self):self.p.update(hopStart=3,hopLimit=2);self.assertIsNone(accepted_ack(self.p,123,77))
 def test_nak(self):self.p['decoded']['routing']['errorReason']='NO_ROUTE';self.assertIsNone(accepted_ack(self.p,123,77))
 def test_missing_metrics(self):del self.p['rxRssi'];self.assertIsNone(accepted_ack(self.p,123,77))
 def test_nonfinite(self):self.p['rxSnr']=float('nan');self.assertIsNone(accepted_ack(self.p,123,77))
 def test_malformed(self):
  for value in [None,{}, {'decoded':None}, {'from':123,'decoded':None}]:self.assertIsNone(accepted_ack(value,123,77))
 def test_zero_snr_from_raw_protobuf(self):
  from meshtastic.protobuf import mesh_pb2
  self.p['raw']=mesh_pb2.MeshPacket();del self.p['rxSnr']
  self.assertEqual(accepted_ack(self.p,123,77),(-910,0))
 def test_no_routing(self):self.p['decoded']={'requestId':77,'portnum':'ROUTING_APP'};self.assertIsNone(accepted_ack(self.p,123,77))
if __name__=='__main__':unittest.main()
