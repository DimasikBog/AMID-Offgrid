# Changelog

## 0.4.1 candidate

- Cancel stalled imports and checksum reads by closing the upstream subscription.
- Reject cancelled knowledge/asset/restore writes when their turn in the queue arrives.
- Retain verified starter bytes for retry when metadata activation fails.
- Own and terminate native route worker isolates/ports on cancellation, replacement,
  screen disposal and app backgrounding; handle early/late spawn and error races.
- Keep the browser fallback bounded and cancel queued work before it starts.
- Fit routes after panel layout and preserve control access on short, large-text maps.
- Regression tests for stalled streams, digest cancellation, queued writes,
  native/web worker lifecycle, unsendable messages, app pause/resume and viewport fitting.

## 0.4.0 candidate

- Offline shortest-distance routing over explicitly connected imported AMID networks.
- Directed edges, intermediate geometry, node search and route reversal.
- Map overlay, A/B markers, distance and GeoJSON export with provenance.
- Portable network import, SQLite persistence and backup/restore.
- Bounded validation and background native calculation; cancelled/stale results ignored.
- Bundled guidance refresh for existing installations, preserving personal data.
- Synthetic example, format instructions and algorithm/storage/UI regression tests.

This adds routing over user-supplied networks. OSM/PBF, address lookup, road
profiles, live conditions and turn-by-turn navigation remain unimplemented.
Phone tests, iOS compilation/signing and store publication remain unverified.

## 0.3.0 candidate

- Personal offline notes with editing, deletion, categories, favorites and paging.
- Persistent appearance preference and portable draft/favorites backup fields.
- Optional password-protected backups with authenticated encryption and bounded key derivation.
- Long UTF-8 text/Markdown imports split without content loss; cancellable streaming and stricter map metadata checks.
- Draft persistence fixes, atomic save-to-message, message history paging and deletion.
- Editable map pins and GeoJSON point export.
- Assistant retrieval cancellation/error handling; stale requests cannot update newer state.
- BLE lifecycle guards and expired pairing-state cleanup on disconnect.
- Explicit Android development/distribution signing; optional signed APK/AAB workflow.
- Unsigned IPA packaging, exact source/run manifests and release-tool tests.

This is a source candidate. Physical devices, new iOS signing, credentials and
store publication remain separate unverified stages until their reports exist.

## 0.2.0

Existing beta v0.2.0-beta.1: 14 tests, Android development APK and unsigned iOS
build. RELEASE.json and VALIDATION.md retain that historical evidence.
