# Contributing to the antenna bench

Work inside `hardware/azimuth`. No Flutter/phone-app change is required to work
on this module. Keep movement opt-in, NC interlocks, software bounds, heartbeat
stops, ACK/window binding and honest missing measurements.

Runtime: Python 3.10+, requirements.txt. CI uses Python 3.12 on Linux and Windows.
Run unittest as shown in README.md. Run the host C++ firmware test using g++ on
Linux. Fixtures are synthetic protocol inputs, never physical RF evidence.

For browser checks:

```sh
python -m pip install -r requirements-dev.txt
python -m playwright install --with-deps chromium
python tools/check_panel_browser.py
```

`CHROMIUM_EXECUTABLE` optionally selects an existing Chrome/Chromium executable.
The test uses local HTTP + synthetic process/telemetry fixtures and never opens
a real serial port. It covers desktop/mobile layout, command clicks, no initial
angle/RSSI, page reload and heartbeat loss. This is not an RF or motor test.

Linux x86-64, Python 3.12, reproducible AVR toolchain:

```sh
python tools/download_avr.py
python tools/build_avr.py
python tools/package.py
```

Downloaded archives are verified against recorded SHA-256 values. The ZIP in
dist/ excludes personal sessions, diagnostic logs, virtual environments and
build-tool caches; it includes the corresponding core source when firmware
binaries are included. SHA256.json identifies the files inside the package.

For a change, describe its trigger, resulting behavior and evidence. Submit a
pull request to AMID-Offgrid. Physical results must record board revision,
firmware, antenna, supply, conditions and instrument; never fill NOT_RUN with
estimated or simulated values. Do not include private channel keys, local
session logs, locations or account tokens in a public contribution.
