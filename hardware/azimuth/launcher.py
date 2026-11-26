"""Interactive local launcher. Never sends ARM, JOG or SCAN automatically."""
from pathlib import Path
import subprocess,sys,re
ROOT=Path(__file__).resolve().parent

def build_command(choice,mega,radio='',peer=''):
 if not mega or any(c in mega for c in '\r\n'):raise ValueError('Select a Mega port')
 if choice=='1':return [sys.executable,str(ROOT/'diagnose.py'),'--mega-port',mega]
 command=[sys.executable,str(ROOT/('panel.py' if choice in ('4','5') else 'bridge.py')),'--mega-port',mega]
 if choice in ('2','4'):return command+['--mode','motor']
 if choice not in ('3','5'):raise ValueError('Choose 1..5')
 if not radio or radio.casefold()==mega.casefold():raise ValueError('Radio and Mega require separate serial ports')
 if not re.fullmatch(r'![0-9a-fA-F]{8}',peer):raise ValueError('Peer format: !a1b2c3d4')
 return command+['--mode','radio','--radio-port',radio,'--peer',peer]

def main():
 from serial.tools import list_ports
 ports=list(list_ports.comports())
 print('AMID Azimuth 0.5 — FIRST_RUN_UA.md contains the bench procedure')
 for p in ports:print(p.device,'|',p.description)
 print('1: NC diagnostics (motor power disconnected)\n2: Motor console\n3: Radio + motor console\n4: Browser panel - motor\n5: Browser panel - radio + motor\n6: Exit')
 choice=input('Mode: ').strip()
 if choice=='6':return
 mega=input('Mega port (e.g. COM5): ').strip()
 radio=peer=''
 if choice in ('3','5'):radio=input('Radio port: ').strip();peer=input('Second OWN node ID (!xxxxxxxx): ').strip()
 try:command=build_command(choice,mega,radio,peer)
 except ValueError as ex:print(ex);return
 print('No automatic movement. In the console, ARM starts homing; JOG starts a small movement.')
 subprocess.run(command,cwd=ROOT,check=False)
if __name__=='__main__':main()
