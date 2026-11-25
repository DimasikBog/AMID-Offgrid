import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:amid_offgrid/models/mesh_wire.dart';
import 'package:amid_offgrid/services/radio_transport.dart';

import 'mesh_vectors.dart';

Uint8List meshEnvelope(int tag, Uint8List data) =>
    (MeshWriter()..bytes(tag, data)).take();
Uint8List meshUint(int tag, int value) =>
    (MeshWriter()..uint(tag, value)).take();

class FixtureRadio extends RadioTransport {
  final controller = StreamController<Uint8List>.broadcast(sync: true);
  final writes = <Uint8List>[];
  bool autoConfigure = true, writeFails = false;
  Completer<void>? pendingWrite, pendingScan;
  @override
  bool get supported => true;
  @override
  bool connected = false;
  @override
  bool scanning = false;
  @override
  String status = 'Тестовий транспорт';
  @override
  List<RadioDevice> devices = [];
  @override
  Stream<Uint8List> get packets => controller.stream;
  void emit(Uint8List bytes) => controller.add(bytes);
  @override
  Future<void> scan() async {
    scanning = true;
    devices = [const RadioDevice('one', 'AMID Dock', -51)];
    notifyListeners();
    if (pendingScan != null) await pendingScan!.future;
  }

  @override
  Future<void> connect(String id) async {
    connected = true;
    scanning = false;
    notifyListeners();
  }

  @override
  Future<void> write(Uint8List packet) async {
    if (writeFails) throw StateError('BLE write failed');
    writes.add(packet);
    final fields = MeshFields(packet);
    if (fields.has(3) && autoConfigure) {
      for (final name in [
        'my_info',
        'metadata',
        'lora',
        'channel_test_key_only',
        'node',
      ]) {
        emit(meshVector(name));
      }
      emit(meshUint(7, fields.uint(3)));
    } else if (pendingWrite != null) {
      await pendingWrite!.future;
    }
  }

  int get lastId => MeshFields(writes.last).nested(1).fixed(6);
  void queued(int id, {int error = 0}) => emit(
    meshEnvelope(
      11,
      (MeshWriter()
            ..uint(1, error)
            ..uint(4, id))
          .take(),
    ),
  );
  void ack(
    int id, {
    int from = 0x1234abcd,
    int to = 0x11223344,
    int channel = 1,
    int error = 0,
    bool viaMqtt = false,
  }) {
    final routing = meshUint(3, error);
    final data =
        (MeshWriter()
              ..uint(1, 5)
              ..bytes(2, routing)
              ..fixed(6, id))
            .take();
    emit(
      meshEnvelope(
        2,
        (MeshWriter()
              ..fixed(1, from)
              ..fixed(2, to)
              ..uint(3, channel)
              ..bytes(4, data)
              ..fixed(6, 900)
              ..uint(12, (-75) & 0xffffffff)
              ..uint(14, viaMqtt ? 1 : 0))
            .take(),
      ),
    );
  }

  void text(String value, {int id = 777, bool viaMqtt = false}) {
    final data =
        (MeshWriter()
              ..uint(1, 1)
              ..bytes(2, utf8.encode(value)))
            .take();
    emit(
      meshEnvelope(
        2,
        (MeshWriter()
              ..fixed(1, 0x1234abcd)
              ..fixed(2, 0x11223344)
              ..uint(3, 1)
              ..bytes(4, data)
              ..fixed(6, id)
              ..uint(12, (-82) & 0xffffffff)
              ..uint(14, viaMqtt ? 1 : 0))
            .take(),
      ),
    );
  }

  @override
  Future<void> stop() async {
    connected = false;
    scanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(controller.close());
    super.dispose();
  }
}
