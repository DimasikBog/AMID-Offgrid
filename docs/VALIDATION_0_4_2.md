# AMID Offgrid 0.4.2 verification

Date: 2026-11-23. Flutter 3.47.6 / Dart 3.13.5 on Linux.
CI=true and FLUTTER_SUPPRESS_ANALYTICS=true were used.

- Formatting and static analysis passed.
- Full Flutter suite: 101 tests passed with --concurrency 1, including the
  preceding 67 tests. CI is configured for two concurrent test files to bound
  runner resource demand; its result must be checked on the final PR run.
- Python release-tool tests: 5 passed. Project identity/private-file check passed.
- Both GitHub workflows passed actionlint. No dependencies or lockfile changed.
- Web release compilation passed. Flutter emitted a Cupertino font-family
  warning; this build is not a native phone or interactive visual test.

Before the fixes, import regressions showed that duplicate metadata and a
non-image sample could be accepted. Those regressions now pass. Import tests
also check private-copy activation, metadata/hash storage, rollback cleanup and
preservation of the original file on removal.

Real SQLite fixtures cover read-only source preservation, normalized views,
TMS row conversion, fallback center, metadata limits/types, coordinate limits,
duplicate/oversized/non-BLOB tiles, queue recovery and close with pending reads.
Real synthetic PNG/JPEG/WebP images exercise engine decoders; excessive width
and pixel count are rejected before pixel decoding. Animated WebP is rejected.
Provider tests cover transparent fallback, key identity, cache eviction on close
and retiring the first key after 513 requests.

Widget ownership tests use controlled archive doubles and completion order to
verify stale/disposed opens, current archive retention and retry after an open
error. They are separate from real SQL, codec and image-provider tests. They do
not claim to measure platform-channel behavior or real device memory.

The first tile is decoded at import/open; other tiles are checked when accessed.
No whole-file integrity audit or arbitrary SQLite execution-cost sandbox is
implemented. Limits and compatibility tradeoffs are documented in OFFLINE_MAPS.md.

The final PR run and release-manifest.json are the evidence for the actual
Android binary, its source commit, development signing and SHA-256. This source
record alone does not certify an Android executable or any iOS executable.

Physical Android/iPhone Files, GPS, BLE, GGUF, large real map performance,
new iOS compilation/signing, permanent Android keys and store publication remain
unverified. deviceTesting and storeSubmission stay not_run.
