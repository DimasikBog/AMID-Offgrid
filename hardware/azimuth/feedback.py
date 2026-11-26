import math

def accepted_ack(packet,peer,request_id):
    if not isinstance(packet,dict):return None
    if packet.get('from')!=peer or packet.get('viaMqtt',False):return None
    d=packet.get('decoded',{})
    if not isinstance(d,dict):return None
    r=d.get('routing')
    if d.get('portnum') not in ('ROUTING_APP',5) or not isinstance(r,dict):return None
    if r.get('errorReason','NONE') not in ('NONE',0) or d.get('requestId')!=request_id:return None
    # Zero values may be omitted by protobuf dict conversion. Metadata is trusted, not independently verified.
    if packet.get('hopStart',0)!=packet.get('hopLimit',0):return None
    a,b=packet.get('rxRssi'),packet.get('rxSnr')
    if b is None and hasattr(packet.get('raw'),'rx_snr'):b=packet['raw'].rx_snr
    if isinstance(a,bool) or isinstance(b,bool) or not isinstance(a,(int,float)) or not isinstance(b,(int,float)):return None
    if not math.isfinite(a) or not math.isfinite(b) or not -150<=a<0 or not -30<=b<=30:return None
    return round(a*10),round(b*10)


class WindowGate:
    """Binds each request to one stationary firmware window; no motor or radio I/O."""
    def __init__(self):self.token=None;self.position=None;self.epoch=0;self.pending=None
    def close(self):self.token=None;self.position=None;self.pending=None;self.epoch+=1
    def open(self,token,position,max_pos):
        if not 0<token<=0xffffffff or not 0<=position<=max_pos:raise ValueError('Invalid firmware window')
        self.close();self.token=token;self.position=position
    def begin_request(self):
        ctx={'token':self.token,'position':self.position,'epoch':self.epoch,'id':None,'done':False}
        self.pending=ctx;return ctx
    def accept(self,packet,peer):
        ctx=self.pending
        if ctx is None or ctx['epoch']!=self.epoch or ctx['token']!=self.token or ctx['done'] or ctx['id'] is None:return None
        values=accepted_ack(packet,peer,ctx['id'])
        if values is None:return None
        ctx['done']=True
        return ctx,values
