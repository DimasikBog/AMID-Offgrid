import 'dart:convert';
import 'dart:typed_data';

// Independent, bounded subset of the public Meshtastic protobuf wire API.
// Schema: protobufs@6b1ded439633cd03d4af85b44231b91d1d106278 (firmware 2.7.26).
// No generated firmware code or channel secrets are stored in AMID.
const meshServiceUuid = '6ba1b218-15a8-461f-9fa8-5dcae273eafd';
const meshToRadioUuid = 'f75c76d2-129e-4dad-a1dd-7866124401e7';
const meshFromRadioUuid = '2c55e69e-4993-11ed-b878-0242ac120002';
const meshFromNumUuid = 'ed9da18c-a800-4f66-a670-aa7547e34453';
const meshBroadcast = 0xffffffff;
const meshTextLimit = 200;

String meshNodeId(int value) => '!${value.toRadixString(16).padLeft(8, '0')}';

int checkedMeshDestination(String value) {
  if (!RegExp(r'^![0-9a-fA-F]{8}$').hasMatch(value)) {
    throw const FormatException('Адресат має вигляд !1234abcd.');
  }
  final number = int.parse(value.substring(1), radix: 16);
  if (number <= 3 || number == meshBroadcast) {
    throw const FormatException('Вкажи адресу конкретного радіовузла.');
  }
  return number;
}

Uint8List meshConfigRequest(int nonce) => (MeshWriter()..uint(3, nonce)).take();

Uint8List meshTextRequest({
  required String text,
  required int id,
  required int to,
  required int channel,
  int hops = 3,
}) {
  final payload = utf8.encode(text);
  if (text.trim().isEmpty ||
      payload.length > meshTextLimit ||
      id <= 0 ||
      id > meshBroadcast ||
      to <= 3 ||
      to > meshBroadcast ||
      channel < 0 ||
      channel > 7 ||
      hops < 0 ||
      hops > 3) {
    throw const FormatException(
      'До 200 байтів UTF-8, канал 0–7, не більше 3 переходів.',
    );
  }
  final data =
      (MeshWriter()
            ..uint(1, 1)
            ..bytes(2, payload))
          .take();
  final packet =
      (MeshWriter()
            ..fixed(2, to)
            ..uint(3, channel)
            ..bytes(4, data)
            ..fixed(6, id)
            ..uint(9, hops)
            ..uint(10, to == meshBroadcast ? 0 : 1))
          .take();
  return (MeshWriter()..bytes(1, packet)).take();
}

class MeshWriter {
  final _out = BytesBuilder(copy: false);
  void _varint(int value) {
    if (value < 0 || value > meshBroadcast) {
      throw const FormatException('uint32');
    }
    do {
      _out.addByte((value & 127) | (value > 127 ? 128 : 0));
      value ~/= 128;
    } while (value != 0);
  }

  void uint(int tag, int value) {
    _varint(tag * 8);
    _varint(value);
  }

  void fixed(int tag, int value) {
    _varint(tag * 8 + 5);
    final b = ByteData(4)..setUint32(0, value, Endian.little);
    _out.add(b.buffer.asUint8List());
  }

  void bytes(int tag, List<int> value) {
    if (value.length > 512) throw const FormatException('Завеликий пакет.');
    _varint(tag * 8 + 2);
    _varint(value.length);
    _out.add(value);
  }

  Uint8List take() {
    final bytes = _out.takeBytes();
    if (bytes.length > 512) throw const FormatException('Завеликий пакет.');
    return bytes;
  }
}

class _Field {
  _Field(this.wire, this.number, this.data);
  final int wire;
  final BigInt? number;
  final Uint8List? data;
}

class MeshFields {
  MeshFields(Uint8List bytes) {
    if (bytes.length > 512) throw const FormatException('Завеликий protobuf.');
    var offset = 0, count = 0;
    BigInt varint() {
      var value = BigInt.zero;
      for (var i = 0; i < 10; i++) {
        if (offset >= bytes.length) {
          throw const FormatException('Обрізаний protobuf.');
        }
        final byte = bytes[offset++];
        if (i == 9 && byte > 1) {
          throw const FormatException('Переповнення protobuf.');
        }
        value |= BigInt.from(byte & 127) << (7 * i);
        if (byte < 128) return value;
      }
      throw const FormatException('Неправильний varint.');
    }

    Uint8List read(int size) {
      if (size < 0 || size > bytes.length - offset) {
        throw const FormatException('Обрізаний protobuf.');
      }
      final value = Uint8List.sublistView(bytes, offset, offset + size);
      offset += size;
      return value;
    }

    while (offset < bytes.length) {
      if (++count > 160) {
        throw const FormatException('Забагато полів protobuf.');
      }
      final rawTag = varint();
      if (rawTag > BigInt.from(meshBroadcast)) {
        throw const FormatException('Тег protobuf.');
      }
      final tag = rawTag.toInt(), wire = tag & 7, number = tag >> 3;
      if (number == 0) throw const FormatException('Нульовий тег protobuf.');
      BigInt? value;
      Uint8List? data;
      switch (wire) {
        case 0:
          value = varint();
        case 1:
          data = read(8);
        case 2:
          final length = varint();
          if (length > BigInt.from(512)) {
            throw const FormatException('Довжина protobuf.');
          }
          data = read(length.toInt());
        case 5:
          data = read(4);
        default:
          throw const FormatException('Непідтримуваний тип protobuf.');
      }
      _fields[number] = _Field(wire, value, data);
      _order.remove(number);
      _order.add(number);
    }
  }
  final _fields = <int, _Field>{};
  final _order = <int>[];
  int? lastOf(Set<int> tags) => _order.where(tags.contains).lastOrNull;
  bool has(int tag) => _fields.containsKey(tag);
  int uint(int tag, [int fallback = 0]) {
    final f = _fields[tag];
    if (f == null) return fallback;
    if (f.wire != 0 || f.number! > BigInt.from(meshBroadcast)) {
      throw const FormatException('Очікується uint32.');
    }
    return f.number!.toInt();
  }

