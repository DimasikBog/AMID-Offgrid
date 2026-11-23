# AMID Offgrid 0.4.0 candidate verification

Date: 2026-11-23. Flutter 3.47.6 / Dart 3.13.5, Linux.
CI=true and FLUTTER_SUPPRESS_ANALYTICS=true used throughout.

- Formatting clean; flutter analyze --no-pub: no issues found.
- flutter test --no-pub: 55 tests passed, including all previous 39.
- Python release-tool tests: 5 passed. Project identity check passed.
- Web release compilation passed; native hardware is not covered by that build.
- actionlint 1.7.12 passed for the workflows; mobile artifacts include the
  synthetic network example and its usage instructions.
- New coverage: route oracle comparison on 50 random directed multigraphs,
  10 000-node chain, reverse geometry, disconnected nodes, bounds, import,
  SQLite reopen, backup rollback, native compute, cancellation, removed sources,
  endpoint search, 320px large-text UI and the full background-calculation →
  map-overlay → source-removal flow.
- Old bundled-guidance upgrade preserves notes, pins and favorites; second
  reopen does not repeat the migration.

For the new Android binary, inspect the successful final PR workflow and its
release-manifest.json. Its exact source commit, artifact size, signing state and
SHA-256 are authoritative. Prior RELEASE.json/VALIDATION.md remain historical
0.2.0 evidence; VALIDATION_0_3.md covers the preceding code version.

The example route data is synthetic. Actual local networks, physical phone
execution, GPS/Files, Android/iPhone BLE, native model inference, new iOS
compilation/signing, permanent distribution credentials and store publication
remain unverified. The routing feature does not provide OSM/PBF import or
turn-by-turn road navigation.
