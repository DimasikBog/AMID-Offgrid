import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../models/data.dart';

/// Split long documents without losing separators or breaking UTF-16 pairs.
List<String> splitDocument(String text, {int maximum = 240000}) {
  if (maximum < 2 || maximum > 250000) throw ArgumentError.value(maximum);
  if (text.isEmpty) return [''];
  final parts = <String>[];
  var start = 0;
  while (start < text.length) {
    var end = (start + maximum).clamp(0, text.length);
    if (end < text.length) {
      final newline = text.lastIndexOf('\n', end - 1);
      if (newline >= start + maximum ~/ 2) end = newline + 1;
      final unit = text.codeUnitAt(end - 1);
      if (unit >= 0xd800 && unit <= 0xdbff) end--;
    }
    parts.add(text.substring(start, end));
    start = end;
  }
  return parts;
}

Json decodeDocument(String name, List<int> bytes) {
  final ext = p.extension(name).toLowerCase();
  if (!{'.txt', '.md', '.json', '.geojson', '.amidbackup'}.contains(ext)) {
    throw const FormatException('Непідтримуваний формат текстового файла.');
  }
  var text = utf8.decode(bytes);
  if (text.startsWith('\ufeff')) text = text.substring(1);
  if (ext != '.txt' && ext != '.md') return decodeObject(text);
  final title = name.trim().isEmpty ? 'Мій документ' : name.trim();
  final shortTitle = title.substring(0, title.length.clamp(0, 200));
  final parts = splitDocument(text);
  return {
    'format': 'AMID_OFFGRID_PACK',
    'version': 1,
    'id': 'text-${const Uuid().v4()}',
    'title': shortTitle,
    'license': 'Власний матеріал користувача.',
    'articles': [
      for (var i = 0; i < parts.length; i++)
        {
          'id': 'part-${i + 1}',
          'title': parts.length == 1
              ? shortTitle
              : '$shortTitle · ${i + 1}/${parts.length}',
          'body': parts[i],
        },
    ],
  };
}

Json documentPack(Json value, String name) => parsePack(
  value['type'] == 'FeatureCollection'
      ? {
          'format': 'AMID_OFFGRID_PACK',
          'version': 1,
          'id': 'map-${const Uuid().v4()}',
          'title': name.substring(0, name.length.clamp(0, 200)),
          'license': 'Користувацький GeoJSON.',
          'articles': [],
          'map': value,
        }
      : value,
);
