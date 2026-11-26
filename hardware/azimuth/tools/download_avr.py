import urllib.request,json,hashlib,tarfile,concurrent.futures
from pathlib import Path
P=Path(__file__).parent/'build-tools';P.mkdir(exist_ok=True)
j=json.load(urllib.request.urlopen('https://downloads.arduino.cc/packages/package_index.json',timeout=30));pkg=next(x for x in j['packages'] if x['name']=='arduino');core=next(x for x in pkg['platforms'] if x['architecture']=='avr' and x['version']=='1.8.6');dep=next(x for x in core['toolsDependencies'] if x['name']=='avr-gcc');tool=next(x for x in pkg['tools'] if x['name']=='avr-gcc' and x['version']==dep['version']);gcc=next(x for x in tool['systems'] if x['host'] in ('x86_64-pc-linux-gnu','x86_64-linux-gnu'))
def get(item):
 name,d=item;dest=P/name;dest.mkdir(exist_ok=True);f=P/d['archiveFileName'];urllib.request.urlretrieve(d['url'],f);expected=d['checksum'].split(':')[1].lower();assert hashlib.sha256(f.read_bytes()).hexdigest()==expected
 with tarfile.open(f) as t:t.extractall(dest,filter='data')
 print(name,d.get('version',dep['version']),flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=2) as ex:list(ex.map(get,[('core',core),('compiler',gcc)]))
(P/'versions.json').write_text(json.dumps({'core':'1.8.6','compiler':dep['version'],'core_sha256':core['checksum'],'compiler_sha256':gcc['checksum']},indent=2))
