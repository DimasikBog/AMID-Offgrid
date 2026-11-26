# USB and local panel protocol

Mega: 115200 baud, ASCII, LF-terminated commands, max line 95 characters.
Opening USB commonly resets the board. Start with STOP + STATUS; expect
`INFO 2 steps_per_rev max_position`, with max_position = steps_per_rev * 3 / 4.
Do not infer actual motion or position merely from a transmitted command.

| Command | Effect / precondition |
|---|---|
| PING | Renew Mega host heartbeat; armed states fault after >3 s without it |
| STATUS | INFO, STATE and INPUTS telemetry; no movement |
| STOP | Close sample window, de-energize, discard home reference |
| ARM | Explicit homing / backoff; DISARMED or FAULT only, NC checks apply |
| JOG -16 / JOG 16 | Unhomed short movement; firmware permits signed 1..32, DISARMED only |
| SCAN | Coarse/fine scan after homing, only when allowed by firmware state |
| S token packet_id rssi10 snr10 | Matching stationary-window RF feedback, internal bridge use |

`INPUTS 1 left right stop`: 0 = closed to GND, 1 = open/actuated/broken circuit.
`STATE n POS steps HOMED 0|1`: see README_UA.md for numeric state names.
`WINDOW token position`: open stationary sample window after 1.5 s settling.
`RESULT token position phase count sufficient rssi10 snr10 reason`:
phases 0 coarse, 1 fine, 2 tracking. count >=2 distinct valid ACKs is sufficient;
otherwise both metrics are NA. Scan windows finish after >=30 s with sufficient
samples or at 80 s; tracking windows last 80 s. CLOSE invalidates pending feedback.
No signal is not converted to a synthetic angle.

The panel wraps the USB bridge, it does not open a second serial connection.
Its child bridge is started with --external-control and requires CONTROL_PING
on stdin every <=3 s. That command is never forwarded to Mega. Stdin EOF,
parent heartbeat loss or shutdown causes a STOP request and bridge exit.
The page separately leases the panel via POST /api/heartbeat. Losing that lease
requests STOP; it does not resume ARM/SCAN when the page returns.

The HTTP panel binds 127.0.0.1 only. GET /api/state and JSON POST
/api/heartbeat or /api/command require the per-process bearer key. POST also
requires the exact local Origin. Commands are an allowlist, not arbitrary serial
input. It is not a supported remote phone API. A future mobile client needs an
explicit authenticated transport and the same stop/lease rules; do not expose
this HTTP port to the Internet or describe current iPhone motor control as done.
