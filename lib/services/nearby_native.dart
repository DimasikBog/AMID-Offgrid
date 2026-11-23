import 'dart:async';
import 'dart:math';

import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'package:flutter/foundation.dart';

import '../models/data.dart';
import 'frame_codec.dart';
import 'secure_channel.dart';
import 'store.dart';

class NearbyService extends ChangeNotifier {
  NearbyService(this.store);
  final AppStore store;
  static final serviceId = UUID.fromString(
        'a61d0001-9bce-4c86-b032-72af1f570001',
      ),
      rxId = UUID.fromString('a61d0002-9bce-4c86-b032-72af1f570001'),
      txId = UUID.fromString('a61d0003-9bce-4c86-b032-72af1f570001');
  CentralManager? _central;
  PeripheralManager? _peripheral;
  Peripheral? _host;
  Central? _guest;
  GATTCharacteristic? _rx, _tx;
  SecureChannel? _crypto;
  PairingTicket? ticket;
  final discoveries = <DiscoveredEventArgs>[],
      _subscriptions = <StreamSubscription>[];
  final _assembler = FrameAssembler(), _acks = <String, Completer<bool>>{};
  Future<void> _receiveQueue = Future.value(), _sendQueue = Future.value();
  Completer<bool>? _handshake;
  bool hosting = false,
      scanning = false,
      connected = false,
      busy = false,
      sending = false,
      _disposed = false;
  String status = 'Сеанс не відкрито', peerName = '';
  int _frameId = Random.secure().nextInt(65536), _epoch = 0;
  bool get supported =>
      !kIsWeb &&
      {
        TargetPlatform.android,
        TargetPlatform.iOS,
      }.contains(defaultTargetPlatform);
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _checkEpoch(int epoch) {
    if (_disposed || epoch != _epoch) throw StateError('Сеанс завершено.');
  }

  void _initialize() {
    if (_disposed) throw StateError('Сервіс Bluetooth уже закритий.');
    if (!supported) {
      throw UnsupportedError(
        'Радіозв’язок працює в Android та iPhone. У вебперегляді доступні чернетки.',
      );
    }
    if (_central != null) return;
    _central = CentralManager();
    _peripheral = PeripheralManager();
    for (final manager in <BluetoothLowEnergyManager>[
      _central!,
      _peripheral!,
    ]) {
      _subscriptions.add(
        manager.stateChanged.listen((e) {
          if (e.state != BluetoothLowEnergyState.poweredOn &&
              (hosting || scanning || connected)) {
            _lost();
          }
        }),
      );
    }
    _subscriptions.add(
      _central!.discovered.listen((e) {
        if (!scanning) return;
        final i = discoveries.indexWhere(
          (d) => d.peripheral.uuid == e.peripheral.uuid,
        );
        if (i >= 0) {
          discoveries[i] = e;
        } else if (discoveries.length < 100) {
          discoveries.add(e);
        }
        _changed();
      }),
    );
    _subscriptions.add(
      _central!.connectionStateChanged.listen((e) {
        if (_host?.uuid == e.peripheral.uuid &&
            e.state == ConnectionState.disconnected) {
          _lost();
        }
      }),
    );
    _subscriptions.add(
      _central!.characteristicNotified.listen((e) {
        if (!hosting &&
            _host?.uuid == e.peripheral.uuid &&
            e.characteristic.uuid == txId) {
          _receive(e.value);
        }
      }),
    );
    _subscriptions.add(
      _peripheral!.characteristicWriteRequested.listen((e) async {
        try {
          if (!hosting ||
              e.characteristic.uuid != rxId ||
              _guest?.uuid != e.central.uuid ||
              e.request.offset != 0 ||
              e.request.value.length > 512) {
            await _peripheral!.respondWriteRequestWithError(
              e.request,
              error: GATTError.writeNotPermitted,
            );
            return;
          }
          await _peripheral!.respondWriteRequest(e.request);
          _receive(e.request.value);
        } catch (_) {
          status = 'Помилка приймання Bluetooth';
          _changed();
        }
      }),
    );
    _subscriptions.add(
      _peripheral!.characteristicNotifyStateChanged.listen((e) {
        if (!hosting || e.characteristic.uuid != txId) return;
        if (e.state && (_guest == null || _guest!.uuid == e.central.uuid)) {
          _guest = e.central;
          status = 'Перевіряю код сполучення…';
          _changed();
        } else if (!e.state && _guest?.uuid == e.central.uuid) {
          _guest = null;
          _lost();
        }
      }),
    );
    if (defaultTargetPlatform == TargetPlatform.android) {
      _subscriptions.add(
        _peripheral!.connectionStateChanged.listen((e) {
          if (_guest?.uuid == e.central.uuid &&
              e.state == ConnectionState.disconnected) {
            _guest = null;
            _lost();
          }
        }),
      );
    }
  }

