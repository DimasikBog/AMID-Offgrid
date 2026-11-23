import 'dart:convert';

import 'route_network.dart';

typedef Json = Map<String, dynamic>;

Json checkedObject(Object? value, String field) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw FormatException('Потрібен об’єкт: $field');
  }
  return Json.from(value);
}

String boundedText(String text, int maximum) {
  if (text.length <= maximum) return text;
  var end = maximum;
  if (end > 0 &&
      text.codeUnitAt(end - 1) >= 0xd800 &&
      text.codeUnitAt(end - 1) <= 0xdbff) {
    end--;
  }
  return text.substring(0, end);
}

String checkedText(Object? value, String field, int max, {bool empty = false}) {
  if (value is! String ||
      value.length > max ||
      (!empty && value.trim().isEmpty)) {
    throw FormatException('Некоректне поле: $field');
  }
  return value;
}

class Article {
  const Article({
    required this.key,
    required this.packId,
    required this.title,
    required this.body,
    required this.category,
    required this.license,
    this.source = '',
  });
  final String key, packId, title, body, category, license, source;
  factory Article.fromJson(Json r) => Article(
    key: r['key'] as String,
    packId: r['packId'] as String,
    title: r['title'] as String,
    body: r['body'] as String,
    category: r['category'] as String,
    license: r['license'] as String,
    source: r['source'] as String? ?? '',
  );
  Json toJson() => {
    'key': key,
    'packId': packId,
    'title': title,
    'body': body,
    'category': category,
    'license': license,
    'source': source,
  };
}

Json parsePack(Json data) {
  if (data['format'] != 'AMID_OFFGRID_PACK' || data['version'] != 1) {
    throw const FormatException('Потрібен пакет AMID версії 1.');
  }
  final id = checkedText(data['id'], 'ID пакета', 100);
  if (!RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(id)) {
    throw const FormatException('Некоректний ID пакета.');
  }
  final title = checkedText(data['title'], 'назва пакета', 200),
      license = checkedText(data['license'], 'ліцензія', 2000);
  if (data['articles'] is! List || (data['articles'] as List).length > 25000) {
    throw const FormatException('Некоректний список статей.');
  }
  final seen = <String>{};
  final articles = (data['articles'] as List).map((value) {
    final a = checkedObject(value, 'стаття'),
        articleId = checkedText(a['id'], 'ID статті', 100);
    if (!seen.add(articleId)) {
      throw const FormatException('Повторювані ID статей.');
    }
    final source = checkedText(a['source'] ?? '', 'джерело', 2000, empty: true);
    if (source.isNotEmpty &&
        !['https', 'http'].contains(Uri.tryParse(source)?.scheme)) {
      throw const FormatException('Джерело має бути HTTP(S)-посиланням.');
    }
    return Article(
      key: '$id::$articleId',
      packId: id,
      title: checkedText(a['title'], 'назва статті', 250),
      body: checkedText(a['body'], 'текст статті', 250000, empty: true),
      category: checkedText(a['category'] ?? 'Мої матеріали', 'категорія', 100),
      license: license,
      source: source,
    ).toJson();
  }).toList();
  return {
    'id': id,
    'title': title,
    'license': license,
    'kind': 'knowledge',
    'articles': articles,
    if (data['map'] != null)
      'map': validateGeoJson(checkedObject(data['map'], 'карта')),
    if (data['routing'] != null)
      'routing': RouteNetwork.parse(data['routing']).toJson(),
  };
}

Json validateGeoJson(Json value) {
  if (value['type'] != 'FeatureCollection' ||
      value['features'] is! List ||
      (value['features'] as List).length > 50000) {
    throw const FormatException('Потрібен GeoJSON FeatureCollection.');
  }
  var total = 0;
  Object coordinates(Object? v, int depth) {
    if (v is! List || v.isEmpty) {
      throw const FormatException('Порожня геометрія.');
    }
    if (depth > 0) return v.map((p) => coordinates(p, depth - 1)).toList();
    if (++total > 300000 ||
        v.length < 2 ||
        v[0] is! num ||
        v[1] is! num ||
        !(v[0] as num).isFinite ||
        !(v[1] as num).isFinite ||
        (v[0] as num).abs() > 180 ||
        (v[1] as num).abs() > 90) {
      throw const FormatException('Некоректні координати.');
    }
    return [(v[0] as num).toDouble(), (v[1] as num).toDouble()];
  }

  const depth = {
    'Point': 0,
    'LineString': 1,
    'MultiLineString': 2,
    'Polygon': 2,
    'MultiPolygon': 3,
  };
  return {
    'type': 'FeatureCollection',
    'features': (value['features'] as List).map((f) {
      if (f is! Map || f['type'] != 'Feature' || f['geometry'] is! Map) {
        throw const FormatException('Некоректний об’єкт карти.');
      }
      final g = f['geometry'] as Map,
          p = f['properties'] is Map ? f['properties'] as Map : {};
      if (!depth.containsKey(g['type'])) {
        throw const FormatException('Непідтримувана геометрія.');
      }
      final name = '${p['name'] ?? p['NAME'] ?? ''}';
      return {
        'type': 'Feature',
        'geometry': {
          'type': g['type'],
          'coordinates': coordinates(g['coordinates'], depth[g['type']]!),
        },
        'properties': {'name': name.substring(0, name.length.clamp(0, 250))},
      };
    }).toList(),
  };
}

