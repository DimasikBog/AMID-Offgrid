# AMID Offgrid 0.4.2 candidate

One Flutter app for Android and iPhone, developed through DimasikBog/AMID-Offgrid.
An owned Mac is not required: iOS compilation runs on macOS CI. Personal iPhone
installation through Windows must remain an option; paid memberships are not
authorized by this project work.

| Area | Candidate scope | Acceptance |
| --- | --- | --- |
| Knowledge | SQLite search, TXT/MD/AMID JSON, personal notes, categories, favorites, paging | Import, edit, close/reopen, search and backup tests |
| Assistant | GGUF on native devices; source retrieval on web | Cancel/error/race tests; actual mobile model loading still needs a phone |
| Maps | Bundled overview, raster MBTiles, GeoJSON, GPS, editable pins and GeoJSON export | Bounded metadata/tile validation, TMS/views, decode/cache/lifecycle tests; real Files/GPS/map checks on both platforms |
| Offline routes | Imported AMID network, directed shortest-distance paths, map overlay and GeoJSON export | Algorithm oracle, invalid graphs, SQLite/backup and UI tests; real datasets and phones still required |
| Messages | Authenticated direct foreground BLE, QR pairing, drafts and delivery acknowledgments | Protocol tests; Android/iPhone radio and lifecycle checks still required |
| Backup | Version 1 JSON plus optional AES-256-GCM/PBKDF2 password envelope | Round trip, wrong password, corruption, merge limits and atomic restore |
| Appearance | System/light/dark preference persisted with user data | Reopen/backup tests and screen inspection |
| Delivery | Development APK, unsigned IPA packaging, optional distribution APK/AAB from secrets | Exact source commit and SHA-256 for each real CI artifact |

ZIM Wikipedia, PDF, PBF/vector road routing, multi-hop mesh, photo recognition and
compatibility with third-party messaging protocols remain unimplemented.
The original services screenshot must be reconciled before claiming full parity.
These functions remain requirements to resolve; a limited candidate is not proof
that every original service has been combined.

Routing 0.4 uses explicitly supplied nodes and edges only. It does not infer
roads from MBTiles/GeoJSON, snap GPS or determine travel permissions and ETA.
The synthetic example is identified in UI and exports. See OFFLINE_ROUTES.md.

Physical Android/iPhone tests, credentials, store listings and store approval are
separate from compilation and unit tests. Never infer those outcomes from a ZIP,
IPA, successful command, or this requirements file.

Version 0.4.1 addresses lifecycle/resource edge cases: stalled-source cancellation,
queued-write cancellation, owned native route workers, app backgrounding and
short/large-text map layouts. Native cancellation requests isolate termination;
the browser fallback cannot interrupt a calculation already running synchronously.

Version 0.4.2 hardens native raster maps with bounded SQL results, image header
checks and pixel limits, a verified first image, lazy checks for later tiles and
explicit archive/cache ownership. It is not a full-file validator, a SQLite
query sandbox or evidence of measured phone memory consumption. Application
limits and compatibility tradeoffs are listed in OFFLINE_MAPS.md.