  Future<void> _authorize(BluetoothLowEnergyManager manager) async {
    if (defaultTargetPlatform == TargetPlatform.android &&
        !await manager.authorize()) {
      throw StateError('Надай дозвіл Bluetooth у налаштуваннях застосунку.');
    }
    if (manager.state != BluetoothLowEnergyState.poweredOn) {
      try {
        await manager.stateChanged
            .firstWhere((e) => e.state == BluetoothLowEnergyState.poweredOn)
            .timeout(const Duration(seconds: 20));
      } catch (_) {
        throw StateError('Увімкни Bluetooth і надай дозвіл.');
      }
    }
  }

  Future<void> startHost() async {
    if (busy) return;
    busy = true;
    _changed();
    try {
      _initialize();
      final stopped = stop();
      final epoch = _epoch;
      await stopped;
      _checkEpoch(epoch);
      await _authorize(_peripheral!);
      _checkEpoch(epoch);
      ticket = PairingTicket.create();
      _crypto = await SecureChannel.create(ticket!, host: true);
      _checkEpoch(epoch);
      hosting = true;
      _rx = GATTCharacteristic.mutable(
        uuid: rxId,
        properties: [GATTCharacteristicProperty.write],
        permissions: [GATTCharacteristicPermission.write],
        descriptors: [],
      );
      _tx = GATTCharacteristic.mutable(
        uuid: txId,
        properties: [GATTCharacteristicProperty.notify],
        permissions: [GATTCharacteristicPermission.read],
        descriptors: [],
      );
      await _peripheral!.removeAllServices();
      _checkEpoch(epoch);
      await _peripheral!.addService(
        GATTService(
          uuid: serviceId,
          isPrimary: true,
          includedServices: [],
          characteristics: [_rx!, _tx!],
        ),
      );
      _checkEpoch(epoch);
      await _peripheral!.startAdvertising(
        Advertisement(
          name: defaultTargetPlatform == TargetPlatform.android
              ? null
              : 'AMID-${ticket!.id.substring(0, 5)}',
          serviceUUIDs: [serviceId],
        ),
      );
      _checkEpoch(epoch);
      status = 'Покажи код потрібному співрозмовнику';
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> join(String code) async {
    if (busy) return;
    final parsed = PairingTicket.parse(code);
    busy = true;
    _changed();
    try {
      _initialize();
      final stopped = stop();
      final epoch = _epoch;
      await stopped;
      _checkEpoch(epoch);
      await _authorize(_central!);
      _checkEpoch(epoch);
      ticket = parsed;
      _crypto = await SecureChannel.create(parsed, host: false);
      _checkEpoch(epoch);
      discoveries.clear();
      scanning = true;
      status = 'Шукаю AMID поблизу…';
      await _central!.startDiscovery(serviceUUIDs: [serviceId]);
      _checkEpoch(epoch);
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  Future<void> connect(DiscoveredEventArgs device) async {
    if (busy || !scanning) return;
    busy = true;
    _changed();
    try {
      final epoch = _epoch;
      await _central!.stopDiscovery();
      _checkEpoch(epoch);
      scanning = false;
      _host = device.peripheral;
      peerName = device.advertisement.name ?? 'AMID поблизу';
      status = 'З’єдную телефони…';
      _changed();
      await _central!.connect(_host!).timeout(const Duration(seconds: 25));
      _checkEpoch(epoch);
      if (defaultTargetPlatform == TargetPlatform.android) {
        try {
          await _central!.requestMTU(_host!, mtu: 185);
        } catch (_) {}
      }
      _checkEpoch(epoch);
      final services = await _central!.discoverGATT(_host!),
          service = services.firstWhere((s) => s.uuid == serviceId);
      _checkEpoch(epoch);
      _rx = service.characteristics.firstWhere((c) => c.uuid == rxId);
      _tx = service.characteristics.firstWhere((c) => c.uuid == txId);
      await _central!.setCharacteristicNotifyState(_host!, _tx!, state: true);
      _checkEpoch(epoch);
      status = 'Перевіряю код сеансу…';
      _handshake = Completer<bool>();
      final confirmed = _handshake!.future.timeout(
        const Duration(seconds: 25),
        onTimeout: () => false,
      );
      await _send({'type': 'hello', 'session': ticket!.id});
      if (!await confirmed) {
        throw StateError(
          'Код сеансу не підтверджено. Створи новий сеанс і відскануй його код.',
        );
      }
    } catch (_) {
      await stop();
      rethrow;
    } finally {
      busy = false;
      _changed();
    }
  }

  void _receive(Uint8List frame) {
    final epoch = _epoch;
    _receiveQueue = _receiveQueue
        .then((_) async {
          if (epoch != _epoch || _crypto == null) return;
          final packet = _assembler.accept(frame);
          if (packet == null) return;
          final v = await _crypto!.open(packet);
          if (epoch != _epoch) return;
          if (v['type'] == 'hello' && hosting && v['session'] == ticket?.id) {
            connected = true;
            peerName = 'Сполучений телефон';
            status = 'Телефони з’єднані';
            _changed();
            await _send({'type': 'hello_ack', 'session': ticket!.id});
          } else if (v['type'] == 'hello_ack' &&
              !hosting &&
              v['session'] == ticket?.id) {
            connected = true;
            status = 'Телефони з’єднані';
            if (_handshake != null && !_handshake!.isCompleted) {
              _handshake!.complete(true);
            }
            _changed();
          } else if (connected &&
              v['type'] == 'message' &&
              v['message'] is Map) {
            final message = Message.parse(Json.from(v['message'] as Map));
            await store.saveMessage(message);
            await _send({'type': 'ack', 'id': message.id});
          } else if (connected &&
              v['type'] == 'ack' &&
              v['id'] is String &&
              _acks.containsKey(v['id'])) {
            await store.messageStatus(v['id'] as String, 'delivered');
            final ack = _acks.remove(v['id']);
            if (ack != null && !ack.isCompleted) ack.complete(true);
          }
        })
        .catchError((Object _) {
          if (epoch == _epoch) {
            status =
                'Пакет не прийнято. Перевір код сполучення або повтори сеанс.';
            _changed();
          }
        });
  }

  Future<void> _send(Json value) {
    final epoch = _epoch;
    final operation = _sendQueue.then((_) async {
      if (_crypto == null || epoch != _epoch) {
        throw StateError('Сеанс завершено.');
      }
      final packet = await _crypto!.seal(value);
      _checkEpoch(epoch);
      final maximum = hosting
          ? await _peripheral!.getMaximumNotifyLength(_guest!)
          : await _central!.getMaximumWriteLength(
              _host!,
              type: GATTCharacteristicWriteType.withResponse,
            );
      _checkEpoch(epoch);
      final mtu = min(180, maximum);
      if (mtu < 20) {
        throw StateError('Непідтримуваний розмір Bluetooth-пакета.');
      }
      for (final frame in fragmentPacket(
        packet,
        mtu: mtu,
        id: _frameId++ % 65536,
      )) {
        if (epoch != _epoch) throw StateError('Сеанс завершено.');
        if (hosting) {
          await _peripheral!.notifyCharacteristic(_guest!, _tx!, value: frame);
          await Future<void>.delayed(const Duration(milliseconds: 8));
        } else {
          await _central!.writeCharacteristic(
            _host!,
            _rx!,
            value: frame,
            type: GATTCharacteristicWriteType.withResponse,
          );
        }
      }
    });
    _sendQueue = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> send(Message message) async {
    if (!connected || sending) throw StateError('Спочатку з’єднай телефони.');
    sending = true;
    _changed();
    final ack = Completer<bool>();
    _acks[message.id] = ack;
    final confirmed = ack.future.timeout(
      const Duration(seconds: 90),
      onTimeout: () => false,
    );
    try {
      await _send({'type': 'message', 'message': message.toWire()});
      await store.messageStatus(message.id, 'transferred');
      if (!await confirmed) {
        throw StateError(
          'Отримання не підтверджено. Повідомлення збережене на цьому пристрої.',
        );
      }
    } finally {
      _acks.remove(message.id);
      if (!ack.isCompleted) ack.complete(false);
      sending = false;
      _changed();
    }
  }

  void _lost() {
    if (_disposed) return;
    // A disconnected peer must not leave a reusable pairing ticket or crypto state.
    final stopped = stop();
    final epoch = _epoch;
    unawaited(
      stopped.then((_) {
        if (!_disposed && epoch == _epoch) {
          status = 'З’єднання перервано. Створи новий сеанс.';
          _changed();
        }
      }),
    );
  }

  Future<void> stop() async {
    _epoch++;
    final wasHosting = hosting, wasScanning = scanning, host = _host;
    connected = false;
    hosting = false;
    scanning = false;
    ticket = null;
    _crypto = null;
    _host = null;
    _guest = null;
    _rx = null;
    _tx = null;
    _assembler.clear();
    if (_handshake != null && !_handshake!.isCompleted) {
      _handshake!.complete(false);
    }
    _handshake = null;
    for (final a in _acks.values) {
      if (!a.isCompleted) a.complete(false);
    }
    _acks.clear();
    if (wasScanning) {
      try {
        await _central?.stopDiscovery();
      } catch (_) {}
    }
    if (host != null) {
      try {
        await _central?.disconnect(host);
      } catch (_) {}
    }
    if (wasHosting) {
      try {
        await _peripheral?.stopAdvertising();
        await _peripheral?.removeAllServices();
      } catch (_) {}
    }
    discoveries.clear();
    status = 'Сеанс не відкрито';
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    super.dispose();
  }
}
