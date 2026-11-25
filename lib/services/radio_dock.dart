import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import '../models/mesh_wire.dart';
import '../models/radio_field_test.dart';
import '../version.dart';
import 'radio_transport.dart';
import 'store.dart';

enum RadioDelivery {
  bluetooth('Передаю модулю'),
  queued('Прийнято чергою радіо'),
  acknowledged('ACK адресата · не підтверджує прочитання'),
  failed('Передавання відхилено'),
  unconfirmed('Немає ACK адресата'),
  interrupted('Сеанс перервано');

  const RadioDelivery(this.label);
  final String label;
}

class RadioTransmission {
  RadioTransmission(this.id, this.messageId, this.text, this.to, this.channel);
  final int id, to, channel;
  final String messageId, text;
  RadioDelivery state = RadioDelivery.bluetooth;
  Timer? timer;
}

class RadioDockService extends ChangeNotifier {
  RadioDockService(
    this.store,
    this.transport, {
    this.ackTimeout = const Duration(seconds: 90),
  }) {
    transport.addListener(_transportChanged);
    _subscription = transport.packets.listen(
      _received,
      onError: (Object _) => unawaited(stop()),
    );
  }
  final AppStore store;
  final RadioTransport transport;
  final Duration ackTimeout;
  late final StreamSubscription<Uint8List> _subscription;
  final nodes = <int, MeshNode>{}, channels = <int, MeshChannel>{};
  final transmissions = <RadioTransmission>[];
  final _pending = <int, RadioTransmission>{};
  final _seen = <String>{};
  Future<void> _receiveQueue = Future.value();
  Completer<bool>? _hello;
  int _epoch = 0, _nonce = 0, _queued = 0;
  bool _disposed = false, _linkUp = false;
  bool ready = false, busy = false, sending = false, txEnabled = false;
  bool overrides = false;
  int localNode = 0, region = 0, selectedChannel = 0;
  String firmware = '', status = 'Радіомодуль не підключено';
  DateTime? _lastSend;
  int? lastRadioRssi;
  double? lastRadioSnr;
  RadioFieldSession? fieldTest;
  RadioFieldReport? lastFieldReport;
  Timer? _fieldTimer;
  Future<void> _fieldSave = Future.value();
  bool fieldSaving = false;
  String? fieldSaveError;
  bool get fieldReportSaved =>
      lastFieldReport != null &&
      store.radioReports.any((r) => r.id == lastFieldReport!.id);

  void startFieldTest() {
    if (!ready || fieldTest != null || fieldSaving || fieldSaveError != null) {
      throw StateError('Підключи радіомодуль і заверши попередній тест.');
    }
    if (region < 0 || region > 255) {
      throw const FormatException(
        'Невідомий регіон. Спочатку перевір налаштування радіо.',
      );
    }
    final watch = Stopwatch()..start();
    fieldTest = RadioFieldSession(
      id: const Uuid().v4(),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      appVersion: appVersion,
      firmware: firmware,
      region: region,
      elapsedMs: () => watch.elapsedMilliseconds,
    );
    lastFieldReport = null;
    fieldSaveError = null;
    _fieldTimer = Timer(
      const Duration(milliseconds: radioFieldMaxMs),
      () => _finishFieldTest('timeLimit'),
    );
    _changed();
  }

  void _finishFieldTest(String reason) {
    final test = fieldTest;
    if (test == null) return;
    fieldTest = null;
    _fieldTimer?.cancel();
    lastFieldReport = test.finish(reason);
    unawaited(saveFieldReport());
    _changed();
  }

  Future<void> finishFieldTest() async {
    _finishFieldTest('manual');
    await _fieldSave;
  }

  Future<void> saveFieldReport() {
    final report = lastFieldReport;
    if (report == null || fieldSaving) return _fieldSave;
    fieldSaving = true;
    fieldSaveError = null;
    _fieldSave = store
        .saveRadioReport(report)
        .catchError((Object _) {
          fieldSaveError = 'Не вдалося зберегти звіт. Повтори збереження.';
        })
        .whenComplete(() {
          fieldSaving = false;
          _changed();
        });
    _changed();
    return _fieldSave;
  }

  bool get supported => transport.supported;
  bool get canSend =>
      ready &&
      !sending &&
      region == 3 &&
      txEnabled &&
      !overrides &&
      firmware.startsWith('2.7.') &&
      (channels[selectedChannel]?.hasFullKey ?? false) &&
      !(channels[selectedChannel]?.uplink ?? true);
  MeshNode? get ownNode => nodes[localNode];
  Future<void> flushIncoming() => _receiveQueue;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _check(int epoch) {
    if (_disposed || _epoch != epoch) {
      throw StateError('Сеанс радіо завершено.');
    }
  }

  void _transportChanged() {
    if (transport.connected) _linkUp = true;
    if (!transport.connected && _linkUp) {
      _invalidate();
      status = transport.status;
    }
    _changed();
  }

