"""Package source, built firmware and corresponding Arduino core source; exclude local data."""
from pathlib import Path
import hashlib,json,zipfile
ROOT=Path(__file__).resolve().parents[1]
EXCLUDED={'__pycache__','.venv','sessions','diagnostics','build-tools','avr-objects','dist','ui-results','.git'}
def main():
 if not (ROOT/'firmware/build/AMID_Azimuth_Mega2560.hex').is_file():raise SystemExit('Build firmware with tools/build_avr.py first')
 core=ROOT/'tools/build-tools/avr-1.8.6.tar.bz2'
 if not core.is_file() or hashlib.sha256(core.read_bytes()).hexdigest()!='ff1d17274b5a952f172074bd36c3924336baefded0232e10982f8999c2f7c3b6':raise SystemExit('Verified Arduino core source archive required; run tools/download_avr.py')
 entries={p.relative_to(ROOT).as_posix():p for p in ROOT.rglob('*') if p.is_file() and not any(x in EXCLUDED for x in p.relative_to(ROOT).parts) and p.name not in ('SHA256.json','test_firmware')}
 entries['third_party/Arduino_AVR_Core_1.8.6.tar.bz2']=core
 manifest={name:hashlib.sha256(p.read_bytes()).hexdigest() for name,p in sorted(entries.items())}
 out=ROOT/'dist';out.mkdir(exist_ok=True);target=out/'AMID-Azimuth-v0.5.0.zip'
 with zipfile.ZipFile(target,'w',zipfile.ZIP_DEFLATED) as z:
  for name,p in sorted(entries.items()):z.write(p,'AMID-Azimuth/'+name)
  z.writestr('AMID-Azimuth/SHA256.json',json.dumps(manifest,indent=2)+'\n')
 with zipfile.ZipFile(target) as z:
  if z.testzip():raise SystemExit('Archive integrity failure')
 (out/(target.name+'.sha256')).write_text(hashlib.sha256(target.read_bytes()).hexdigest()+'  '+target.name+'\n')
 print(target)
if __name__=='__main__':main()
