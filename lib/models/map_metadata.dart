import 'data.dart';

Json parseRasterMapMetadata(Map<String, String> metadata) {
  if (!{
    'png',
    'jpg',
    'jpeg',
    'webp',
  }.contains(metadata['format']?.toLowerCase())) {
    throw const FormatException(
      'Підтримуються растрові MBTiles: PNG, JPG, WebP. Векторні PBF ще не підтримуються.',
    );
  }
  double zoom(String key, double fallback) {
    if (!metadata.containsKey(key)) return fallback;
    final value = double.tryParse(metadata[key]!);
    if (value == null || !value.isFinite || value < 0 || value > 24) {
      throw FormatException('Некоректний масштаб карти: $key');
    }
    return value;
  }

  final minZoom = zoom('minzoom', 0), maxZoom = zoom('maxzoom', 20);
  if (minZoom > maxZoom) {
    throw const FormatException('Переплутані масштаби карти.');
  }
  List<double>? coordinates(String key, int length) {
    final text = metadata[key];
    if (text == null) return null;
    final values = text
        .split(',')
        .map((v) => double.tryParse(v.trim()))
        .toList();
    if (values.length != length ||
        values.any((v) => v == null || !v.isFinite)) {
      throw FormatException('Некоректне поле карти: $key');
    }
    return values.cast<double>();
  }

  final center = coordinates('center', 3), bounds = coordinates('bounds', 4);
  if (bounds != null &&
      (bounds[0].abs() > 180 ||
          bounds[2].abs() > 180 ||
          bounds[1].abs() > 90 ||
          bounds[3].abs() > 90 ||
          bounds[1] > bounds[3])) {
    throw const FormatException('Некоректні межі карти.');
  }
  var lat = 20.0, lon = 0.0, level = minZoom;
  if (center != null) {
    lon = center[0];
    lat = center[1];
    level = center[2];
  } else if (bounds != null) {
    lon = bounds[0] <= bounds[2]
        ? (bounds[0] + bounds[2]) / 2
        : ((bounds[0] + bounds[2] + 360) / 2 + 180) % 360 - 180;
    lat = (bounds[1] + bounds[3]) / 2;
  }
  if (lat.abs() > 85.05112878 || lon.abs() > 180 || level < 0 || level > 24) {
    throw const FormatException('Некоректний центр карти.');
  }
  return {
    'center': [lat, lon, level.clamp(minZoom, maxZoom)],
    'minZoom': minZoom,
    'maxZoom': maxZoom,
    'attribution': checkedText(
      metadata['attribution'] ?? 'Користувацька карта · перевір джерело',
      'джерело карти',
      8000,
      empty: true,
    ),
  };
}
