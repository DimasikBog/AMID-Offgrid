"""Execute the real browser scripts with deterministic Web API fixtures (no npm)."""
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

from build_web_cache import generate

ROOT = Path(__file__).resolve().parents[1]
WORKER = r'''
const assert = require('node:assert/strict');
const vm = require('node:vm');
const {webcrypto} = require('node:crypto');
const handlers = {}, scope = 'https://example.test/app/';
const stores = new Map(), calls = [], notifications = [];
let offline = false, corrupt = false, skips = 0, claims = 0;
let clients = [{id:'current',url:scope,postMessage:m=>notifications.push(m)}];
const fixtures = {'index.html':'page', 'flutter_bootstrap.js':'boot', 'a b.txt':'asset'};
const storage = {
  async has(name) { return stores.has(name); },
  async open(name) {
    if (!stores.has(name)) stores.set(name, new Map());
    const map = stores.get(name);
    return {
      async put(url, response) { map.set(url, response); },
      async keys() { return [...map.keys()].map(url=>({url})); },
      async match(request, opts) {
        let url = typeof request==='string' ? request : request.url;
        if (opts?.ignoreSearch) { const parsed = new URL(url); parsed.search=''; url=parsed.href; }
        return map.get(url)?.clone();
      }
    };
  },
  async keys() { return [...stores.keys()]; },
  async delete(name) { return stores.delete(name); }
};
const context = {
  URL, Response, Uint8Array, crypto:webcrypto, caches:storage,
  fetch:async input=>{
    const url=typeof input==='string'?input:input.url;calls.push(url);
    if(offline) throw Error('offline');
    const path=decodeURIComponent(url.slice(scope.length));
    return new Response(corrupt?'wrong':fixtures[path]??'network');
  },
  self:{ registration:{scope}, addEventListener:(type,fn)=>handlers[type]=fn,
    clients:{matchAll:async()=>clients, claim:async()=>{claims++;}},
    skipWaiting:async()=>{skips++;} }
};
vm.runInNewContext(SOURCE,context);
async function event(type, extras={}) {
  let pending;
  const e={...extras,waitUntil:p=>{pending=p;}};
  handlers[type](e);if(pending)await pending;
}
async function message(type, source=clients[0]) {
  let reply;
  await event('message',{data:{type},source,ports:[{postMessage:m=>reply=m}]});
  return reply;
}
async function get(path,mode='cors',method='GET') {
  let response;
  handlers.fetch({request:{url:scope+path,mode,method},respondWith:p=>response=p});
  return response?await(await response).text():null;
}
(async()=>{
  const prefix='amid-offgrid:'+scope+':';
  stores.set(prefix+'old',new Map([['old',new Response('old')]]));
  stores.set('another-application',new Map());
  if(SCENARIO==='failure') {
    corrupt=true;
    await assert.rejects(event('install'),/integrity/);
    assert(stores.has(prefix+'old'));assert(stores.has('another-application'));
    assert.equal(stores.size,2);assert.equal(skips,0);assert.equal(claims,0);
    assert.equal((await message('STATUS')).ready,false);
  } else {
    await event('install');
    assert.equal(skips,0);assert.equal(claims,0);
    assert.equal((await message('STATUS')).ready,true);
    const name=[...stores.keys()].find(k=>k.startsWith(prefix)&&k!==prefix+'old');
    if(SCENARIO==='offline') {
      offline=true;
      assert.equal(await get('','navigate'),'page');
      assert.equal(await get('a/deep/link','navigate'),'page');
      assert.equal(await get('a%20b.txt?test=1'),'asset');
      assert.equal(await get('anything','cors','POST'),null);
      await assert.rejects(get('missing'),/offline/);
      let intercepted=false;
      handlers.fetch({request:{url:'https://elsewhere.test/app/',method:'GET'},respondWith:()=>intercepted=true});
      assert.equal(intercepted,false);
    } else if(SCENARIO==='repair') {
      stores.get(name).delete(scope+'a%20b.txt');
      assert.equal((await message('STATUS')).ready,false);
      corrupt=true;await message('REPAIR');
      assert.equal(stores.get(name).size,2);assert(stores.has(prefix+'old'));
      assert.equal(notifications.at(-1).type,'FAILED');
      corrupt=false;const before=calls.length;await message('REPAIR');
      assert.equal(calls.length-before,1);assert.equal((await message('STATUS')).ready,true);
    } else if(SCENARIO==='activation') {
      clients.push({id:'other',url:scope+'index.html',postMessage:()=>{}});
      assert.equal((await message('ACTIVATE')).accepted,false);assert.equal(skips,0);
      clients.pop();assert.equal((await message('ACTIVATE')).accepted,true);assert.equal(skips,1);
      const ignored=await message('ACTIVATE',{id:'foreign',url:'https://elsewhere.test/'});
      assert.equal(ignored,undefined);assert.equal(skips,1);
    } else if(SCENARIO==='cleanup') {
      stores.set('amid-offgrid:https://example.test/other/:v1',new Map());
      await event('activate');
      assert.equal(claims,1);assert(!stores.has(prefix+'old'));assert(stores.has(name));
      assert(stores.has('another-application'));assert(stores.has('amid-offgrid:https://example.test/other/:v1'));
    }
  }
})().catch(error=>{console.error(error);process.exitCode=1;});
'''
CLIENT = r'''
const assert=require('node:assert/strict'),vm=require('node:vm');
const {MessageChannel}=require('node:worker_threads');
const elements=new Map(),events={},swEvents={};let reloads=0,updates=0,prompts=0,repairs=0;
function element(id) {
 if(!elements.has(id))elements.set(id,{id,hidden:false,disabled:false,textContent:'',open:false,
   showModal(){this.open=true;},after(child){elements.set(child.id,child);}});
 return elements.get(id);
}
const active={postMessage(data,ports){if(data.type==='REPAIR')repairs++;if(ports?.[0]){ports[0].postMessage({ready:SCENARIO!=='missing',files:3});ports[0].close();}}};
const registration={active,installing:null,waiting:null,addEventListener(){},async update(){updates++;}};
const navigator={onLine:false,standalone:false};
if(SCENARIO!=='unsupported')navigator.serviceWorker={
 async register(){return registration;},addEventListener:(name,fn)=>swEvents[name]=fn};
const context={navigator,MessageChannel,WeakSet,Promise,Error,
 document:{getElementById:element,createElement:()=>({})},
 location:{reload:()=>reloads++},
 setTimeout:(fn,ms)=>{const t=setTimeout(fn,ms);t.unref();return t;},clearTimeout,
 window:{isSecureContext:true,matchMedia:()=>({matches:false}),addEventListener:(name,fn)=>events[name]=fn}
};
vm.runInNewContext(SOURCE,context);
async function settle() {
 const start=Date.now();
 const expected=SCENARIO==='unsupported'?/недоступно/:SCENARIO==='missing'?/готую/:/файли збережені/;
 while(!expected.test(element('offline-status').textContent)) {
  if(Date.now()-start>3000)throw Error('Client did not settle: '+element('offline-status').textContent);
  await new Promise(resolve=>setTimeout(resolve,5));
 }
}
(async()=>{
 await settle();
 if(SCENARIO==='unsupported') {
  assert.equal(element('prepare-offline').disabled,true);
  assert.match(element('offline-status').textContent,/недоступно/);
 } else {
  assert.match(element('offline-status').textContent,SCENARIO==='missing'?/готую/:/файли збережені/);
  assert.equal(repairs,SCENARIO==='missing'?1:0);
  assert.match(element('network-detail').textContent,/недоступна/);
  swEvents.controllerchange();assert.equal(reloads,0);
  if(SCENARIO==='install') {
   let prevented=false;
   events.beforeinstallprompt({preventDefault(){prevented=true;},async prompt(){prompts++;},userChoice:Promise.resolve({outcome:'dismissed'})});
   await element('install-app').onclick();assert(prevented);assert.equal(prompts,1);assert.equal(reloads,0);
   assert.notEqual(element('install-app').textContent,'Як відкрити');
   await element('install-app').onclick();assert(element('offline-help').open);
  } else if(SCENARIO==='update') {
   let accepted=false;
   registration.waiting={postMessage(data,ports){ports[0].postMessage({accepted});ports[0].close();}};
   await element('update-app').onclick();assert.equal(reloads,0);
   await element('confirm-update').onclick();assert.match(element('action-detail').textContent,/закрий інші вкладки/);
   swEvents.controllerchange();assert.equal(reloads,0);
   accepted=true;await element('confirm-update').onclick();swEvents.controllerchange();assert.equal(reloads,1);
   swEvents.controllerchange();assert.equal(reloads,1);
  }
 }
 context.window.amidPwa.startupError();assert.equal(element('restart-app').hidden,false);
 context.window.amidPwa.startupReady();assert.equal(element('startup').hidden,true);
})().catch(error=>{console.error(error);process.exitCode=1;});
'''


