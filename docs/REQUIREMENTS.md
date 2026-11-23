# AMID Offgrid 0.3.0 candidate

One Flutter app for Android and iPhone, developed through DimasikBog/AMID-Offgrid.
An owned Mac is not required: iOS compilation runs on macOS CI. Personal iPhone
installation through Windows must remain an option; paid memberships are not
authorized by this project work.

| Area | Candidate scope | Acceptance |
| --- | --- | --- |
| Knowledge | SQLite search, TXT/MD/AMID JSON, personal notes, categories, favorites, paging | Import, edit, close/reopen, search and backup tests |
| Assistant | GGUF on native devices; source retrieval on web | Cancel/error/race tests; actual mobile model loading still needs a phone |
| Maps | Bundled overview, raster MBTiles, GeoJSON, GPS, editable pins and GeoJSON export | Metadata validation; real Files/GPS/map checks on both platforms |
| Messages | Authenticated direct foreground BLE, QR pairing, drafts and delivery acknowledgments | Protocol tests; Android/iPhone radio and lifecycle checks still required |
| Backup | Version 1 JSON plus optional AES-256-GCM/PBKDF2 password envelope | Round trip, wrong password, corruption, merge limits and atomic restore |
| Appearance | System/light/dark preference persisted with user data | Reopen/backup tests and screen inspection |
| Delivery | Development APK, unsigned IPA packaging, optional distribution APK/AAB from secrets | Exact source commit and SHA-256 for each real CI artifact |

ZIM Wikipedia, PDF, PBF/vector routing, multi-hop mesh, photo recognition and
compatibility with third-party messaging protocols remain unimplemented.
The original services screenshot must be reconciled before claiming full parity.
These functions remain requirements to resolve; a limited candidate is not proof
that every original service has been combined.

Physical Android/iPhone tests, credentials, store listings and store approval are
separate from compilation and unit tests. Never infer those outcomes from a ZIP,
IPA, successful command, or this requirements file.
