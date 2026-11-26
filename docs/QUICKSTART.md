# Швидкий старт AMID Offgrid

## Просто відкрити додаток

[Відкрити вебверсію](https://dimasikbog.github.io/AMID-Offgrid/).
Перший запуск потребує мережі: дочекайся повідомлення «Офлайн: файли збережені».
У меню **⋮ → Перед дорогою** видно власні матеріали й завантажені області вулиць.
Перед поїздкою відкрий потрібну область без мережі. Огляд світу не замінює вулиці.

На iPhone можна додати вебверсію на екран «Додому» через Safari — для цього
не потрібен підпис нативного застосунку. Інструкція й межі: [встановлення](INSTALL.md#браузер-і-pwa).
Вебверсія має пошук у матеріалах; GGUF, нативні MBTiles і прямий BLE потребують нативного пакета.

## Завантажити готову збірку

[Перевірений кандидат 0.10.2-beta.19](https://github.com/DimasikBog/AMID-Offgrid/releases/tag/v0.10.2-beta.19).
Це beta, не магазинний реліз. Поряд із пакетами є маніфести з SHA-256 та джерелом збірки.

| Пристрій | Файл |
| --- | --- |
| Android ARM64 | `AMID_Offgrid_android_arm64.apk` |
| Windows x64 | `AMID_Offgrid_Windows_x64.zip` — розпакувати цілком |
| iPhone / iPad | `AMID_Offgrid_iOS_unsigned.ipa` — потрібен власний підпис |
| Інші платформи й годинники | [Повна таблиця та вимоги](INSTALL.md) |

Перед оновленням експортуй резервну копію; GGUF і детальні карти збережи окремо.
Фізичні пристрої, підписи й магазини мають окремі обмеження з інструкції.

## Запустити вихідний код

Потрібні Git, **Flutter 3.47.6** (Dart 3.13.5 у комплекті), Python 3.11+ і Chrome.
Це команди для власного локального клону; керований ProductOS preview має свій запуск.

Windows PowerShell:

```powershell
git clone https://github.com/DimasikBog/AMID-Offgrid.git
Set-Location AMID-Offgrid
flutter --version
flutter pub get --enforce-lockfile
py -3 scripts/check_project.py
flutter run -d chrome
```

Linux / macOS:

```sh
git clone https://github.com/DimasikBog/AMID-Offgrid.git
cd AMID-Offgrid
flutter --version
flutter pub get --enforce-lockfile
python3 scripts/check_project.py
flutter run -d chrome
```

Це легкий запуск із вихідного коду. Для повного нативного набору окремо виконай
`python3 scripts/prepare_offline_payload.py` (у Windows — `py -3` замість `python3`).
Команда завантажує приблизно 640 MB закріпленої Qwen-моделі й перевіряє SHA-256.
Нативна Android-збірка потребує Android SDK; iOS — macOS/Xcode та окремого підписування.

## Зібрати PWA для власного сервера

```sh
flutter build web --release --no-web-resources-cdn
python3 scripts/build_web_cache.py build/web
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Відкрий `http://127.0.0.1:8080/`. У Windows використовуй `py -3` замість `python3`.
Для хостингу в підкаталозі передай правильний `--base-href`; для зовнішнього
розгортання потрібен HTTPS. GitHub Pages workflow визначає шлях репозиторію автоматично.

[Перевірки 0.10.2](VALIDATION_0_10_2.md) · [Офлайн-набір](OFFLINE_PREPARATION.md) ·
[SOS і тренування](EMERGENCY_SOS.md) · [Сторонні ліцензії](../THIRD_PARTY_NOTICES.md).
