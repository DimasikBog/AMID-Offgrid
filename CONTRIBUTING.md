# Розробка AMID Offgrid

[Швидкий старт](docs/QUICKSTART.md) · [English](README.en.md) · [Повідомлення про вразливості](SECURITY.md)

MIT поширюється на власний код AMID. Не додавай сторонні тексти, карти, моделі
або бінарні файли без права поширення. Особисті дані та ключі не комітяться.

Flutter 3.47.6 / Dart 3.13.5. Один Flutter-код для телефону, комп’ютера й web;
малі watch-клієнти — `android/wear` (Kotlin) та `watchos` (SwiftUI), спільні
вбудовані матеріали — `wearables/cards.json`. Автоматичної phone/watch sync немає.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --concurrency 2
python3 scripts/check_project.py
python3 -m unittest discover -s scripts -p 'test_*.py'
```

Для CI встановлюй `CI=true` і `FLUTTER_SUPPRESS_ANALYTICS=true`.
Desktop: `flutter build windows`, `flutter build linux` або `flutter build macos`
на відповідній ОС. macOS/iOS використовують SwiftPM. Wear OS: спочатку
`flutter build apk --config-only`, потім у `android/` — `./gradlew :wear:assembleRelease`.
Watch: на macOS із XcodeGen — `cd watchos && xcodegen generate`, далі збірка
за командами `.github/workflows/mobile.yml`.

Роби окрему гілку й PR. Для нового кандидата підніми version/build у pubspec,
lib/version.dart і watch-клієнтах: check_project.py перевіряє узгодженість.
Зміни стану мають читати старі копії без втрати даних. Верифікуй відмову на
пошкоджених даних і скасуванні, а не лише успішний шлях.

Стандартні нові platform jobs запускаються тільки для public-репозиторію.
Публікація prerelease дозволена лише після всіх успішних збірок, із main push
або ручного запуску власником. Fork PR не має publication/signing секретів.
Виходи перевіряються за source SHA, версією й digest перед створенням релізу.
Неповний draft не оголошується готовим.

Для bug report вкажи версію, платформу, відтворення й очікувану поведінку.
Не прикладай особисту базу або резервну копію; мінімальний синтетичний приклад
достатній. Тести на справжніх телефонах/годинниках позначай виконаними лише з
описом конкретного пристрою та точного артефакту.

## Перевірки вебофлайн

Для `scripts/test_web_offline.py` потрібен Node.js 22+ (перевірено з 24).
Використовуються лише вбудовані Web API/VM fixtures, без npm та Node-проєкту.
`python3 -m unittest discover -s scripts -p 'test_*.py'` виконує всі перевірки.
Після `flutter build web` виконай `python3 scripts/build_web_cache.py build/web`.
Не публікуй build до генерації offline manifest/worker. Див. docs/WEB_OFFLINE.md.

## Зручний шаблон повідомлення про помилку

[Створити issue](https://github.com/DimasikBog/AMID-Offgrid/issues/new) із таким описом:

```text
Версія / source commit:
Платформа, ОС і модель пристрою (без IMEI/серійного номера):
Кроки відтворення:
Очікуваний результат:
Фактичний результат:
Очищена помилка або знімок із синтетичними даними:
Фізичний пристрій чи емулятор:
```

Не публікуй координати, токени, TOTP/резервні коди, приватні ключі, особисті
повідомлення чи повні резервні копії. Для вразливостей використовуй
[SECURITY.md](SECURITY.md). Для SOS підходять підміни або тренування;
тестові дзвінки й SMS до екстрених служб робити не потрібно.

Для серверних змін додатково виконай `node --test scripts/test_account_service.mjs`.
У Windows замінюй `python3` на `py -3`.

## English essentials

Fork the repository, use a focused branch and submit a PR to `main`. Use
Flutter 3.47.6, keep dependency pins and preserve app IDs, backups and user data.
Include actual test commands/results; mark tests you did not run. Distinguish
emulator evidence from physical-device testing. Do not upload credentials,
private signing material, personal backups or location data. Use synthetic
examples and test SOS only with fakes/training. Preserve third-party licenses.
The native build/release rules above remain the reference for contributors.
