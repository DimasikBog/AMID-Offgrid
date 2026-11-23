# Verification matrix

| Check | Mechanism | Evidence required |
| --- | --- | --- |
| Formatting / static analysis | dart format, flutter analyze | Clean result for the final source commit |
| State, notes, ranking, restore and draft durability | Flutter unit/SQLite tests | Passing test output |
| Cancellation, wrong passwords and corrupted backups | Flutter tests | Passing test output, no mutation on failure |
| Note creation, favorites, unsaved draft preservation | Widget tests at 390×844 | Passing screen interaction tests |
| Routing | Dijkstra versus independent Floyd-Warshall oracle on 50 random directed multigraphs; 10 000-node chain | Matching minimum distances, correct geometry and no invented path |
| Routing persistence and UI | File import, SQLite reopen, backup, cancel/source removal and 320px large-text widget tests | Passing automated checks; real network data and phones still required |
| Bundled guidance upgrade | Legacy state refresh and second reopen | Personal notes, pins, favorites preserved and refresh idempotent |
| Radio framing and authenticated transport | Protocol unit tests | Passing tests; does not prove real radio interoperability |
| Packaging and provenance | Python tests and manifest checker | Real artifact digests and source/run identifiers |
| Android executable | GitHub Actions APK build + ELF/apksigner/zipalign checks | Successful final run and matching APK |
| iOS executable | Manual macOS CI + package_ios.py | Successful final run, app/IPA and digest; remains unsigned |
| Android/iPhone BLE, GPS, Files and GGUF | Physical devices | Device model, OS, commit, artifact SHA, steps and observed results |
| Personal iPhone signing/renewal | Windows + owner's iPhone | Successful install, launch and data retained after renewal |
| Store candidate | Valid accounts + signed AAB/IPA + listings | Console validation and test tracks |
| Publication | Store review and release | Approved, actually available listing |

Physical-device checks remain not run. Capture at least Android ↔ iPhone sends
in both directions, long Cyrillic text, disconnect/reconnect, radio off, denied
permissions, app backgrounding and screen lock. Verify foreground-only behavior.
Check real large-file import, a resumed download, low storage, backup restore,
model load/cancel/unload, package removal and upgrade from the prior version.

Keep device reports next to the release record. Record SDK/OS/hardware and the
exact source/artifact; never carry a green result forward to different code.
