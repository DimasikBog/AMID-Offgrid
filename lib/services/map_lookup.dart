import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/data.dart';
import '../models/route_network.dart';

class MapPlace {
  const MapPlace(this.name, this.point, {this.detail = '', this.regionId});
  final String name, detail;
  final String? regionId;
  final RoutePoint point;
}

MapPlace? coordinatePlace(String query) {
  final match = RegExp(
    r'^\s*(-?\d+(?:\.\d+)?)\s*[,;\s]\s*(-?\d+(?:\.\d+)?)\s*$',
  ).firstMatch(query);
  if (match == null) return null;
  final lat = double.tryParse(match[1]!), lon = double.tryParse(match[2]!);
  if (lat == null ||
      lon == null ||
      !lat.isFinite ||
      !lon.isFinite ||
      lat.abs() > 90 ||
      lon.abs() > 180) {
    return null;
  }
  return MapPlace('Координати', RoutePoint(lat, lon), detail: '$lat, $lon');
}

class MapLookup {
  MapLookup({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  bool _closed = false;
  static final _clock = Stopwatch()..start();
  static final _nextAllowed = <String, int>{};
  static final _queues = <String, Future<void>>{};

  Future<Json> _get(Uri uri) async {
    final previous = _queues[uri.host] ?? Future<void>.value();
    final admitted = Completer<void>();
    _queues[uri.host] = admitted.future;
    try {
      await previous;
      final delay = (_nextAllowed[uri.host] ?? 0) - _clock.elapsedMilliseconds;
      if (delay > 0) await Future<void>.delayed(Duration(milliseconds: delay));
      if (_closed) throw StateError('Запит скасовано.');
      _nextAllowed[uri.host] = _clock.elapsedMilliseconds + 1200;
    } finally {
      admitted.complete();
    }
    final request = http.Request('GET', uri)..followRedirects = false;
    if (!kIsWeb) {
      request.headers['User-Agent'] =
          'AMID-Offgrid (+https://github.com/DimasikBog/AMID-Offgrid)';
    }
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200 ||
        (response.contentLength ?? 0) > 2 * 1024 * 1024) {
      await response.stream.listen((_) {}).cancel();
      throw StateError('Сервіс карти недоступний. Спробуй пізніше.');
    }
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream.timeout(
      const Duration(seconds: 25),
    )) {
      if (_closed) throw StateError('Запит скасовано.');
      if (bytes.length + chunk.length > 2 * 1024 * 1024) {
        throw const FormatException('Відповідь карти завелика.');
      }
      bytes.add(chunk);
    }
    return decodeObject(utf8.decode(bytes.takeBytes()));
  }

  Future<List<MapPlace>> search(String query) async {
    final text = query.trim();
    if (text.runes.length < 3 || text.runes.length > 200) {
      throw const FormatException('Пошук: від 3 до 200 символів.');
    }
    final data = await _get(
      Uri.https('photon.komoot.io', '/api/', {
        'q': text,
        'limit': '8',
        'lang': 'en',
      }),
    );
    return parsePlaces(data);
  }

  static List<MapPlace> parsePlaces(Json data) {
    final features = data['features'];
    if (features is! List || features.length > 50) {
      throw const FormatException('Некоректна відповідь пошуку.');
    }
    final result = <MapPlace>[];
    for (final raw in features.take(8)) {
      if (raw is! Map ||
          raw['geometry'] is! Map ||
          raw['properties'] is! Map ||
          raw['geometry']['type'] != 'Point') {
        continue;
      }
      try {
        final point = RoutePoint.parse(raw['geometry']['coordinates']);
        final props = raw['properties'] as Map;
        String field(String key) => props[key] is String
            ? String.fromCharCodes((props[key] as String).runes.take(160))
            : '';
        final address = [
          field('street'),
          field('housenumber'),
        ].where((s) => s.isNotEmpty).join(' ');
        final title = field('name').isNotEmpty ? field('name') : address;
        if (title.isEmpty) continue;
        result.add(
          MapPlace(
            title,
            point,
            detail: [
              address,
              field('city'),
              field('country'),
            ].where((s) => s.isNotEmpty).toSet().join(' · '),
          ),
        );
      } on FormatException {
        /* Skip a malformed result without losing the others. */
      }
    }
    return result;
  }

  Future<RoadDirections> route(MapPlace from, MapPlace to, String mode) async {
    if (!{'foot', 'bike', 'car'}.contains(mode)) {
      throw const FormatException('Невідомий спосіб руху.');
    }
    if (from.point.metersTo(to.point) < 2) {
      throw const FormatException('Обери різні точки старту та фінішу.');
    }
    final coords =
        '${from.point.longitude},${from.point.latitude};${to.point.longitude},${to.point.latitude}';
    final data = await _get(
      Uri.https(
        'routing.openstreetmap.de',
        '/routed-$mode/route/v1/driving/$coords',
        {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
      ),
    );
    return RoadDirections.parse(data, from, to, mode);
  }

  void dispose() {
    _closed = true;
    _client.close();
  }
}

class RoadDirections {
  const RoadDirections(
    this.from,
    this.to,
    this.mode,
    this.points,
    this.meters,
    this.seconds,
  );
  final MapPlace from, to;
  final String mode;
  final List<RoutePoint> points;
  final double meters, seconds;
  static RoadDirections parse(
    Json data,
    MapPlace from,
    MapPlace to,
    String mode,
  ) {
    final routes = data['routes'];
    if (data['code'] != 'Ok' ||
        routes is! List ||
        routes.isEmpty ||
        routes.first is! Map) {
      throw const FormatException('Не вдалося знайти маршрут цими дорогами.');
    }
    final route = routes.first as Map, geometry = route['geometry'];
    final meters = route['distance'], seconds = route['duration'];
    if (meters is! num ||
        !meters.isFinite ||
        meters < 0 ||
        meters > 50000000 ||
        seconds is! num ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds > 31536000 ||
        geometry is! Map ||
        geometry['type'] != 'LineString' ||
        geometry['coordinates'] is! List ||
        (geometry['coordinates'] as List).length < 2 ||
        (geometry['coordinates'] as List).length > 20000) {
      throw const FormatException('Некоректна геометрія маршруту.');
    }
    final points = (geometry['coordinates'] as List)
        .map(RoutePoint.parse)
        .toList(growable: false);
    if (points.first.metersTo(from.point) > 2000 ||
        points.last.metersTo(to.point) > 2000) {
      throw const FormatException(
        'Обрані точки надто далеко від доступних доріг. Обери точку на дорозі або стежці.',
      );
    }
    return RoadDirections(
      from,
      to,
      mode,
      points,
      meters.toDouble(),
      seconds.toDouble(),
    );
  }

  Json get geoJson => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {
          'name': '${from.name} → ${to.name}',
          'amid_route': true,
          'distance_m': meters,
          'duration_s': seconds,
          'travel_mode': mode,
          'source': 'FOSSGIS / OpenStreetMap',
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': points.map((p) => p.toJson()).toList(),
        },
      },
    ],
  };
}
