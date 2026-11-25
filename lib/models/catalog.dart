import 'dart:convert';

import 'package:flutter/services.dart';

import 'data.dart';

class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.title,
    required this.kind,
    required this.description,
    required this.source,
    required this.license,
    this.url,
    this.sha256 = '',
    this.bytes = 0,
    this.ramGiB = 0,
    this.year,
  });
  final String id, title, kind, description, source, license, sha256;
  final Uri? url;
  final int bytes, ramGiB;
  final int? year;
  bool get installable => url != null;
  bool get model => kind == 'model';
  factory CatalogEntry.fromJson(Json data) {
    final id = checkedText(data['id'], 'ID', 80);
    if (!RegExp(r'^[a-z0-9][a-z0-9-]{1,79}$').hasMatch(id)) {
      throw const FormatException('Некоректний ID каталогу.');
    }
    final kind = checkedText(data['kind'], 'тип', 20);
    if (!{'model', 'image', 'geojson', 'source'}.contains(kind)) {
      throw const FormatException('Невідомий тип пакета.');
    }
    final source = checkedText(data['source'], 'джерело', 1500);
    if (Uri.tryParse(source)?.scheme != 'https') {
      throw const FormatException('Потрібне HTTPS-джерело.');
    }
    Uri? url;
    final raw = data['url'];
    final bytes = data['bytes'] as int? ?? 0;
    final digest = data['sha256'] as String? ?? '';
    if (raw != null) {
      url = Uri.parse(raw as String);
      final allowed = {
        'huggingface.co',
        'upload.wikimedia.org',
        'raw.githubusercontent.com',
      };
      if (url.scheme != 'https' ||
          !allowed.contains(url.host) ||
          url.userInfo.isNotEmpty ||
          url.hasFragment ||
          (url.hasPort && url.port != 443) ||
          bytes < 1 ||
          bytes > (kind == 'model' ? 8589934592 : 16 << 20) ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest) ||
          kind == 'source') {
        throw const FormatException('Неперевірене джерело завантаження.');
      }
    } else if (kind != 'source') {
      throw const FormatException('Пакет не має джерела завантаження.');
    }
    return CatalogEntry(
      id: id,
      title: checkedText(data['title'], 'назва', 200),
      kind: kind,
      description: checkedText(data['description'], 'опис', 2000),
      source: source,
      license: checkedText(data['license'], 'ліцензія', 1000),
      url: url,
      bytes: bytes,
      sha256: digest,
      ramGiB: data['ramGiB'] as int? ?? 0,
      year: data['year'] as int?,
    );
  }
}

Future<List<CatalogEntry>> loadCatalog({AssetBundle? bundle}) async {
  final data = jsonDecode(
    await (bundle ?? rootBundle).loadString('assets/catalog.json'),
  ) as Json;
  if (data['format'] != 'AMID_CATALOG' ||
      data['version'] != 1 ||
      data['entries'] is! List ||
      (data['entries'] as List).length > 200) {
    throw const FormatException('Невідомий каталог.');
  }
  final items = (data['entries'] as List)
      .map((e) => CatalogEntry.fromJson(Json.from(e as Map)))
      .toList();
  if (items.map((e) => e.id).toSet().length != items.length) {
    throw const FormatException('Повторювані пакети каталогу.');
  }
  return List.unmodifiable(items);
}
