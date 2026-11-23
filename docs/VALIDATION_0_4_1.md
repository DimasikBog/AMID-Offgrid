# AMID Offgrid 0.4.1 verification

Date: 2026-11-23. Flutter 3.47.6 / Dart 3.13.5 on Linux.
CI=true and FLUTTER_SUPPRESS_ANALYTICS=true were used.

- Clean formatting and static analysis.
- Full Flutter suite: 67 tests passed, including the preceding 55.
- Python release-tool tests: 5 passed; project identity/private-file check passed.
- Web release compilation passed. Dependency versions and lockfile are unchanged.
- Before the fixes, regression tests reproduced a stalled cancellation timeout
  and a map RenderFlex overflow of 388 pixels on a 320×280 viewport at 2× text.
  Both pass with the changes.
- Stream/checksum tests check subscription closure and reader reuse.
- Queued knowledge/asset/restore tests check cancellation after waiting behind
  another write and verify that later writes still succeed.
- Native and browser worker contracts check results, typed errors, replacement,
  cancellation and disposal. A native unsendable-message test checks spawn failure
  recovery. UI tests check pause/resume and a tall route fitted after panel layout.

The final PR workflow and release-manifest.json provide evidence for the new
Android binary, its source commit, signing and SHA-256. Previous release records
remain historical and do not certify a different build.

Native worker cancellation requests immediate isolate shutdown; it does not
promise an exact termination time. Browser work cannot be preempted mid-event.
Cancellation before a queued write prevents activation; a transaction already
committing finishes atomically. OS file dialogs are controlled by the OS.

Physical devices, real large-model download/activation on iOS, BLE/GPS/Files/GGUF,
new iOS compilation/signing, permanent Android keys and store release remain
unverified. No hardware or publication result is inferred from these tests.

API references: [StreamIterator.cancel](https://api.dart.dev/dart-async/StreamIterator/cancel.html),
[Isolate.kill](https://api.dart.dev/dart-isolate/Isolate/kill.html),
[isolate result/error handling](https://api.dart.dev/dart-isolate/Isolate/run.html).
