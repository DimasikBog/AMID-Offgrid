import 'dart:typed_data';

const frameHeaderLength = 8, maxRadioPacket = 32768;
List<Uint8List> fragmentPacket(
  Uint8List data, {
  required int mtu,
  required int id,
}) {
  if (data.isEmpty ||
      data.length > maxRadioPacket ||
      mtu < 20 ||
      mtu > 512 ||
      id < 0 ||
      id > 65535) {
    throw const FormatException('Некоректний радіопакет.');
  }
  final payload = mtu - 8, count = (data.length / (mtu - 8)).ceil();
  return List.generate(count, (i) {
    final start = i * payload,
        end = (start + payload).clamp(0, data.length),
        frame = Uint8List(8 + end - start),
        h = ByteData(8);
    h.setUint8(0, 0xad);
    h.setUint8(1, 1);
    h.setUint16(2, id);
    h.setUint16(4, i);
    h.setUint16(6, count);
    frame.setRange(0, 8, h.buffer.asUint8List());
    frame.setRange(8, frame.length, data, start);
    return frame;
  });
}

class _Parts {
  _Parts(this.count, this.time);
  final int count;
  final DateTime time;
  final parts = <int, Uint8List>{};
  int bytes = 0;
}

class FrameAssembler {
  final _pending = <int, _Parts>{};
  void clear() => _pending.clear();
  Uint8List? accept(Uint8List frame, {DateTime? now}) {
    final time = now ?? DateTime.now();
    _pending.removeWhere(
      (_, p) => time.difference(p.time) > const Duration(seconds: 45),
    );
    if (frame.length <= 8 || frame.length > 512) {
      throw const FormatException('Некоректний фрагмент.');
    }
    final h = ByteData.sublistView(frame),
        id = h.getUint16(2),
        index = h.getUint16(4),
        count = h.getUint16(6);
    if (h.getUint8(0) != 0xad ||
        h.getUint8(1) != 1 ||
        count < 1 ||
        count > 4096 ||
        index >= count) {
      throw const FormatException('Невідомий фрагмент.');
    }
    if (!_pending.containsKey(id) && _pending.length >= 4) {
      throw const FormatException('Забагато незавершених пакетів.');
    }
    final parts = _pending.putIfAbsent(id, () => _Parts(count, time));
    if (parts.count != count) {
      _pending.remove(id);
      throw const FormatException('Змінився розмір пакета.');
    }
    final data = Uint8List.sublistView(frame, 8), previous = parts.parts[index];
    if (previous != null) {
      if (previous.length != data.length ||
          List.generate(
            data.length,
            (i) => i,
          ).any((i) => previous[i] != data[i])) {
        _pending.remove(id);
        throw const FormatException('Суперечливі копії фрагмента.');
      }
      return null;
    }
    parts.parts[index] = Uint8List.fromList(data);
    parts.bytes += data.length;
    if (parts.bytes > maxRadioPacket) {
      _pending.remove(id);
      throw const FormatException('Завеликий пакет.');
    }
    if (parts.parts.length != count) return null;
    final out = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      out.add(parts.parts[i]!);
    }
    _pending.remove(id);
    return out.takeBytes();
  }
}
