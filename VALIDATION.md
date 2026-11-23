# Перевірка AMID Offgrid 0.2.0
Дата: 2026-11-23

- Flutter 3.47.6, Dart 3.13.5.
- flutter analyze --no-pub: No issues found.
- flutter test --no-pub --reporter expanded: 14 passed.
- Протокол: AES-GCM, двонапрямні ключі, неправильний секрет, підміна, повтори, черговість, 4000 кириличних символів при MTU20, граничні розміри й час життя фрагментів.
- SQLite: Unicode FTS, повторний запуск, rollback транзакції й стану в RAM, відновлення черги після помилки, backup/restore, відсікання некоректних даних.
- UI: навігація на екрані390×844 без layout exception. Додатково оглянуто браузерний Flutter-перегляд.
- AndroidManifest.xml та iOS plist/privacy manifest синтаксично прочитані.
- Android APK 0.2.0+2: зібрано. 85 447 288 байтів, arm64-v8a, minSdk26, targetSdk36.
- SHA-256 APK: 1189101a797e21fed540c6ceeda3f4c746f3b814296890614c449adac81db46c.
- Підпис development: apksigner verify пройдено (v2/v3), zipalign 16KiB пройдено; ARM64 ELF-сегменти підтримують 16KiB.
- 2026-11-23: APK завантажено з проєкту, ZIP перевірено повністю, розмір і SHA-256 збігаються. Актуальний код перенесено для роботи через GitHub.
- iOS: 2026-11-23 успішно скомпільовано на macOS у GitHub Actions, запуск 45147118690, коміт a5ecca46ed058a6b4c0c162f1b4fd4ee4059a7ab. Runner.app для iOS17+, ARM64, com.amid.offgrid, версія0.2.0. Перевірено ZIP, контрольну суму, Info.plist, платформу iPhoneOS і Mach-O ARM64. Архів непідписаний; Apple-підпис та перевірка на iPhone залишаються необхідними.
- SHA-256 AMID_Offgrid_iOS_unsigned.zip: 2886b262db293c9e903d2c2f3cf86842921902e3ba72e4817e4061709d9aa58f (15 731 018 байтів).
- GitHub Actions quality, запуск 45147118690: No issues found; +14: All tests passed.
- GitHub Actions 45147118690: quality, Android release build, перевірка APK і iOS unsigned build завершилися success. Виправлено ліміт Gradle heap для D8; фінальна перевірка Android пройшла без обходу перевірок.
- BLE на реальних Android/iPhone, GPS на пристрої, нативні діалоги Files і реальна генерація на телефоні не тестувалися.
- Це не підтвердження магазинної готовності, дальності BLE, сумісності з іншими месенджерами або точності ШІ.
