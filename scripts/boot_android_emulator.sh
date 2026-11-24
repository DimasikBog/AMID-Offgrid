#!/usr/bin/env bash
set -euo pipefail
kind="${1:?android or wearos}"
case "$kind" in
  android) image='system-images;android-35;google_apis;x86_64'; profile='pixel_2' ;;
  wearos) image='system-images;android-34;android-wear;x86_64'; profile='wearos_small_round' ;;
  *) exit 2 ;;
esac
mkdir -p build/emulator-evidence
export ANDROID_USER_HOME="$RUNNER_TEMP/amid-android"
export ANDROID_EMULATOR_HOME="$ANDROID_USER_HOME"
export ANDROID_AVD_HOME="$ANDROID_USER_HOME/avd"
mkdir -p "$ANDROID_AVD_HOME"
for variable in ANDROID_USER_HOME ANDROID_EMULATOR_HOME ANDROID_AVD_HOME; do
  printf '%s=%s\n' "$variable" "${!variable}" >> "$GITHUB_ENV"
done
printf '%s\n' "$ANDROID_HOME/platform-tools" "$ANDROID_HOME/emulator" "$ANDROID_HOME/cmdline-tools/latest/bin" >> "$GITHUB_PATH"
export PATH="$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$ANDROID_HOME/emulator:$PATH"
sdkmanager --install emulator platform-tools "$image"
avdmanager list device > build/emulator-evidence/device-profiles.txt
echo no | avdmanager create avd --force --name amid-test --package "$image" --device "$profile" --path "$ANDROID_AVD_HOME/amid-test.avd"
emulator -list-avds
test -f "$ANDROID_AVD_HOME/amid-test.ini"
# This is an isolated hosted test VM; fail if hardware acceleration is unavailable.
test -e /dev/kvm
sudo chmod a+rw /dev/kvm
emulator -accel-check
nohup emulator @amid-test -no-window -no-audio -no-boot-anim -no-snapshot -gpu swiftshader_indirect -memory 2048 -cores 2 > build/emulator-evidence/emulator.log 2>&1 &
amidEmulatorPid=$!
# Show a crashed emulator immediately instead of waiting for adb forever.
for ((i=0; i<60; i++)); do
  if ! kill -0 "$amidEmulatorPid" 2>/dev/null; then cat build/emulator-evidence/emulator.log; exit 1; fi
  if adb devices | grep -q 'emulator-5554[[:space:]]'; then break; fi
  sleep 2
done
timeout 90 adb wait-for-device
for ((i=0; i<180; i++)); do
  if [[ "$(adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" == '1' ]]; then break; fi
  sleep 2
done
[[ "$(adb shell getprop sys.boot_completed | tr -d '\r')" == '1' ]]
adb shell input keyevent 82
adb shell settings put global window_animation_scale 0
adb shell settings put global transition_animation_scale 0
adb shell settings put global animator_duration_scale 0
adb shell getprop > build/emulator-evidence/getprop.txt
emulator -version > build/emulator-evidence/emulator-version.txt 2>&1
python3 - "$kind" "$image" "$profile" <<'PY'
import json, os, subprocess, sys
from pathlib import Path
def prop(name):
    return subprocess.check_output(['adb', 'shell', 'getprop', name], text=True).strip()
data = {'sourceCommit': os.environ['GITHUB_SHA'], 'platform': sys.argv[1],
        'image': sys.argv[2], 'profile': sys.argv[3], 'model': prop('ro.product.model'),
        'api': prop('ro.build.version.sdk'), 'release': prop('ro.build.version.release'),
        'abi': prop('ro.product.cpu.abi'), 'physicalDevice': False}
Path('build/emulator-evidence/device.json').write_text(json.dumps(data, indent=2))
print(json.dumps(data))
PY
