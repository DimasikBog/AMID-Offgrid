"""Physical bench bridge: Mega motor control + Meshtastic serial radio; never synthetic RSSI."""
import argparse,queue,threading,time,secrets,math,json,re
from pathlib import Path
from datetime import datetime,timezone

from feedback import accepted_ack,WindowGate
from journal import Journal,parse_info,parse_result,explain

def main():
    import serial
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mega-port',required=True);p.add_argument('--radio-port');p.add_argument('--peer',help='Second own node, e.g. !a1b2c3d4')
    p.add_argument('--mode',choices=['motor','radio'],default='motor');p.add_argument('--channel',type=int,default=0)
    p.add_argument('--interval',type=float,default=30,help='Minimum seconds between probes; must be 30..35 for this firmware')
    p.add_argument('--log-dir',default='sessions',help='Local CSV, JSONL and offline HTML session reports')
    p.add_argument('--external-control',action='store_true',help='Require supervisor CONTROL_PING every 3 seconds')
    args=p.parse_args()
    if not 30<=args.interval<=35 or not math.isfinite(args.interval):p.error('interval must be finite and 30..35 seconds (80-second sample window)')
    if not 0<=args.channel<=7:p.error('channel must be 0..7')
    if args.mode=='radio' and (not args.radio_port or not re.fullmatch(r'![0-9a-fA-F]{8}',args.peer or '')):p.error('radio mode requires --radio-port and --peer !xxxxxxxx')
    events=queue.Queue();radio=None;receiver=None;journal=None;gate=WindowGate();probe_requested=False;last_probe=-1e9;hb=-1e9;stop=threading.Event()
    def console():
        while not stop.is_set():
            try:s=input().strip().upper()
            except EOFError:events.put(('quit',None));return
            if s=='CONTROL_PING' and args.external_control:events.put(('control_ping',None));continue
            if s in ('ARM','SCAN','STOP','STATUS','PROBE') or re.fullmatch(r'JOG -?\d{1,2}',s):events.put(('cmd',s))
            else:print('Commands: STATUS, JOG 16, JOG -16, ARM, SCAN, STOP, PROBE; Ctrl+C exits',flush=True)
    mega=serial.Serial(args.mega_port,115200,timeout=.05,write_timeout=.5)
    def send(s):mega.write((s+'\n').encode('ascii'))
    try:
        # Opening Mega USB resets many boards. No automatic arming or motion.
        time.sleep(2);mega.reset_input_buffer();send('STOP');send('STATUS')
        deadline=time.monotonic()+3;calibration=None
        while time.monotonic()<deadline:
            line=mega.readline().decode('ascii',errors='replace').strip()
            if line:print('MEGA:',line,flush=True)
            if line.startswith('INFO '):calibration=parse_info(line);break
        if calibration is None:raise ValueError('Flash v0.2 firmware first: INFO 2 handshake missing')
        steps_rev,max_pos=calibration
        session=Path(args.log_dir)/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%SZ')+'_'+secrets.token_hex(3))
        journal=Journal(session,{'version':'0.5.0','mode':args.mode,'peer':args.peer,'steps_rev':steps_rev,'protocol':2},max_pos)
        print('Session report:',session/'report.html',flush=True)
        if args.mode=='radio':
            from meshtastic.serial_interface import SerialInterface
            from meshtastic.protobuf import portnums_pb2
            radio=SerialInterface(devPath=args.radio_port)
            peer=int(args.peer[1:],16)
            if not radio.myInfo or peer in (0,0xffffffff,radio.myInfo.my_node_num):raise ValueError('Peer must be the SECOND unicast node')
            lora=radio.localNode.localConfig.lora
            if lora.region!=3 or not lora.tx_enabled or lora.override_duty_cycle:raise ValueError('Configure EU_868, TX enabled, duty-cycle override OFF before testing')
            print(f'LOCAL !{radio.myInfo.my_node_num:08x}',flush=True)
            from pubsub import pub
            def receiver(packet,interface):
                if interface is radio:events.put(('rx',packet))
            pub.subscribe(receiver,'meshtastic.receive')
        threading.Thread(target=console,daemon=True).start()
        print('Connected; motor is DISARMED. Check direction/NC switches. Type ARM, wait HOMED, then SCAN.',flush=True)
        last_control=time.monotonic()
        while True:
            now=time.monotonic()
            if args.external_control and now-last_control>3:
                print('Supervisor heartbeat lost; STOP and exit',flush=True);return
            if now-hb>=1:send('PING');hb=now
            raw=mega.readline()
            if raw:
                line=raw.decode('ascii',errors='replace').strip();print('MEGA:',line,flush=True)
                journal.event('firmware',line=line)
                explanation=explain(line)
                if explanation:print(explanation,flush=True)
                if line.startswith('INFO ') and parse_info(line)!=calibration:
                    raise ValueError('Calibration changed during session; stopping')
                if line.startswith('RESULT '):
                    result=parse_result(line,max_pos)
                    if result['window']==gate.token and result['position_steps']==gate.position:
                        journal.record(result,gate.epoch)
                    else:journal.event('orphan_result',line=line)
                    gate.close()
                if line.startswith(('HELLO','FAULT','DISARMED','CLOSE','NO_SIGNAL','HOMING','SCAN COARSE')):
                    gate.close()
                if line.startswith('WINDOW '):
                    values=line.split()
                    if len(values)!=3:raise ValueError('Malformed WINDOW')
                    gate.open(int(values[1]),int(values[2]),max_pos)
            while not events.empty():
                kind,data=events.get_nowait()
                if kind=='quit':return
                if kind=='control_ping':last_control=time.monotonic();continue
                if kind=='cmd':
                    if data=='PROBE':
                        if radio:probe_requested=True
                        else:print('PROBE needs real radio mode',flush=True)
                        continue
                    if data=='SCAN' and args.mode!='radio':print('Motor mode has no RF feedback: SCAN disabled. Use real radio mode.',flush=True);continue
                    if data=='STOP':gate.close()
                    journal.event('command',command=data)
                    send(data)
                if kind=='rx':
                    accepted=gate.accept(data,peer)
                    if accepted:
                        ctx,values=accepted
                        if ctx['token'] is not None:send(f"S {ctx['token']} {ctx['id']} {values[0]} {values[1]}")
                        observation={'window':ctx['token'],'rssi10':values[0],'snr10':values[1]}
                        journal.event('radio_ack',**observation)
                        print(json.dumps({'feedback':'real_radio_ack',**observation}),flush=True)
            if radio and (gate.token is not None or probe_requested) and now-last_probe>=args.interval:
                probe_requested=False
                ctx=gate.begin_request();last_probe=now
                try:
                    sent=radio.sendData(b'AMID-AZ2'+secrets.token_bytes(4),destinationId=args.peer,
                        portNum=portnums_pb2.PRIVATE_APP,wantAck=True,wantResponse=False,
                        channelIndex=args.channel,hopLimit=0)
                    ctx['id']=sent.id
                    journal.event('probe',window=ctx['token'],request_id=ctx['id'])
                except Exception as ex:
                    print('Radio probe failed:',str(ex),flush=True);gate.pending=None
                    journal.event('probe_error',error=str(ex))
    except KeyboardInterrupt:pass
    finally:
        stop.set()
        try:send('STOP')
        except Exception:pass
        if receiver:
            from pubsub import pub
            pub.unsubscribe(receiver,'meshtastic.receive')
        if radio:radio.close()
        mega.close()
        if journal:
            journal.close()
            print('Saved report:',journal.path/'report.html',flush=True)
if __name__=='__main__':main()
