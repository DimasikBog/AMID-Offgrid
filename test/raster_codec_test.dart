import 'dart:convert';
import 'dart:typed_data';

import 'package:amid_offgrid/models/raster_limits.dart';
import 'package:amid_offgrid/services/raster_codec_native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'raster_image_fixtures.dart';
import 'raster_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final format in ['png', 'jpeg', 'webp']) {
    test('decode a real synthetic $format image sample', () async {
      final bytes = format == 'png'
          ? rasterPng()
          : base64Decode(rasterImageFixtures[format]!);
      await verifyRasterSample(bytes, format);
    });
  }
  for (final name in ['wide', 'pixels']) {
    test('reject $name dimensions before pixel decoding', () async {
      await expectLater(
        checkedRasterBuffer(base64Decode(rasterImageFixtures[name]!), 'png'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('роздільності'),
          ),
        ),
      );
    });
  }
  test(
    'reject empty, oversized, wrong-signature and mismatched formats',
    () async {
      for (final bytes in [
        Uint8List(0),
        Uint8List(RasterLimits.tileBytes + 1),
        Uint8List.fromList([1, 2, 3]),
      ]) {
        await expectLater(
          checkedRasterBuffer(bytes, 'png'),
          throwsFormatException,
        );
      }
      await expectLater(
        checkedRasterBuffer(rasterPng(), 'jpg'),
        throwsFormatException,
      );
    },
  );
  test('animated WebP is not accepted as a static map tile', () async {
    await expectLater(
      verifyRasterSample(
        base64Decode(rasterImageFixtures['animated']!),
        'webp',
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('Анімовані'),
        ),
      ),
    );
  });
}
