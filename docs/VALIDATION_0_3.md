# AMID Offgrid 0.3.0 candidate verification

Date: 2026-11-23. Flutter 3.47.6 / Dart 3.13.5 on Linux. SDK source revision:
5fc346839b5d0eef006ed8404392afb4dfae428d. CI=true and
FLUTTER_SUPPRESS_ANALYTICS=true were used; no cloud metadata discovery was
needed in this configuration.

- Dependency resolution with --enforce-lockfile passed without changing pubspec.lock.
- dart format check: clean.
- flutter analyze --no-pub: No issues found.
- flutter test --no-pub: 39 passed, including the previous 14 tests.
- Python release-tool tests: 5 passed.
- Project identity/private signing-file check: passed.
- actionlint 1.7.12: both mobile.yml and release.yml passed.
- Web release compilation succeeded. Web does not exercise the native phone adapters.

Tests cover long text preservation, UTF-16 boundaries, notes/favorites/theme,
SQLite persistence and rollback, complete-match ranking, bounded atomic restore,
draft durability, encrypted backup round trips/wrong passwords/tampering, import
cancellation/cleanup, assistant request ownership, radio protocol framing and
screen interactions. Packaging tests use explicitly synthetic fixtures; they do
not stand in for an actual iOS compilation or an installed application.

GitHub Actions is the evidence for the new APK build, its signatures/alignment
and exact artifact provenance. Use the successful run attached to the final PR
and inspect its release-manifest.json. The checked-in RELEASE.json remains the
historical 0.2.0 artifact record.

Not verified here: physical Android/iPhone execution, BLE interoperability,
device GPS/Files/model inference, iPhone personal signing/renewal, new iOS
compilation, permanent signing credentials and store review/publication. The
manual macOS and distribution-signing paths are not marked completed.
