#!/usr/bin/env python3
"""Isolated release-build browser check; never uses a personal browser/profile."""
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
import os
from pathlib import Path
import shutil
import sys
import tempfile
from threading import Thread

from playwright.sync_api import sync_playwright, expect
from build_web_cache import generate


class QuietHandler(SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def check(build):
    with tempfile.TemporaryDirectory(prefix='amid-pwa-browser-') as directory:
        root = Path(directory)
        app = root / 'AMID-Offgrid'
        shutil.copytree(build, app)
        server = ThreadingHTTPServer(('127.0.0.1', 0), partial(QuietHandler, directory=str(root)))
        Thread(target=server.serve_forever, daemon=True).start()
        url = f'http://127.0.0.1:{server.server_port}/AMID-Offgrid/'
        try:
            with sync_playwright() as p:
                options = {'headless': True}
                if os.environ.get('AMID_TEST_CHROMIUM'):
                    options['executable_path'] = os.environ['AMID_TEST_CHROMIUM']
                browser = p.chromium.launch(**options)
                context = browser.new_context(service_workers='allow', viewport={'width': 390, 'height': 844})
                page = context.new_page()
                page.set_default_timeout(45000)
                errors = []
                page.on('pageerror', lambda error: errors.append(str(error)))
                page.goto(url)
                expect(page.locator('#offline-status')).to_have_text('Офлайн: файли збережені', timeout=60000)
                page.wait_for_function('document.getElementById("startup").hidden')
                assert page.locator('#flutter-host flt-glass-pane').count() == 1
                bounds = page.locator('#flutter-host').bounding_box()
                assert bounds and bounds['y'] >= 44 and bounds['width'] == 390
                # Opaque synthetic marker, no personal data or existing profile.
                page.evaluate('localStorage.setItem("amid-web-integration", "preserve-me")')
                context.set_offline(True)
                page.reload(wait_until='domcontentloaded')
                page.wait_for_function('document.getElementById("startup").hidden')
                expect(page.locator('#offline-status')).to_have_text('Офлайн: файли збережені')
                page.goto(url + 'saved/deep/link', wait_until='domcontentloaded')
                page.wait_for_function('document.getElementById("startup").hidden')
                assert page.evaluate('localStorage.getItem("amid-web-integration")') == 'preserve-me'
                if os.environ.get('AMID_BROWSER_EVIDENCE'):
                    evidence = Path(os.environ['AMID_BROWSER_EVIDENCE'])
                    evidence.mkdir(parents=True, exist_ok=True)
                    page.screenshot(path=str(evidence / 'offline-phone.png'))
                print('PASS actual Chromium: first install, offline root/deep links, Flutter host layout', flush=True)
                context.set_offline(False)
                page.goto(url)
                expect(page.locator('#offline-status')).to_have_text('Офлайн: файли збережені')
                # Simulate one evicted static asset, not personal storage.
                page.evaluate('''async () => {
                  const key = (await caches.keys()).find(k => k.startsWith('amid-offgrid:' + location.href + ':'));
                  await (await caches.open(key)).delete(new URL('assets/starter.json', location.href).href);
                }''')
                page.locator('#offline-status').click()
                page.locator('#prepare-offline').click()
                expect(page.locator('#offline-status')).to_have_text('Офлайн: файли збережені')
                page.wait_for_function('''async () => {
                  const key = (await caches.keys()).find(k => k.startsWith('amid-offgrid:' + location.href + ':'));
                  return !!await (await caches.open(key)).match(new URL('assets/starter.json', location.href).href);
                }''')
                print('PASS actual Chromium: missing static file repaired', flush=True)
                page.get_by_role('button', name='Закрити', exact=True).click()
                other = context.new_page()
                other.goto(url)
                expect(other.locator('#offline-status')).to_have_text('Офлайн: файли збережені')
                # Generate a real second build's worker in this disposable server only.
                css = app / 'pwa.css'
                css.write_text(css.read_text() + '\n/* integration update */\n')
                generate(app)
                page.locator('#offline-status').click()
                page.locator('#check-update').click()
                expect(page.locator('#update-app')).to_be_visible(timeout=60000)
                page.get_by_role('button', name='Закрити', exact=True).click()
                page.locator('#update-app').click()
                page.locator('#confirm-update').click()
                expect(page.locator('#action-detail')).to_contain_text('Спочатку закрий інші вкладки')
                other.close()
                with page.expect_navigation(wait_until='domcontentloaded'):
                    page.locator('#confirm-update').click()
                page.wait_for_function('document.getElementById("startup").hidden')
                expect(page.locator('#offline-status')).to_have_text('Офлайн: файли збережені')
                assert page.evaluate('localStorage.getItem("amid-web-integration")') == 'preserve-me'
                print('PASS actual Chromium: other window blocks activation; explicit update preserves data', flush=True)
                # A worker manifest whose served bytes change before install must fail closed.
                css.write_text(css.read_text() + '\n/* next release */\n')
                generate(app)
                css.write_text(css.read_text() + '\n/* unexpected bytes after manifest */\n')
                page.locator('#offline-status').click()
                page.locator('#check-update').click()
                expect(page.locator('#offline-status')).to_have_text('Офлайн: підготовка не вдалася', timeout=60000)
                context.set_offline(True)
                page.reload(wait_until='domcontentloaded')
                page.wait_for_function('document.getElementById("startup").hidden')
                assert page.evaluate('localStorage.getItem("amid-web-integration")') == 'preserve-me'
                assert not errors, errors
                print('PASS actual Chromium: corrupt replacement rejected; previous build still boots offline', flush=True)
                context.close()
                browser.close()
        finally:
            server.shutdown()
            server.server_close()


if __name__ == '__main__':
    check(Path(sys.argv[1] if len(sys.argv) > 1 else 'build/web').resolve())