  Future<void> scan() async {
    if (busy) return;
    _invalidate();
    final epoch = _epoch;
    busy = true;
    _changed();
    try {
      await transport.stop();
      _check(epoch);
      await transport.scan();
      _check(epoch);
      status = transport.status;
    } finally {
      if (epoch == _epoch) {
        busy = false;
        _changed();
      }
    }
  }

  Future<void> connect(String id) async {
    if (busy) return;
    _invalidate();
    final epoch = _epoch;
    busy = true;
    status = 'Підключаю та перевіряю конфігурацію…';
    _changed();
    _nonce = Random.secure().nextInt(0x7fffffff) + 1;
    final hello = _hello = Completer<bool>();
    try {
      await transport.connect(id);
      _check(epoch);
      await transport.write(meshConfigRequest(_nonce));
      _check(epoch);
      if (!await hello.future.timeout(
        const Duration(seconds: 45),
        onTimeout: () => false,
      )) {
        throw StateError(
          'Модуль не підтвердив конфігурацію. Перевір PIN і прошивку.',
        );
      }
      _check(epoch);
      ready = true;
      status = 'Модуль готовий. Інтернет-шлюз не підключено.';
    } catch (_) {
      if (_epoch == epoch) await stop();
      rethrow;
    } finally {
      if (_epoch == epoch) {
        busy = false;
        _changed();
      }
    }
  }

  void chooseChannel(int index) {
    if (!channels.containsKey(index)) {
      throw const FormatException('Невідомий канал.');
    }
    if (index != selectedChannel) _finishFieldTest('configurationChanged');
    selectedChannel = index;
    _changed();
  }

  void _received(Uint8List bytes) {
    if (_disposed) return;
    if (_queued >= 32) {
      unawaited(stop());
      return;
    }
    final epoch = _epoch;
    _queued++;
    _receiveQueue = _receiveQueue
        .then((_) async {
          if (_disposed || epoch != _epoch) return;
          await _apply(MeshEvent(bytes), epoch);
        })
        .catchError((Object _) {
          if (!_disposed && epoch == _epoch) {
            fieldTest?.processingError();
            status = 'Пошкоджений пакет відкинуто.';
            _changed();
          }
        })
        .whenComplete(() => _queued--);
  }

  Future<void> _apply(MeshEvent event, int epoch) async {
    if (event.rebooted) {
      await stop();
      return;
    }
    if (ready &&
        (event.lora != null || event.variant == 10 || event.firmware != null)) {
      _finishFieldTest('configurationChanged');
    }
    if (event.myNode != null) localNode = event.myNode!;
    if (event.firmware != null) firmware = boundedText(event.firmware!, 80);
    final lora = event.lora;
    if (lora != null) {
      region = lora.region;
      txEnabled = lora.txEnabled;
      overrides = lora.overrides;
    }
    if (event.variant == 10) {
      final index = event.fields.nested(10).uint(1);
      channels.remove(index);
      final channel = event.channel;
      if (channel != null) channels[channel.index] = channel;
    }
    final node = event.node;
    if (node != null &&
        node.number > 3 &&
        node.number != meshBroadcast &&
        (nodes.containsKey(node.number) || nodes.length < 128)) {
      nodes[node.number] = node;
    }
    if (event.configId == _nonce &&
        localNode > 3 &&
        localNode != meshBroadcast &&
        _hello != null &&
        !_hello!.isCompleted) {
      _hello!.complete(true);
    }
    final queue = event.queue;
    if (queue != null) {
      final receipt = _pending[queue.id];
      if (receipt != null) {
        receipt.state = queue.result == 0
            ? RadioDelivery.queued
            : RadioDelivery.failed;
        fieldTest?.outcome(receipt.id, receipt.state.name);
        if (queue.result == 0) {
          await store.messageStatus(
            receipt.messageId,
            'transferred',
            checkActive: () => _check(epoch),
          );
        } else {
          receipt.timer?.cancel();
          _pending.remove(queue.id);
        }
        _check(epoch);
      }
    }
    final packet = event.packet;
    if (packet != null) await _packet(packet, epoch);
    _changed();
  }

