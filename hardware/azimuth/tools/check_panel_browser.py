"""Browser behavior/layout tests against protocol fixtures, never a serial device."""
import sys,threading,os,json,io
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from panel import Controller,ThreadingHTTPServer,handler
from playwright.sync_api import sync_playwright
class Process:
 def __init__(self):self.stdin=io.StringIO()
 def poll(self):return None
c=Controller('motor');s=ThreadingHTTPServer(('127.0.0.1',0),handler(c,'browser-test'))
t=threading.Thread(target=s.serve_forever,daemon=True);t.start();checks=[]
try:
 with sync_playwright() as p:
  options={'headless':True,'args':['--no-sandbox']}
  if os.environ.get('CHROMIUM_EXECUTABLE'):options['executable_path']=os.environ['CHROMIUM_EXECUTABLE']
  browser=p.chromium.launch(**options);page=browser.new_page(viewport={'width':1440,'height':1100});errors=[];page.on('pageerror',lambda e:errors.append(str(e)))
  page.goto(f'http://127.0.0.1:{s.server_port}/#browser-test')
  page.wait_for_function("document.getElementById('connection').textContent.includes('завершив')")
  assert page.locator('[data-command="ARM"]').is_disabled();assert page.locator('#angle').inner_text()=='—'
  assert 'ще немає' in page.locator('#measurement').inner_text();checks.append('no_bridge_no_motion_no_invented_metrics')
  c.process=Process();c.feed('Connected; motor is DISARMED.');c.feed('MEGA: INFO 2 4096 3072');c.feed('MEGA: STATE 0 POS 0 HOMED 0');c.feed('MEGA: INPUTS 1 0 0 0')
  page.wait_for_function("!document.querySelector('[data-command=ARM]').disabled")
  page.locator('[data-command="JOG 16"]').click();page.wait_for_timeout(100);assert c.process.stdin.getvalue()=='JOG 16\n';checks.append('explicit_click_only')
  assert page.locator('[data-command="SCAN"]').is_disabled();assert page.locator('[data-command="PROBE"]').is_disabled();checks.append('motor_mode_blocks_radio')
  page.reload();page.wait_for_function("document.getElementById('connection').textContent.includes('працює')");checks.append('reload_keeps_session_key')
  for width,height in [(1440,1100),(390,844)]:
   page.set_viewport_size({'width':width,'height':height});page.wait_for_timeout(80)
   assert page.evaluate('document.documentElement.scrollWidth <= innerWidth');checks.append(f'layout_{width}')
  page.close();c.lease=c.clock()-4;c.watchdog();assert c.process.stdin.getvalue().endswith('STOP\n');checks.append('lost_browser_requests_stop')
  assert not errors,errors;browser.close();checks.append('no_javascript_errors')
 print(json.dumps({'checks':checks,'result':'PASS','physical':'NOT_RUN'},indent=2))
finally:s.shutdown();s.server_close();t.join()
