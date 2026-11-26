# AMID Offgrid

[Українська](README.md) · English

Open-source Flutter app for offline knowledge, notes, maps and local AI.
The app UI is currently Ukrainian. Android, iOS, desktop and web share Flutter
code; Wear OS and watchOS have separate limited companion apps.

[Open the web app](https://dimasikbog.github.io/AMID-Offgrid/) ·
[Download 0.10.2-beta.19](https://github.com/DimasikBog/AMID-Offgrid/releases/tag/v0.10.2-beta.19) ·
[Source code](https://github.com/DimasikBog/AMID-Offgrid)

## What works

- Offline library, notes, search, favorites and portable backups.
- Street maps, saved regional areas, personal points and map styles.
- Native GGUF model selection and local inference; web uses material search.
- Optional accounts with TOTP and encrypted offline personalization.
- Trip preparation inventory with direct access to saved street regions.
- SOS assistance through system phone/SMS UI and a separate training mode.

A saved inventory is not a file-integrity or connectivity check. SOS does not
confirm dispatch delivery: system confirmation and sending the SMS remain
user actions. Exercise SOS only in training mode, never with test emergency calls.

## Install or run

The web app needs a first online load before offline use. On iPhone, Safari can
add it to the Home Screen. Web does not provide native GGUF, MBTiles or direct BLE.

Release downloads include platform manifests with source commits and SHA-256.
Android packages use a development signature. Native iOS/watchOS packages are
unsigned; an IPA cannot be installed just by opening it. Desktop archives must
be extracted completely. [Installation and platform limits](docs/INSTALL.md).

For a local source preview, install Git, Flutter **3.47.6**, Python 3.11+ and Chrome:

```sh
git clone https://github.com/DimasikBog/AMID-Offgrid.git
cd AMID-Offgrid
flutter pub get --enforce-lockfile
python3 scripts/check_project.py
flutter run -d chrome
```

On Windows, use `py -3` instead of `python3`.
[Quick start, native payload and self-hosted PWA](docs/QUICKSTART.md).

## License and verification

Application source is licensed under [MIT](LICENSE). Maps, model weights,
fonts and imported content retain their own licenses and attribution;
see [third-party notices](THIRD_PARTY_NOTICES.md).

The 0.10.2 candidate passed 205 Flutter tests, platform builds and four
emulator/simulator scenarios. Physical devices, store submission, production signing
and actual emergency delivery have not been validated.
[Evidence and exact source revisions](docs/VALIDATION_0_10_2.md).

## Contribute

[Contribution guide](CONTRIBUTING.md) · [Security reporting](SECURITY.md) ·
[Report a non-security bug](https://github.com/DimasikBog/AMID-Offgrid/issues/new).
Use synthetic data in public reports; private vulnerability reporting is described
in the security policy and depends on the repository setting.
