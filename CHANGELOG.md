# Changelog

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
