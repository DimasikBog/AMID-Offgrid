"""Select and boot an available Apple simulator; preserve exact model evidence."""
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def run(*args):
    return subprocess.check_output(args, text=True)


kind = sys.argv[1]
if kind not in {'ios', 'watchos'}:
    raise SystemExit('Expected ios or watchos')
root = Path('build/emulator-evidence')
root.mkdir(parents=True, exist_ok=True)
inventory = json.loads(run('xcrun', 'simctl', 'list', 'devices', 'available', '--json'))
(root / 'simulators.json').write_text(json.dumps(inventory, indent=2))
candidates = []
for runtime, devices in inventory['devices'].items():
    if ('.iOS-' if kind == 'ios' else '.watchOS-') not in runtime:
        continue
    for device in devices:
        if device.get('isAvailable') and ('iPhone' if kind == 'ios' else 'Apple Watch') in device['name']:
            version = tuple(int(n) for n in re.findall(r'\d+', runtime.split('Runtime.')[-1]))
            small = ('SE' in device['name'] or '40mm' in device['name'] or '42mm' in device['name'])
            candidates.append((version, small, device['name'], runtime, device))
if not candidates:
    raise SystemExit(f'No available {kind} simulator. See simulators.json; no test was run.')
# Prefer Xcode 26.2's runtime when installed; otherwise report the actual newest one.
same_sdk = [item for item in candidates if item[0][:2] == (26, 2)]
_, _, _, runtime, selected = max(same_sdk or candidates, key=lambda item: item[:3])
if selected['state'] != 'Booted':
    subprocess.run(['xcrun', 'simctl', 'boot', selected['udid']], check=True, timeout=120)
subprocess.run(['xcrun', 'simctl', 'bootstatus', selected['udid'], '-b'], check=True, timeout=300)
evidence = {'sourceCommit': os.environ.get('GITHUB_SHA'), 'platform': kind,
            'runtime': runtime, 'device': selected, 'physicalDevice': False,
            'xcode': run('xcodebuild', '-version')}
(root / 'device.json').write_text(json.dumps(evidence, indent=2))
with open(os.environ['GITHUB_ENV'], 'a') as output:
    output.write(f"AMID_SIMULATOR_ID={selected['udid']}\n")
print(json.dumps(evidence, ensure_ascii=False))