class Pin {
  const Pin(this.id, this.name, this.latitude, this.longitude);
  final String id, name;
  final double latitude, longitude;
  factory Pin.fromJson(Json v) {
    final c = v['coordinate'];
    final lat = c is List && c.length >= 2 ? c[1] : v['latitude'],
        lon = c is List && c.length >= 2 ? c[0] : v['longitude'];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Некоректні координати.');
    }
    return Pin(
      checkedText(v['id'], 'ID точки', 100),
      checkedText(v['name'], 'назва точки', 100),
      lat.toDouble(),
      lon.toDouble(),
    );
  }
  Json toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
  };
  String get text =>
      '$name\nШирота: ${latitude.toStringAsFixed(6)}\nДовгота: ${longitude.toStringAsFixed(6)}';
}

class Message {
  const Message(
    this.id,
    this.body,
    this.createdAt,
    this.direction,
    this.status,
  );
  final String id, body, createdAt, direction, status;
  factory Message.parse(
    Json v, {
    String direction = 'in',
    String status = 'received',
  }) {
    if (!{'in', 'out'}.contains(direction) ||
        (direction == 'in' && status != 'received') ||
        (direction == 'out' &&
            !{'draft', 'transferred', 'delivered'}.contains(status))) {
      throw const FormatException('Некоректний стан повідомлення.');
    }
    if (v['format'] != 'AMID_OFFGRID_MESSAGE' || v['version'] != 1) {
      throw const FormatException('Невідомий формат повідомлення.');
    }
    final time = checkedText(v['createdAt'], 'час', 80);
    if (DateTime.tryParse(time) == null) {
      throw const FormatException('Некоректний час.');
    }
    return Message(
      checkedText(v['id'], 'ID', 100),
      checkedText(v['body'], 'текст', 4000),
      time,
      direction,
      status,
    );
  }
  factory Message.fromJson(Json v) => Message.parse(
    v,
    direction: v['direction'] as String? ?? 'out',
    status: v['status'] as String? ?? 'draft',
  );
  Json toWire() => {
    'format': 'AMID_OFFGRID_MESSAGE',
    'version': 1,
    'id': id,
    'body': body,
    'createdAt': createdAt,
  };
  Json toJson() => {...toWire(), 'direction': direction, 'status': status};
  Message withStatus(String s) => Message(id, body, createdAt, direction, s);
  String get statusLabel => switch (status) {
    'received' => 'Отримано',
    'delivered' => 'Отримання підтверджено',
    'transferred' => 'Передано · очікую підтвердження',
    _ => 'Чернетка',
  };
}

List<String> searchTerms(String query) =>
    RegExp(r'[a-zA-Z0-9\u00c0-\u024f\u0400-\u04ff]+')
        .allMatches(query.toLowerCase())
        .map((m) => m.group(0)!)
        .where(
          (w) =>
              w.length > 1 &&
              !{
                'як',
                'що',
                'це',
                'та',
                'на',
                'для',
                'the',
                'and',
                'або',
              }.contains(w),
        )
        .toSet()
        .take(16)
        .toList();
String prettyBytes(int n) => n >= 1073741824
    ? '${(n / 1073741824).toStringAsFixed(1)} GiB'
    : n >= 1048576
    ? '${(n / 1048576).toStringAsFixed(1)} MiB'
    : n >= 1024
    ? '${(n / 1024).toStringAsFixed(0)} KiB'
    : '$n B';
Json decodeObject(String value) {
  final data = jsonDecode(
    value.startsWith('\ufeff') ? value.substring(1) : value,
  );
  if (data is! Json) throw const FormatException('Потрібен об’єкт JSON.');
  return data;
}
