import 'dart:async';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../models/mesh_wire.dart';
import 'radio_transport.dart';

RadioTransport createRadioTransport() => _BleRadioTransport();

class _BleRadioTransport extends RadioTransport {
  CentralManager? _manager;
  Peripheral? _peer;
  GATTCharacteristic? _from, _to, _number;
  final _found = <String, DiscoveredEventArgs>{};
  final _subscriptions = <StreamSubscription>[];
  final _packets = StreamController<Uint8List>.broadcast(sync: true);
  Timer? _scanTimer, _poll;
  Future<void> _closing = Future.value();
  int _epoch = 0;
  int? _drainingEpoch;
  bool _dirty = false, _disposed = false, _connecting = false;
  @override
  bool connected = false;
  @override
  bool scanning = false;
  @override
  String status = 'Модуль не підключено';
  @override
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  @override
  Stream<Uint8List> get packets => _packets.stream;
  @override
  List<RadioDevice> get devices => _found.entries
      .map(
        (e) => RadioDevice(
          e.key,
          e.value.advertisement.name ?? 'Meshtastic',
          e.value.rssi,
        ),
      )
      .toList(growable: false);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) {
      throw StateError('Підключення завершено.');
    }
  }

  void _initialize() {
    if (_disposed || !supported) {
      throw UnsupportedError('Bluetooth LoRa доступний на Android та iPhone.');
    }
    if (_manager != null) return;
    final manager = _manager = CentralManager();
    _subscriptions.add(
      manager.discovered.listen((e) {
        if (!scanning) return;
        if (_found.containsKey(e.peripheral.uuid.toString()) ||
            _found.length < 40) {
          _found[e.peripheral.uuid.toString()] = e;
          _changed();
        }
      }),
    );
    _subscriptions.add(
      manager.connectionStateChanged.listen((e) {
        if (_peer?.uuid == e.peripheral.uuid &&
            e.state == ConnectionState.disconnected) {
          unawaited(_fail('Модуль від’єднався. Підключи його повторно.'));
        }
      }),
    );
    _subscriptions.add(
      manager.stateChanged.listen((e) {
        if (e.state != BluetoothLowEnergyState.poweredOn &&
            (connected || scanning || _connecting)) {
          unawaited(_fail('Bluetooth вимкнено або дозвіл відкликано.'));
        }
      }),
    );
    _subscriptions.add(
      manager.characteristicNotified.listen((e) {
        if (connected &&
            e.peripheral.uuid == _peer?.uuid &&
            e.characteristic.uuid.toString() == meshFromNumUuid) {
          _drain();
        }
      }),
    );
  }

  Future<void> _authorize() async {
    final manager = _manager!;
    if (defaultTargetPlatform == TargetPlatform.android) {
      if (!await manager.authorize()) {
        throw StateError('Надай дозвіл Bluetooth у налаштуваннях.');
      }
    }
    if (manager.state != BluetoothLowEnergyState.poweredOn) {
      await manager.stateChanged
          .firstWhere((e) => e.state == BluetoothLowEnergyState.poweredOn)
          .timeout(const Duration(seconds: 20));
    }
  }

  @override
  Future<void> scan() async {
    _initialize();
    if (_connecting) throw StateError('Зачекай завершення підключення.');
    await stop();
    final epoch = _epoch;
    await _authorize();
    _check(epoch);
    _found.clear();
    scanning = true;
    status = 'Шукаю Meshtastic-модулі…';
    _changed();
    try {
      await _manager!
          .startDiscovery(serviceUUIDs: [UUID.fromString(meshServiceUuid)])
          .timeout(const Duration(seconds: 12));
      _check(epoch);
      _scanTimer = Timer(
        const Duration(seconds: 15),
        () => unawaited(_finishScan(epoch)),
      );
    } catch (_) {
      if (epoch == _epoch) await stop();
      rethrow;
    }
  }

  Future<void> _finishScan(int epoch) async {
    if (epoch != _epoch || _disposed) return;
    scanning = false;
    try {
      await _manager?.stopDiscovery();
    } catch (_) {}
    if (epoch != _epoch || _disposed) return;
    status = _found.isEmpty
        ? 'Модулі не знайдено. Увімкни BLE на радіо.'
        : 'Вибери свій модуль';
    _changed();
  }

  @override
  Future<void> connect(String id) async {
    _initialize();
    if (_connecting) throw StateError('Підключення вже виконується.');
    final device = _found[id];
    if (device == null) throw const FormatException('Спочатку знайди модуль.');
    await stop();
    _connecting = true;
    final epoch = _epoch;
    _peer = device.peripheral;
    status = 'З’єдную модуль. Підтвердь PIN із його екрана.';
    _changed();
    try {
      await _authorize();
      _check(epoch);
      await _manager!.connect(_peer!).timeout(const Duration(seconds: 25));
      _check(epoch);
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _manager!.requestMTU(_peer!, mtu: 512);
        } catch (_) {}
      }
      _check(epoch);
      final services = await _manager!
          .discoverGATT(_peer!)
          .timeout(const Duration(seconds: 15));
      _check(epoch);
      final service = services.firstWhere(
        (s) => s.uuid.toString() == meshServiceUuid,
      );
      _from = service.characteristics.firstWhere(
        (c) => c.uuid.toString() == meshFromRadioUuid,
      );
      _to = service.characteristics.firstWhere(
        (c) => c.uuid.toString() == meshToRadioUuid,
      );
      _number = service.characteristics.firstWhere(
        (c) => c.uuid.toString() == meshFromNumUuid,
      );
      await _manager!.setCharacteristicNotifyState(
        _peer!,
        _number!,
        state: true,
      );
      _check(epoch);
      connected = true;
      status = 'Bluetooth підключено; читаю конфігурацію';
      _poll = Timer.periodic(const Duration(seconds: 3), (_) => _drain());
      _changed();
    } catch (_) {
      if (epoch == _epoch) {
        await _fail(
          'Не вдалося підключити модуль. Перевір PIN і прошивку Meshtastic.',
        );
      }
      rethrow;
    } finally {
      if (epoch == _epoch) {
        _connecting = false;
        _changed();
      }
    }
  }

  @override
  Future<void> write(Uint8List packet) async {
    if (!connected || _peer == null || packet.isEmpty || packet.length > 512) {
      throw StateError('Модуль не готовий.');
    }
    final epoch = _epoch, peer = _peer!, to = _to!;
    final maximum = await _manager!.getMaximumWriteLength(
      peer,
      type: GATTCharacteristicWriteType.withResponse,
    );
    _check(epoch);
    if (packet.length > maximum) {
      throw const FormatException(
        'Замалий BLE MTU. Скороти повідомлення або перепідключи модуль.',
      );
    }
    // One protobuf per GATT write. AMID frame_codec fragments are not Meshtastic.
    await _manager!
        .writeCharacteristic(
          peer,
          to,
          value: packet,
          type: GATTCharacteristicWriteType.withResponse,
        )
        .timeout(const Duration(seconds: 12));
    _check(epoch);
    _drain();
  }

  void _drain() {
    if (!connected || _disposed) return;
    final epoch = _epoch;
    if (_drainingEpoch == epoch) {
      _dirty = true;
      return;
    }
    _drainingEpoch = epoch;
    unawaited(() async {
      try {
        var budget = 512;
        do {
          _dirty = false;
          for (var count = 0; count < 128; count++) {
            _check(epoch);
            final bytes = await _manager!
                .readCharacteristic(_peer!, _from!)
                .timeout(const Duration(seconds: 8));
            _check(epoch);
            if (bytes.isEmpty) break;
            if (bytes.length > 512 || --budget == 0) {
              throw const FormatException('Надмірний потік від модуля.');
            }
            _packets.add(bytes);
          }
        } while (_dirty && connected);
      } catch (_) {
        if (!_disposed && epoch == _epoch) {
          await _fail('Помилка читання модуля. Перепідключи його.');
        }
      } finally {
        if (_drainingEpoch == epoch) _drainingEpoch = null;
      }
    }());
  }

  Future<void> _fail(String message) async {
    final epoch = _epoch + 1;
    await stop();
    if (!_disposed && epoch == _epoch) {
      status = message;
      _changed();
    }
  }

  @override
  Future<void> stop() async {
    _epoch++;
    _scanTimer?.cancel();
    _poll?.cancel();
    final peer = _peer;
    _peer = null;
    final wasScanning = scanning;
    connected = false;
    scanning = false;
    _connecting = false;
    _from = null;
    _to = null;
    _number = null;
    status = 'Модуль не підключено';
    _changed();
    final closing = _closing.then((_) async {
      if (wasScanning) {
        try {
          await _manager?.stopDiscovery();
        } catch (_) {}
      }
      if (peer != null) {
        try {
          await _manager?.disconnect(peer);
        } catch (_) {}
      }
    });
    _closing = closing.catchError((Object _) {});
    await closing;
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    for (final sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    unawaited(_packets.close());
    super.dispose();
  }
}
