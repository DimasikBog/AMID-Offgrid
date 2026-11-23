#!/usr/bin/env bash
set -euo pipefail
export CI=true
export FLUTTER_SUPPRESS_ANALYTICS=true
if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "iOS compilation requires macOS and Xcode." >&2
  exit 2
fi
flutter pub get
flutter build ios --release --no-codesign
echo "Unsigned iOS build finished. Open ios/Runner.xcworkspace to configure your Apple signing team."
