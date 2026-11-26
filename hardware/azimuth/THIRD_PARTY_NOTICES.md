# Third-party components

Own Python/C++ code, diagrams and documentation: MIT, see LICENSE.

- Arduino AVR core **1.8.6**, LGPL-2.1, upstream source:
  https://github.com/arduino/ArduinoCore-avr/tree/1.8.6
  Official archive SHA-256: ff1d17274b5a952f172074bd36c3924336baefded0232e10982f8999c2f7c3b6.
  The source repository stores our sketch, not a renamed Arduino binary.
  `tools/download_avr.py` verifies upstream archives; `tools/package.py` includes
  the corresponding full Arduino source archive alongside compiled firmware
  when producing a firmware distribution. Keep that archive and its notices
  with binary redistribution. Build sources and scripts allow rebuilding the
  firmware with changes to the Arduino core.
- avr-gcc **7.3.0-atmel3.6.1-arduino7**, GNU toolchain component licenses and
  runtime exceptions apply. It is downloaded for building, not repackaged as
  AMID-owned software. Keep upstream source/license links.
- meshtastic Python **2.7.11**: https://github.com/meshtastic/python/tree/v2.7.11
  Its license and dependencies apply separately. Installed by pip.
- pyserial **3.5**: https://github.com/pyserial/pyserial/tree/v3.5
  BSD-3-Clause. Installed by pip.
- Playwright **1.62.0** is a test-only dependency; Apache-2.0.
  https://github.com/microsoft/playwright-python
- Meshtastic device firmware is not built, relicensed or included here. Use
  official firmware matching the exact radio board and retain its licenses.

Dependency versions do not imply a physical RF compatibility test was run.
