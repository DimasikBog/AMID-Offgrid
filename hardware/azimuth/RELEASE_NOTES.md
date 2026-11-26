# AMID Azimuth 0.5.0 — experimental open-source bench

Source, pin-to-pin wiring, bill of materials, first-run instructions,
troubleshooting and loopback browser control for Mega + laptop + two own
Meshtastic EU868 radios. Motor firmware v0.3 / INFO 2, INPUTS 1.

The package includes source, HEX/ELF, toolchain metadata and corresponding
Arduino core source. Start with FIRST_RUN_UA.md; Windows setup/launcher included.

Publication is gated by 45 Python checks on Linux and Windows, host C++ firmware
checks, real Chromium UI tests using protocol fixtures, and an AVR build.
Fixtures do not represent physical RF or motor evidence. Actual workflow results
are available in Actions for the release source commit.

Physical motor, NC switches, powerbank, radio ACK, range and angle calibration:
NOT_RUN. Windows CMD interaction on a physical Windows computer: NOT_RUN.
Not certified emergency equipment or global Internet coverage. Direct iPhone
motor control is not implemented. Own source MIT; third-party licenses apply.
