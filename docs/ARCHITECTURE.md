# Architecture

Flutter 3.47.6 / Dart 3.13.5, application ID com.amid.offgrid. Platform minima
remain Android 8 (API 26), ARM64, and iOS 17. Their full device coverage is not yet
confirmed. Dependency versions remain pinned in pubspec.lock.

Shared UI/models, SQLite state and FTS, input validation, document parsing,
authenticated backup codec and BLE framing live in lib/. Conditional imports
select native or browser adapters for files, inference, Bluetooth, storage and
tiles. Browser preview does not simulate phone hardware or generate fake replies.

AppStore serializes mutations. A failed transaction rolls back memory and SQLite;
close drains queued writes. Optional JSON fields extend the version 1 state
without erasing existing installations. Personal notes are a normal knowledge
pack, while favorites refer to article keys. Restore merges existing data,
preserves conflicting existing knowledge/pins, merges distinct personal notes,
and rejects conflicting message identities and capacity violations atomically.

GGUF/MBTiles files are streamed into private storage with size/hash checks. Text
documents are split into bounded articles without losing separators or breaking
UTF-16 pairs. Cancellation is cooperative and partial imports are removed; the
starter download retains its partial file for resuming unless explicitly cleared.

Backups exclude native paths, GGUF and MBTiles. Password backups use PBKDF2-HMAC-
SHA256 (210000 iterations, random 16-byte salt) and AES-256-GCM with random nonce
and authenticated format version. Native key derivation runs in a background
isolate. Passwords are not persisted. This does not encrypt the live database.

Assistant retrieval and model tasks use request generations, so cancellation or
disposal cannot publish stale results. BLE operations use a session generation;
disconnect or radio loss invalidates tickets and crypto state. Actual radio and
mobile-runtime behavior still require device verification.

CI creates artifacts per source commit. Signing secrets are absent from PR jobs.
The manual Android distribution workflow accepts reviewed main only and fails
when a required key is missing. No workflow automatically publishes to a store.

Route networks extend normal version 1 packs with an optional routing field,
validated on import/restore. Topology comes from explicit node IDs and directed
edges, never geometric crossings. Distances follow edge geometry; Dijkstra uses
a binary min-heap. Native compute runs the calculation off the UI isolate;
request generations discard cancelled or stale results. A source pack removal
clears its map result. Networks are portable in backups; selected route results
are transient unless exported as GeoJSON.

Bundled guidance has a revision separate from the SQL schema. Opening an old
installation refreshes only the reserved built-in pack in one reindexing
transaction, preserving personal notes, pins and valid favorites. No update is
performed when the current bundled revision is already present.
