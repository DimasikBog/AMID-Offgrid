# Validation record — desktop package 0.5.0 / motor firmware 0.3

Local source verification on Linux, 2026-11-26:

| Check | Result |
|---|---|
| Python unit and local HTTP/serial-fixture integration tests | 45 PASS |
| Host C++ firmware logic test, g++ with warnings as errors | PASS |
| ATmega2560 build, Arduino AVR core 1.8.6 / AVR GCC 7.3 | PASS |
| Firmware flash text+data | 12638 bytes |
| Static RAM data+bss | 945 bytes; stack not measured on device |
| JavaScript syntax | PASS |
| Browser rendering on this local machine | NOT_RUN: browser binary absent; download blocked |
| ZIP and SHA-256 package integrity | PASS |
| Physical motor, switches, powerbank, RF/ACK, range, angle | NOT_RUN |

GitHub workflow `.github/workflows/azimuth.yml` adds Python tests on Windows,
a Chromium browser test and independent AVR build/package. Do not treat a
configured workflow as a completed run: inspect Actions for the actual commit.
The release job runs only after those checks pass on main. Browser tests use
local protocol fixtures, never serial hardware. Native Flutter application code
is unchanged by this module; its own mobile workflow remains separate.

The physical acceptance sheet is BENCH_CHECKLIST.csv and contains only NOT_RUN
until an operator records observed results. Nominal step positions, RF medians,
ACK/window filtering and software stops are not proof of actual angular accuracy,
antenna gain, range, powerbank endurance or emergency delivery.
