# Verification matrix

| Check | Mechanism | Evidence required |
| --- | --- | --- |
| Formatting / static analysis | dart format, flutter analyze | Clean result for the final source commit |
| State, notes, ranking, restore and draft durability | Flutter unit/SQLite tests | Passing test output |
| Cancellation, wrong passwords and corrupted backups | Flutter tests | Passing test output, no mutation on failure |
| Stalled sources and queued writes | Never-ending stream, checksum cancellation and blocked SQLite queue | Source cancelled without new input; cancelled writes do not activate data |
| Route worker ownership | Native/web contract, cancellation/replacement/disposal and spawn failure | Typed errors, reusable workers and closed task state |
| Lifecycle and layout | Pause/resume, tall-route viewport and 320×280 at 2× text | Stale output suppressed; route contained in camera bounds; controls reachable |
| Raster archives | Real SQLite fixtures, normalized views, invalid metadata, duplicate/oversized tiles and TMS coordinates | Reject invalid activation; preserve source bytes; queue recovers; close rejects pending reads |
| Raster decoding and cache | Synthetic real PNG/JPEG/WebP, excessive dimensions/pixels, animated WebP and 513 image keys | Validate before pixel decode, transparent fallback, cache retirement and close eviction |
| Raster widget ownership | Controlled late-open futures and archive doubles, including open-error retry | Disposed/stale archives closed; latest selected archive remains active; separate from real SQL/codec/provider tests |
| Note creation, favorites, unsaved draft preservation | Widget tests at 390×844 | Passing screen interaction tests |
| Routing | Dijkstra versus independent Floyd-Warshall oracle on 50 random directed multigraphs; 10 000-node chain | Matching minimum distances, correct geometry and no invented path |
| Routing persistence and UI | File import, SQLite reopen, backup, cancel/source removal and 320px large-text widget tests | Passing automated checks; real network data and phones still required |
| Bundled guidance upgrade | Legacy state refresh and second reopen | Personal notes, pins, favorites preserved and refresh idempotent |
| Radio framing and authenticated transport | Protocol unit tests | Passing tests; does not prove real radio interoperability |
| Packaging and provenance | Python tests and manifest checker | Real artifact digests and source/run identifiers |
| Android executable | GitHub Actions APK build + ELF/apksigner/zipalign checks | Successful final run and matching APK |
| iOS executable | Manual macOS CI + package_ios.py | Successful final run, app/IPA and digest; remains unsigned |
| Native Android/iPhone UI and SQLite | Flutter integration_test on actual OS emulator/simulator | Navigation, note/favorite, Lite, close/reopen and Unicode FTS; [exact results and source](EMULATOR_VALIDATION.md) |
| Wear OS / watchOS native UI | UiAutomator / XCUITest on actual OS emulator/simulator | Six card bodies, checklist persistence, screenshots; [exact results and source](EMULATOR_VALIDATION.md) |
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

## Version 0.5 additions

- Reader/preparation reopen, backup round trip, malformed-field rejection and
  preserving queued preferences during a legacy restore.
- Default native desktop database factory without a mobile method channel.
- Adaptive shell at 390×844, 1440×900 and 320×480 with 2× text; search focus and
  deferred map creation. Light reader checklist, font controls and clipboard.
- Complete bundle packaging, executable mode, outside-link rejection and
  deterministic/versioned web cache generation.
- CI Windows/Linux native --self-test: real temporary storage and search only.
  macOS/watchOS compilation, physical watch installs and all phone hardware checks
  remain distinct results, never inferred from unit tests.
