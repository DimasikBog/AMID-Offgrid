"""Observe Mega NC input states without ARM/JOG/SCAN or radio transmission."""
import argparse,json,time
from pathlib import Path
from datetime import datetime,timezone
from journal import parse_info

def parse_inputs(line):
 a=line.split()
 if len(a)!=5 or a[:2]!=['INPUTS','1'] or any(x not in ('0','1') for x in a[2:]):raise ValueError('Invalid INPUTS telemetry; flash v0.3')
 return tuple(map(int,a[2:]))

def inspect(port,duration,output,clock=time.monotonic,sleep=time.sleep):
 import serial
 report={'version':'0.5.0','port':port,'utc':datetime.now(timezone.utc).isoformat(),'physical_verification':'NOT_VERIFIED','status':'NOT_READY','inputs_seen':[],'events':[]}
 device=serial.Serial(port,115200,timeout=.1,write_timeout=.5)
 def send(command):device.write((command+'\n').encode('ascii'))
 try:
  sleep(2);device.reset_input_buffer();send('STOP')
  end=clock()+duration;last=-1e9;found_info=False;seen=set()
  while clock()<end:
   now=clock()
   if now-last>=.5:send('PING');send('STATUS');last=now
   line=device.readline().decode('ascii',errors='replace').strip()
   if not line:continue
   report['events'].append(line)
   if line.startswith('INFO '):parse_info(line);found_info=True
   if line.startswith('STATE '):
    a=line.split()
    if len(a)!=6 or a[2]!='POS' or a[4]!='HOMED' or a[1] not in ('0','9'):raise ValueError('Unexpected armed/moving state; stopping')
   if line.startswith('INPUTS '):
    values=parse_inputs(line)
    if values not in seen:
     seen.add(values);report['inputs_seen'].append(list(values))
     print('LEFT / RIGHT / STOP:',*values, '(0 = closed to GND; 1 = open)',flush=True)
  if not found_info or not seen:raise ValueError('INFO 2 + INPUTS 1 missing; flash v0.3 and check the selected Mega port')
  report['status']='OBSERVATIONS_ONLY'
  return report
 except BaseException as ex:
  report['error']=str(ex) or type(ex).__name__
  raise
 finally:
  try:send('STOP')
  finally:
   device.close()
   Path(output).parent.mkdir(parents=True,exist_ok=True)
   Path(output).write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--list-ports',action='store_true');p.add_argument('--mega-port')
 p.add_argument('--duration',type=int,default=30);p.add_argument('--output')
 a=p.parse_args()
 if a.list_ports:
  from serial.tools import list_ports
  ports=list(list_ports.comports())
  for x in ports:print(x.device,'|',x.description)
  if not ports:print('No serial ports found. Check a USB data cable and device drivers.')
  return
 if not a.mega_port:p.error('--mega-port required unless --list-ports')
 if not 3<=a.duration<=300:p.error('--duration must be 3..300 seconds')
 output=a.output or str(Path('diagnostics')/(datetime.now(timezone.utc).strftime('%Y%m%dT%H%M%S%fZ')+'.json'))
 try:
  inspect(a.mega_port,a.duration,output)
  print('Saved:',output,'— observations only; manually verify which switch you pressed.')
 except (ValueError,OSError) as ex:p.exit(2,str(ex)+'\n')
if __name__=='__main__':main()