  int signed32(int tag, [int fallback = 0]) {
    final f = _fields[tag];
    if (f == null) return fallback;
    if (f.wire != 0) throw const FormatException('Очікується int32.');
    final value = f.number!;
    if (value > BigInt.from(meshBroadcast) &&
        value >> 32 != BigInt.from(meshBroadcast)) {
      throw const FormatException('Переповнення int32.');
    }
    return (value & BigInt.from(meshBroadcast)).toInt().toSigned(32);
  }

  Uint8List bytes(int tag) {
    final f = _fields[tag];
    if (f == null) return Uint8List(0);
    if (f.wire != 2) throw const FormatException('Очікуються bytes.');
    return f.data!;
  }

  int fixed(int tag, [int fallback = 0]) {
    final f = _fields[tag];
    if (f == null) return fallback;
    if (f.wire != 5) throw const FormatException('Очікується fixed32.');
    return ByteData.sublistView(f.data!).getUint32(0, Endian.little);
  }

  double? float(int tag) {
    if (!has(tag)) return null;
    final f = _fields[tag]!;
    if (f.wire != 5) throw const FormatException('Очікується float.');
    final value = ByteData.sublistView(f.data!).getFloat32(0, Endian.little);
    return value.isFinite ? value : null;
  }

  String text(int tag) => utf8.decode(bytes(tag));
  MeshFields nested(int tag) => MeshFields(bytes(tag));
}

class MeshChannel {
  const MeshChannel(this.index, this.name, this.hasFullKey, this.uplink);
  final int index;
  final String name;
  final bool hasFullKey, uplink;
}

class MeshNode {
  const MeshNode(
    this.number,
    this.name, {
    this.battery,
    this.latitude,
    this.longitude,
    this.viaMqtt = false,
  });
  final int number;
  final String name;
  final int? battery;
  final double? latitude, longitude;
  final bool viaMqtt;
}

class MeshPacket {
  MeshPacket(MeshFields p)
    : from = p.fixed(1),
      to = p.fixed(2),
      id = p.fixed(6),
      channel = p.uint(3),
      snr = p.float(8),
      rssi = p.has(12) ? p.signed32(12) : null,
      viaMqtt = p.uint(14) != 0,
      data = p.lastOf({4, 5}) == 4 ? p.nested(4) : null;
  final int from, to, id, channel;
  final double? snr;
  final int? rssi;
  final bool viaMqtt;
  final MeshFields? data;
  int get port => data?.uint(1) ?? 0;
  int get requestId => data?.fixed(6) ?? 0;
  String? get text =>
      port == 1 && data!.bytes(2).length <= 237 ? data!.text(2) : null;
  int? get routingError => port == 5 ? data!.nested(2).uint(3) : null;
}

class MeshEvent {
  MeshEvent(Uint8List bytes) : fields = MeshFields(bytes);
  final MeshFields fields;
  int? get variant => fields.lastOf({
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
  });
  int? get configId => variant == 7 ? fields.uint(7) : null;
  int? get myNode => variant == 3 ? fields.nested(3).uint(1) : null;
  bool get rebooted => variant == 8 && fields.uint(8) != 0;
  String? get firmware => variant == 13 ? fields.nested(13).text(1) : null;
  MeshPacket? get packet => variant == 2 ? MeshPacket(fields.nested(2)) : null;
  ({int id, int result})? get queue {
    if (variant != 11) return null;
    final q = fields.nested(11);
    return (id: q.uint(4), result: q.signed32(1));
  }

  ({int region, bool txEnabled, bool overrides})? get lora {
    if (variant != 5) return null;
    final config = fields.nested(5);
    if (config.lastOf({1, 2, 3, 4, 5, 6, 7, 8, 9, 10}) != 6) return null;
    final l = config.nested(6);
    return (
      region: l.uint(7),
      txEnabled: l.uint(9) != 0,
      overrides: l.uint(12) != 0 || (l.has(14) && l.float(14) != 0),
    );
  }

  MeshChannel? get channel {
    if (variant != 10) return null;
    final c = fields.nested(10), index = c.uint(1);
    if (index > 7 || c.uint(3) == 0) return null;
    final s = c.nested(2), key = s.bytes(2);
    return MeshChannel(
      index,
      s.text(3),
      key.length == 32 && key.toSet().length > 1,
      s.uint(5) != 0,
    );
  }

  MeshNode? get node {
    if (variant != 4) return null;
    final n = fields.nested(4), position = n.nested(3), user = n.nested(2);
    double? lat, lon;
    if (position.has(1) && position.has(2)) {
      final a = position.fixed(1).toSigned(32) * 1e-7;
      final b = position.fixed(2).toSigned(32) * 1e-7;
      if (a.abs() <= 90 && b.abs() <= 180) {
        lat = a;
        lon = b;
      }
    }
    return MeshNode(
      n.uint(1),
      user.text(2),
      battery: n.has(6) && n.nested(6).has(1) ? n.nested(6).uint(1) : null,
      latitude: lat,
      longitude: lon,
      viaMqtt: n.uint(8) != 0,
    );
  }
}