  Future<void> _packet(MeshPacket packet, int epoch) async {
    if (packet.to != localNode && packet.to != meshBroadcast) return;
    if (!packet.viaMqtt) {
      lastRadioRssi = packet.rssi;
      lastRadioSnr = packet.snr;
    }
    final receipt = _pending[packet.requestId];
    if (packet.port == 5 &&
        !packet.viaMqtt &&
        receipt != null &&
        receipt.to != meshBroadcast &&
        packet.from == receipt.to &&
        packet.to == localNode &&
        packet.channel == receipt.channel) {
      receipt.state = packet.routingError == 0
          ? RadioDelivery.acknowledged
          : RadioDelivery.failed;
      if (fieldTest?.outcome(receipt.id, receipt.state.name) ?? false) {
        fieldTest?.signal(rssi: packet.rssi, snr: packet.snr);
      }
      receipt.timer?.cancel();
      _pending.remove(receipt.id);
      if (receipt.state == RadioDelivery.acknowledged) {
        await store.messageStatus(
          receipt.messageId,
          'delivered',
          checkActive: () => _check(epoch),
        );
      }
      _check(epoch);
    }
    if (!ready ||
        packet.from == localNode ||
        packet.from <= 3 ||
        packet.id == 0 ||
        packet.channel != selectedChannel) {
      return;
    }
    final text = packet.text;
    if (text == null || text.trim().isEmpty) return;
    final id = 'mesh-${meshNodeId(packet.from)}-${packet.id.toRadixString(16)}';
    if (_seen.contains(id)) return;
    if (!store.messages.any((m) => m.id == id)) {
      await store.saveMessage(
        Message(
          id,
          text,
          DateTime.now().toUtc().toIso8601String(),
          'in',
          'received',
        ),
        checkActive: () => _check(epoch),
      );
      _check(epoch);
    }
    _seen.add(id);
    if (!packet.viaMqtt) {
      fieldTest?.received();
      fieldTest?.signal(rssi: packet.rssi, snr: packet.snr);
    }
    if (_seen.length > 1000) _seen.remove(_seen.first);
    status =
        'Отримано LoRa-текст від ${meshNodeId(packet.from)}. Авторство визначає радіопротокол.';
  }

  Future<void> sendText(String text, {required int to}) async {
    if (!canSend) {
      throw StateError(
        'Потрібні Meshtastic 2.7, EU868, увімкнений TX і канал із власним 32-байтовим ключем без MQTT uplink.',
      );
    }
    if (_lastSend != null &&
        DateTime.now().difference(_lastSend!) < const Duration(seconds: 10)) {
      throw StateError('Зачекай 10 секунд між повідомленнями.');
    }
    if (_pending.length >= 20) {
      throw StateError('Зачекай завершення попередніх передавань.');
    }
    final epoch = _epoch;
    var id = Random.secure().nextInt(0x7fffffff) + 1;
    while (_pending.containsKey(id)) {
      id = Random.secure().nextInt(0x7fffffff) + 1;
    }
    final bytes = meshTextRequest(
      text: text,
      id: id,
      to: to,
      channel: selectedChannel,
    );
    if (to == localNode) {
      throw const FormatException('Вибери інший радіовузол.');
    }
    final receipt = RadioTransmission(
      id,
      'radio-${const Uuid().v4()}',
      text,
      to,
      selectedChannel,
    );
    sending = true;
    _changed();
    try {
      await store.saveMessage(
        Message(
          receipt.messageId,
          text,
          DateTime.now().toUtc().toIso8601String(),
          'out',
          'draft',
        ),
        checkActive: () => _check(epoch),
      );
      _check(epoch);
      _pending[id] = receipt;
      if (fieldTest?.full ?? false) _finishFieldTest('capacity');
      fieldTest?.attempt(id, broadcast: to == meshBroadcast);
      transmissions.insert(0, receipt);
      if (transmissions.length > 30) transmissions.removeLast();
      await transport.write(bytes);
      _check(epoch);
      _lastSend = DateTime.now();
      if (_pending.containsKey(id)) {
        receipt.timer = Timer(ackTimeout, () {
          if (_epoch == epoch && _pending.remove(id) != null) {
            receipt.state = RadioDelivery.unconfirmed;
            fieldTest?.outcome(receipt.id, receipt.state.name);
            _changed();
          }
        });
      }
      status =
          'BLE-запис прийнято. Очікую стан черги радіо; це ще не доставка.';
    } catch (_) {
      receipt.timer?.cancel();
      _pending.remove(id);
      receipt.state = RadioDelivery.failed;
      fieldTest?.outcome(receipt.id, receipt.state.name);
      rethrow;
    } finally {
      if (_epoch == epoch) {
        sending = false;
        _changed();
      }
    }
  }

  void _invalidate() {
    _finishFieldTest('disconnected');
    _epoch++;
    ready = false;
    busy = false;
    sending = false;
    final hello = _hello;
    _hello = null;
    if (hello != null && !hello.isCompleted) hello.complete(false);
    for (final receipt in _pending.values) {
      receipt.timer?.cancel();
      receipt.state = RadioDelivery.interrupted;
    }
    _pending.clear();
    nodes.clear();
    channels.clear();
    _seen.clear();
    localNode = 0;
    _linkUp = false;
    selectedChannel = 0;
    region = 0;
    txEnabled = false;
    overrides = false;
    firmware = '';
    lastRadioRssi = null;
    lastRadioSnr = null;
  }

  Future<void> stop() async {
    _invalidate();
    status = 'Радіомодуль не підключено';
    _changed();
    await transport.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidate();
    transport.removeListener(_transportChanged);
    unawaited(_subscription.cancel());
    transport.dispose();
    super.dispose();
  }
}
