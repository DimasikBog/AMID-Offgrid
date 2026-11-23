import 'dart:convert';

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/models/map_metadata.dart';
import 'package:amid_offgrid/services/document_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'large UTF-16 documents round trip without lost separators or emoji',
    () {
      const source = 'Річка 🌊\nДім 🏠\n';
      final text = List.filled(100, source).join();
      final parts = splitDocument(text, maximum: 13);
      expect(parts.join(), text);
      for (final part in parts) {
        expect(part.length, lessThanOrEqualTo(13));
        expect(utf8.decode(utf8.encode(part)), part);
      }
    },
  );
  test('BOM and long Markdown import as complete searchable articles', () {
    final text = List.filled(60000, 'Знання\n').join();
    final pack = parsePack(
      decodeDocument('Документ.MD', utf8.encode('\ufeff$text')),
    );
    final articles = pack['articles'] as List;
    expect(articles.length, greaterThan(1));
    expect(articles.map((a) => a['body']).join(), text);
    expect(articles.map((a) => a['key']).toSet().length, articles.length);
  });
  test('unknown file types and non-object documents are rejected', () {
    expect(
      () => decodeDocument('file.exe', utf8.encode('{}')),
      throwsFormatException,
    );
    expect(
      () => decodeDocument('file.json', utf8.encode('[1]')),
      throwsFormatException,
    );
    expect(
      () => parsePack({
        'format': 'AMID_OFFGRID_PACK',
        'version': 1,
        'id': 'bad',
        'title': 'bad',
        'license': 'CC0',
        'articles': [null],
      }),
      throwsFormatException,
    );
  });
  test('MBTiles rejects NaN, reversed ranges and malformed coordinates', () {
    for (final values in <Map<String, String>>[
      {'format': 'png', 'minzoom': 'NaN'},
      {'format': 'png', 'minzoom': '15', 'maxzoom': '4'},
      {'format': 'png', 'bounds': '0,50,20,40'},
      {'format': 'png', 'center': 'x,y,4'},
      {'format': 'pbf'},
    ]) {
      expect(() => parseRasterMapMetadata(values), throwsFormatException);
    }
  });
  test('MBTiles centered across the date line stays at the date line', () {
    final value = parseRasterMapMetadata({
      'format': 'png',
      'bounds': '170,-10,-170,10',
      'minzoom': '2',
      'maxzoom': '12',
    });
    expect((value['center'] as List)[1], -180);
    expect(value['minZoom'], 2);
  });
}
