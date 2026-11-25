#!/usr/bin/env python3
"""Install actual AAB-generated splits, then drive their Flutter integration app."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import time
from urllib.parse import urlsplit, urlunsplit

from prepare_offline_payload import ROOT
from verify_play_bundle import command, inspect


def adb(*args):
    return subprocess.check_output(['adb', '-s', 'emulator-5554', *args], text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('artifact', type=Path)
    args = parser.parse_args()
    path = args.artifact.resolve()
    evidence = ROOT / 'build/emulator-evidence'
    evidence.mkdir(parents=True, exist_ok=True)
    jar = inspect(path, evidence)
    apks = ROOT / 'build/play-emulator.apks'
    print(command(jar, 'build-apks', f'--bundle={path}', f'--output={apks}',
                  '--local-testing', '--connected-device', '--device-id=emulator-5554', '--overwrite'))
    print(command(jar, 'install-apks', f'--apks={apks}', '--device-id=emulator-5554'))
    installed = adb('shell', 'pm', 'path', 'com.amid.offgrid')
    (evidence / 'installed-splits.txt').write_text(installed, encoding='utf-8')
    if 'offline_model' not in installed or '/base.apk' not in installed:
        raise RuntimeError('The base and install-time AI split must both be installed')
    adb('shell', 'cmd', 'connectivity', 'airplane-mode', 'enable')
    if adb('shell', 'settings', 'get', 'global', 'airplane_mode_on').strip() != '1':
        raise RuntimeError('Offline test requires airplane mode')
    adb('logcat', '-c')
    adb('shell', 'am', 'force-stop', 'com.amid.offgrid')
    log_path = evidence / 'app-logcat.txt'
    log_file = log_path.open('w', encoding='utf-8')
    capture = subprocess.Popen(['adb', '-s', 'emulator-5554', 'logcat', '-v', 'brief'],
                               stdout=log_file, stderr=subprocess.STDOUT, text=True)
    try:
        adb('shell', 'am', 'start', '-n', 'com.amid.offgrid/.MainActivity')
        deadline = time.monotonic() + 120
        service = None
        while time.monotonic() < deadline:
            logs = log_path.read_text(encoding='utf-8', errors='replace')
            match = re.search(r'The Dart VM service is listening on (http://127\.0\.0\.1:\d+/[^\s]+)', logs)
            if match:
                service = urlsplit(match.group(1))
                break
            time.sleep(0.5)
        if service is None:
            raise RuntimeError('Installed split application did not expose its debug VM service')
        adb('forward', 'tcp:8181', f'tcp:{service.port}')
        forwarded = urlunsplit(('http', '127.0.0.1:8181', service.path, '', ''))
        environment = dict(os.environ, CI='true', FLUTTER_SUPPRESS_ANALYTICS='true')
        # --use-existing-app skips Flutter's APK installation entirely. The
        # running app is exactly the base + AI split installed by bundletool.
        with (evidence / 'driver.log').open('w', encoding='utf-8') as log:
            process = subprocess.Popen([
                'flutter', 'drive', '--no-pub', f'--use-existing-app={forwarded}',
                '--driver=test_driver/mobile.dart', '--target=integration_test/mobile_smoke_test.dart',
                '--timeout=600', '-d', 'emulator-5554'],
                cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
            for line in process.stdout:
                print(line, end='', flush=True)
                log.write(line)
            if process.wait() != 0:
                raise RuntimeError('The installed split integration test failed')
        logs = log_path.read_text(encoding='utf-8', errors='replace')
        for marker in ['AMID_STARTER_INSTALLED android: 639446688',
                       'AMID_MOBILE_AI_PASS android:', 'AMID_MOBILE_EMULATOR_PASS android:']:
            if marker not in logs:
                raise RuntimeError('Missing actual split-install result: ' + marker)
        result = {'sourceCommit': os.environ.get('GITHUB_SHA'), 'airplaneMode': True,
                  'installedAiSplit': True, 'fullStarterInstalled': True, 'localInference': True,
                  'navigationAndPersistence': True, 'physicalDevice': False, 'googlePlayTesting': 'not_run'}
        (evidence / 'split-install-result.json').write_text(json.dumps(result, indent=2) + '\n', encoding='utf-8')
        print('AMID_PLAY_SPLIT_INSTALL_PASS:', json.dumps(result))
    finally:
        capture.terminate()
        try:
            capture.wait(timeout=5)
        except subprocess.TimeoutExpired:
            capture.kill()
            capture.wait()
        log_file.close()
        subprocess.run(['adb', '-s', 'emulator-5554', 'forward', '--remove', 'tcp:8181'], check=False)


if __name__ == '__main__':
    main()