class WebOfflineTest(unittest.TestCase):
    def execute(self, harness, source, scenario):
        result = subprocess.run(['node', '-e',
            'const SOURCE=' + json.dumps(source) + ';const SCENARIO=' + json.dumps(scenario) + ';\n' + harness],
            capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_worker_lifecycle_integrity_repair_and_scope(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name, content in {'index.html': 'page', 'flutter_bootstrap.js': 'boot', 'a b.txt': 'asset'}.items():
                (root / name).write_text(content)
            generate(root)
            source = (root / 'amid-sw.js').read_text()
            for scenario in ['failure', 'offline', 'repair', 'activation', 'cleanup']:
                with self.subTest(scenario=scenario): self.execute(WORKER, source, scenario)

    def test_client_status_install_dismissal_and_explicit_update(self):
        source = (ROOT / 'web/pwa.js').read_text()
        for scenario in ['unsupported', 'ready', 'missing', 'install', 'update']:
            with self.subTest(scenario=scenario): self.execute(CLIENT, source, scenario)

    def test_worker_implementation_also_changes_cache_version(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('page')
            (root / 'flutter_bootstrap.js').write_text('boot')
            first = generate(root)
            template = (ROOT / 'scripts/web_worker.js').read_text()
            changed = root.parent / (root.name + '-worker.js')
            try:
                changed.write_text(template + '\n// corrected worker')
                self.assertNotEqual(first['version'], generate(root, template_path=changed)['version'])
            finally:
                changed.unlink()

    def test_legacy_bootstrap_upgrade_is_repeatable(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'index.html').write_text('<script src="flutter_bootstrap.js" async></script>')
            (root / 'flutter_bootstrap.js').write_text('new host bootstrap')
            first = generate(root)
            self.assertIn('src="amid-bootstrap.js"', (root / 'index.html').read_text())
            self.assertEqual((root / 'amid-bootstrap.js').read_text(), 'new host bootstrap')
            self.assertEqual(first, generate(root))
