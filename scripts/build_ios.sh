#!/usr/bin/env bash
set -euo pipefail
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS compilation requires macOS and Xcode." >&2
  exit 2
fi
mkdir -p dist
xcodebuild -version | tee dist/toolchain.txt
AMID_IOS_SDK_VERSION="$(xcrun --sdk iphoneos --show-sdk-version)"
export AMID_IOS_SDK_VERSION
python3 - <<'PY'
import os
version = os.environ['AMID_IOS_SDK_VERSION']
if int(version.split('.')[0]) < 26:
    raise SystemExit('Select Xcode 26+ with an iOS 26+ SDK before building the store candidate.')
print('iPhoneOS SDK:', version)
PY
flutter pub get --enforce-lockfile
flutter build ios --release --no-codesign --no-pub
git diff --exit-code -- pubspec.lock
echo "Unsigned iOS build finished. Apple signing/provisioning and physical-device testing are still required."
