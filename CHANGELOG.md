# Changelog

## 0.7.1+11

- Каталог атласів, геошарів та локальних моделей з SHA-256 і ліцензіями.
- Добровільні username-акаунти, TOTP, резервні коди, відкликання і видалення.
- CSP і захист backend; збережено браузер/офлайн-сторінки з 0.7.0.
- Межі безпеки, моделі й перевірки: docs/CATALOG_ACCOUNTS.md.

## 0.7.0 candidate — browser and offline reading

- Direct bounded HTTPS text reader, validated redirects/links, cancellation and in-memory history.
- Native system WebView on Android/iOS/macOS, explicit JavaScript toggle, no bridge to AMID data.
- Offline page collection integrated with SQLite search, favorites and portable version-1 backups.
- Stable URL-derived identities, update/delete and non-destructive restore merge.
- Shared roadmap for regional/historical maps, platform capabilities and the separate physical radio dock/gateway.
- Native WebView device acceptance, full Windows/Linux WebView, account backend and LoRa integration remain open.


## 0.6.0-beta.8 — повний офлайн-набір

[Опубліковані пакети](https://github.com/DimasikBog/AMID-Offgrid/releases/tag/v0.6.0-beta.8). Перевірено 126 Flutter-тестів, 19 Python-тестів,
вісім збірок, чотири нативні емуляторні сценарії та всі опубліковані SHA-256.

- Повні нативні збірки містять перевірену Qwen3 0.6B Q8, карту світу й довідник.
- Підготовка на першому запуску без мережі; частини до 8 MiB замість 639 MB у пам’яті.
- Легка збірка: одна кнопка встановлення всіх базових компонентів, пауза/докачування, SHA-256 і відновлення.
- Автоматичний запуск вибраної моделі з першим запитом; власні моделі й нотатки зберігаються.
- Навмисно видалена модель не встановлюється знову без команди користувача.
- CI перевіряє модель всередині реальних пакетів, автоматичне встановлення й генерацію.
- iOS: довший обмежений холодний запуск worker та контрольований backport запуску симулятора.
- watchOS: кнопка на весь рядок, читабельний стан доступності й перевірка після перезапуску.
- Український пошук FTS4 виправлено; наявні базові перевірки оновлюються для повного набору.
- Детальні карти вулиць, реальні BLE/GPS, фізичні пристрої, підписи й магазини — окремі завдання.

## Вебоновлення після 0.5.0-beta.7

- Видима підготовка офлайн-файлів, помилки та повтор без очищення нотаток.
- Перевірка bytes/SHA-256 статичних файлів, відновлення відсутніх файлів.
- Root/deep links із кешованим HTML тієї самої версії.
- Підказки встановлення, browser install prompt та явне оновлення зі збереженням змін.
- Стартовий екран замість порожнього вікна, окрема web-панель без перекриття Flutter.
- 12 Python-тестів з 10 JS-сценаріями; нативні beta.7 пакети не змінюються.

## 0.5.0 candidate

- MIT license for AMID-owned code and contribution/install guides.
- Adaptive rail/bottom navigation, keyboard shortcuts, lazy visited tabs and back-to-home.
- New responsive home panel, favorite previews and quick actions.
- Persistent reader scale, text copy and personal checklist, including portable backups.
- Preserve queued preferences when restoring legacy backups with missing optional fields.
- Light interface unloads inference and stops the nearby session; reader-only article actions.
- Native desktop hosts, runtime SQLite FFI and temporary-database diagnostic entrypoint.
- Local-renderer PWA cache and bounded same-scope service worker ownership.
- Standalone Kotlin Wear OS and SwiftUI watchOS pocket clients with bundled cards.
- Standard public-runner build matrix and all-platform hash-gated beta publication.

Compilation is separate from physical-device acceptance, Apple signing and stores.


## 0.4.2 candidate

- Reject duplicate, oversized or mistyped MBTiles metadata before activation.
- Verify a real raster sample at import/open; bound encoded bytes, dimensions
  and pixel count before pixel decoding on every accessed tile.
- Support PNG/JPEG/WebP, normalized SQLite views and TMS row conversion.
- Derive a usable fallback center from an actual tile when metadata lacks one.
- Replace synchronous tile access with owned asynchronous read-only archives.
- Bound retained image keys, evict on close and close stale archive opens.
- Skip damaged later tiles with a visible warning and offer retry on open errors.
- Correct the about text to describe the existing imported-network routes.
- Add import, real SQLite, image-codec, cache and widget lifecycle regressions.

This validates a sample plus accessed tiles, not the entire archive or arbitrary
SQLite query cost. Physical phone memory/performance and native platform behavior
remain unverified. See docs/OFFLINE_MAPS.md for deliberate application limits.

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
