import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../models/raster_limits.dart';

String rasterEncoding(Uint8List bytes) {
  bool starts(List<int> signature, [int offset = 0]) {
    if (bytes.length < offset + signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[offset + i] != signature[i]) return false;
    }
    return true;
  }

  if (starts([137, 80, 78, 71, 13, 10, 26, 10])) return 'png';
  if (starts([255, 216, 255])) return 'jpg';
  if (starts([82, 73, 70, 70]) && starts([87, 69, 66, 80], 8)) return 'webp';
  throw const FormatException('Тайл не є PNG, JPEG або WebP.');
}

/// The caller owns the returned buffer until passing it to a Flutter decoder.
Future<ui.ImmutableBuffer> checkedRasterBuffer(
  Uint8List bytes,
  String format,
) async {
  if (bytes.isEmpty || bytes.length > RasterLimits.tileBytes) {
    throw const FormatException('Розмір тайла перевищує ліміт 4 MiB.');
  }
  if (rasterEncoding(bytes) != (format == 'jpeg' ? 'jpg' : format)) {
    throw const FormatException('Формат тайла не відповідає метаданим карти.');
  }
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  ui.ImageDescriptor? descriptor;
  try {
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width < 1 ||
        descriptor.height < 1 ||
        descriptor.width > RasterLimits.dimension ||
        descriptor.height > RasterLimits.dimension ||
        descriptor.width * descriptor.height > RasterLimits.pixels) {
      throw const FormatException(
        'Тайл перевищує ліміт роздільності: 1 048 576 пікселів.',
      );
    }
    return buffer;
  } catch (_) {
    buffer.dispose();
    rethrow;
  } finally {
    descriptor?.dispose();
  }
}

Future<ui.Codec> decodeRasterTile(
  Uint8List bytes,
  String format,
  ImageDecoderCallback decode,
) async {
  final codec = await decode(await checkedRasterBuffer(bytes, format));
  if (codec.frameCount != 1) {
    codec.dispose();
    throw const FormatException('Анімовані тайли не підтримуються.');
  }
  return codec;
}

Future<void> verifyRasterSample(Uint8List bytes, String format) async {
  final codec = await decodeRasterTile(
    bytes,
    format,
    ui.instantiateImageCodecWithSize,
  );
  try {
    final frame = await codec.getNextFrame();
    frame.image.dispose();
  } finally {
    codec.dispose();
  }
}
