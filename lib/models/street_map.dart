import 'dart:math' as math;

import 'data.dart';

const streetArchiveUrl =
    'https://data.source.coop/protomaps/openstreetmap/v4.pmtiles';
const streetAttribution = '© OpenStreetMap contributors · Protomaps · ODbL';
const maxStreetTiles = 3000;
const maxStreetBytes = 50 * 1024 * 1024;
const maxStreetStorageBytes = 250 * 1024 * 1024;

class StreetTile {
  const StreetTile(this.z, this.x, this.y);
  final int z, x, y;
  String get key => '$z-$x-$y';
  static StreetTile parse(String value) {
    final parts = value.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.any((v) => v == null)) {
      throw const FormatException('Некоректний тайл.');
    }
    final z = parts[0]!, x = parts[1]!, y = parts[2]!;
    if (z < 0 || z > 15 || x < 0 || y < 0 || x >= (1 << z) || y >= (1 << z)) {
      throw const FormatException('Координати тайла поза картою.');
    }
    return StreetTile(z, x, y);
  }
}

class StreetBounds {
  StreetBounds(this.west, this.south, this.east, this.north) {
    if ([west, south, east, north].any((n) => !n.isFinite) ||
        west.abs() > 180 ||
        east.abs() > 180 ||
        south < -85.05112878 ||
        north > 85.05112878 ||
        south >= north) {
      throw const FormatException('Некоректні межі області.');
    }
  }
  final double west, south, east, north;
  List<double> get json => [west, south, east, north];
  double get centerLatitude => (south + north) / 2;
  double get centerLongitude => west <= east
      ? (west + east) / 2
      : ((west + east + 360) / 2 + 180) % 360 - 180;

  List<StreetTile> tiles(int maximumZoom) {
    if (maximumZoom < 10 || maximumZoom > 15) {
      throw const FormatException('Масштаб області: 10–15.');
    }
    final result = <String, StreetTile>{};
    for (var z = 0; z <= maximumZoom; z++) {
      final n = 1 << z;
      int x(double lon) => (((lon + 180) / 360) * n).floor().clamp(0, n - 1);
      int y(double lat) {
        final r = lat * math.pi / 180;
        return ((1 - math.log(math.tan(r) + 1 / math.cos(r)) / math.pi) / 2 * n)
            .floor()
            .clamp(0, n - 1);
      }

      final top = y(north), bottom = y(south);
      final spans = west <= east
          ? [(x(west), x(east))]
          : [(x(west), n - 1), (0, x(east))];
      for (final span in spans) {
        if ((span.$2 - span.$1 + 1) * (bottom - top + 1) + result.length >
            maxStreetTiles + 1) {
          throw const FormatException(
            'Область завелика. Наблизь карту або обери менший масштаб деталізації.',
          );
        }
        for (var col = span.$1; col <= span.$2; col++) {
          for (var row = top; row <= bottom; row++) {
            final tile = StreetTile(z, col, row);
            result[tile.key] = tile;
            if (result.length > maxStreetTiles) {
              throw const FormatException('Ліміт області — 3000 тайлів.');
            }
          }
        }
      }
    }
    return result.values.toList(growable: false);
  }
}

class StreetRegion {
  StreetRegion(this.data) {
    final id = data['id'], title = data['title'];
    if (id is! String ||
        !RegExp(r'^[a-f0-9-]{36}$').hasMatch(id) ||
        title is! String ||
        title.trim().isEmpty ||
        title.runes.length > 80 ||
        data['source'] != streetArchiveUrl ||
        (data['dataDate'] != null && data['dataDate'] is! String) ||
        data['maxZoom'] is! int ||
        (data['maxZoom'] as int) < 10 ||
        (data['maxZoom'] as int) > 15 ||
        data['bytes'] is! int ||
        data['createdAt'] is! String ||
        DateTime.tryParse(data['createdAt'] as String) == null ||
        data['tiles'] is! Map ||
        (data['tiles'] as Map).length > maxStreetTiles ||
        (data['tiles'] as Map).isEmpty) {
      throw const FormatException('Некоректна збережена область.');
    }
    final raw = data['bounds'];
    if (raw is! List || raw.length != 4 || raw.any((n) => n is! num)) {
      throw const FormatException('Некоректні межі області.');
    }
    bounds = StreetBounds(
      (raw[0] as num).toDouble(),
      (raw[1] as num).toDouble(),
      (raw[2] as num).toDouble(),
      (raw[3] as num).toDouble(),
    );
    var size = 0;
    for (final entry in (data['tiles'] as Map).entries) {
      if (entry.key is! String || entry.value is! Map) {
        throw const FormatException('Некоректний індекс області.');
      }
      final tile = StreetTile.parse(entry.key as String),
          record = entry.value as Map;
      if (tile.z > maxZoom ||
          record['bytes'] is! int ||
          (record['bytes'] as int) < 0 ||
          (record['bytes'] as int) > 2 * 1024 * 1024 ||
          record['sha256'] is! String ||
          !RegExp(r'^[a-f0-9]{64}$').hasMatch(record['sha256'] as String)) {
        throw const FormatException('Некоректний запис тайла.');
      }
      size += record['bytes'] as int;
    }
    if (size > maxStreetBytes ||
        data['bytes'] != size ||
        bounds
            .tiles(maxZoom)
            .map((t) => t.key)
            .toSet()
            .difference(tileKeys.toSet())
            .isNotEmpty ||
        bounds.tiles(maxZoom).length != tileKeys.length) {
      throw const FormatException('Неповна або завелика область.');
    }
  }
  final Json data;
  late final StreetBounds bounds;
  String get id => data['id'] as String;
  String get title => data['title'] as String;
  int get maxZoom => data['maxZoom'] as int;
  int get bytes => data['bytes'] as int;
  Iterable<String> get tileKeys => (data['tiles'] as Map).keys.cast<String>();
  String storageId(String tileKey) => 'street-$id-$tileKey';
}
