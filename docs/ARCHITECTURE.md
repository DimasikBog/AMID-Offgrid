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
a binary min-heap. The native RouteWorker owns one isolate and its reply port;
cancellation, replacement, disposal and app backgrounding request immediate
shutdown and close the port, including a late spawn completion. The web worker
can cancel a queued bounded calculation before it starts, but cannot preempt
synchronous work already running on the main event loop. Request generations
also discard stale results. A source pack removal
clears its map result. Networks are portable in backups; selected route results
are transient unless exported as GeoJSON.

Bundled guidance has a revision separate from the SQL schema. Opening an old
installation refreshes only the reserved built-in pack in one reindexing
transaction, preserving personal notes, pins and valid favorites. No update is
performed when the current bundled revision is already present.

Import streams and checksum reads use a cancellable StreamIterator. Cancellation
closes the upstream subscription even when no next chunk arrives. A check inside
the serialized mutation queue prevents cancelled imports/assets/restores from
starting a later write. A database transaction already committing is allowed to
finish atomically; this is not a rollback of an already completed operation.
Verified starter bytes return to the resumable partial file if activation fails.

Route fitting runs after the route panel has laid out. Short viewports and large
text get an independently controlled scroll area and visible scrollbar, preserving
map gestures and access to controls without forcing text to shrink.

RasterArchive owns an asynchronous read-only sqflite connection. Metadata rows
and returned strings are capped in SQL; tile data is returned only if its BLOB
length is within the byte limit. Opening checks an actual decoded sample.
Subsequent tiles are checked lazily. Both physical tables and normalized views
are accepted. XYZ requests are converted to MBTiles TMS rows. Without geographic
metadata, the first stored tile supplies the fallback center.

The codec checks encoded signatures and ImageDescriptor dimensions before
pixel decoding. Animated images are rejected. RasterTileProvider scopes cache
keys to one archive, retires old keys and evicts them on disposal. Archive close
rejects queued reads and drains in-flight SQL before closing the connection.
Widget generations close late opens and ignore stale errors. Corrupt lazy tiles
fall back to transparency; the map reports a bounded warning. SQL result limits
do not bound evaluation cost inside SQLite, including complex views or text
conversions. See OFFLINE_MAPS.md for limits and remaining phone checks.
