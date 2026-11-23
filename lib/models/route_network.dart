import 'dart:math' as math;

/// An explicitly connected, user-supplied network. Geometry never creates links.
class RoutePoint {
  const RoutePoint(this.latitude, this.longitude);
  final double latitude, longitude;

  factory RoutePoint.parse(Object? value) {
    if (value is! List || value.length != 2) {
      throw const FormatException('Координати мережі: [довгота, широта].');
    }
    final lon = value[0], lat = value[1];
    if (lat is! num ||
        lon is! num ||
        !lat.isFinite ||
        !lon.isFinite ||
        lat.abs() > 90 ||
        lon.abs() > 180) {
      throw const FormatException('Некоректні координати мережі.');
    }
    return RoutePoint(lat.toDouble(), lon.toDouble());
  }

  List<double> toJson() => [longitude, latitude];

  double metersTo(RoutePoint other) {
    final lat = latitude * math.pi / 180;
    final nextLat = other.latitude * math.pi / 180;
    final dLat = nextLat - lat;
    final dLon = (other.longitude - longitude) * math.pi / 180;
    final a =
        math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat) * math.cos(nextLat) * math.pow(math.sin(dLon / 2), 2);
    return 6371008.8 * 2 * math.asin(math.sqrt(a.clamp(0, 1)));
  }
}

String _text(Object? value, String field, int maximum) {
  if (value is! String || value.trim().isEmpty || value.length > maximum) {
    throw FormatException('Некоректне поле мережі: $field.');
  }
  return value;
}

Map<String, dynamic> _object(Object? value) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    throw const FormatException('Некоректний об’єкт мережі.');
  }
  return Map<String, dynamic>.from(value);
}

class RouteNode {
  const RouteNode(this.id, this.name, this.point);
  final String id, name;
  final RoutePoint point;

  factory RouteNode.parse(Object? value) {
    final data = _object(value);
    return RouteNode(
      _text(data['id'], 'ID вузла', 100),
      _text(data['name'], 'назва вузла', 150),
      RoutePoint.parse(data['coordinate']),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'coordinate': point.toJson(),
  };
}

class RouteEdge {
  const RouteEdge(
    this.id,
    this.from,
    this.to,
    this.name,
    this.bidirectional,
    this.points,
    this.meters,
  );
  final String id, from, to, name;
  final bool bidirectional;
  final List<RoutePoint> points;
  final double meters;

  Map<String, dynamic> toJson() => {
    'id': id,
    'from': from,
    'to': to,
    'name': name,
    'bidirectional': bidirectional,
    'via': points
        .skip(1)
        .take(points.length - 2)
        .map((p) => p.toJson())
        .toList(),
  };
}

class OfflineRoute {
  const OfflineRoute(this.nodes, this.legs, this.points, this.meters);
  final List<RouteNode> nodes;
  final List<RouteLeg> legs;
  final List<RoutePoint> points;
  final double meters;

  Map<String, dynamic> toGeoJson({
    required String networkTitle,
    required String license,
    required bool synthetic,
  }) => {
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {
          'name': '${nodes.first.name} → ${nodes.last.name}',
          'network': networkTitle,
          'license': license,
          'distance_meters': meters,
          'synthetic': synthetic,
          'node_ids': nodes.map((n) => n.id).toList(),
          'edge_ids': legs.map((l) => l.edge.id).toList(),
        },
        'geometry': {
          'type': 'LineString',
          'coordinates': points.map((p) => p.toJson()).toList(),
        },
      },
    ],
  };
}

class RouteLeg {
  const RouteLeg(this.edge, this.reversed);
  final RouteEdge edge;
  final bool reversed;
  String get from => reversed ? edge.to : edge.from;
  String get to => reversed ? edge.from : edge.to;
  Iterable<RoutePoint> get points =>
      reversed ? edge.points.reversed : edge.points;
}

class RouteNetwork {
  RouteNetwork._(this.nodes, this.edges, this.synthetic);
  static const maxNodes = 10000, maxEdges = 30000, maxViaPoints = 100000;
  final Map<String, RouteNode> nodes;
  final List<RouteEdge> edges;
  final bool synthetic;

  factory RouteNetwork.parse(Object? value) {
    final data = _object(value),
        rawNodes = data['nodes'],
        rawEdges = data['edges'];
    if (data['format'] != 'AMID_ROUTE_NETWORK' ||
        data['version'] != 1 ||
        data['synthetic'] is! bool ||
        rawNodes is! List ||
        rawNodes.length < 2 ||
        rawNodes.length > maxNodes ||
        rawEdges is! List ||
        rawEdges.isEmpty ||
        rawEdges.length > maxEdges) {
      throw const FormatException(
        'Потрібна мережа AMID версії 1: до 10 000 вузлів і 30 000 ділянок.',
      );
    }
    final nodes = <String, RouteNode>{};
    for (final raw in rawNodes) {
      final node = RouteNode.parse(raw);
      if (nodes.containsKey(node.id)) {
        throw const FormatException('Повторювані ID вузлів мережі.');
      }
      nodes[node.id] = node;
    }
    final edges = <RouteEdge>[], ids = <String>{};
    var viaCount = 0;
    for (final raw in rawEdges) {
      final e = _object(raw);
      final id = _text(e['id'], 'ID ділянки', 100);
      final from = _text(e['from'], 'початок ділянки', 100);
      final to = _text(e['to'], 'кінець ділянки', 100);
      final name = _text(e['name'], 'назва ділянки', 150);
      final via = e['via'] ?? <dynamic>[];
      if (!ids.add(id) ||
          from == to ||
          !nodes.containsKey(from) ||
          !nodes.containsKey(to) ||
          e['bidirectional'] is! bool ||
          via is! List ||
          (viaCount += via.length) > maxViaPoints) {
        throw const FormatException(
          'Некоректні зв’язки або завелика геометрія мережі.',
        );
      }
      final points = [
        nodes[from]!.point,
        ...via.map(RoutePoint.parse),
        nodes[to]!.point,
      ];
      var meters = 0.0;
      for (var i = 1; i < points.length; i++) {
        if ((points[i].longitude - points[i - 1].longitude).abs() > 180) {
          throw const FormatException(
            'Ділянки через антимеридіан поки не підтримуються.',
          );
        }
        meters += points[i - 1].metersTo(points[i]);
      }
      if (!meters.isFinite || meters <= 0) {
        throw const FormatException('Ділянка повинна мати ненульову довжину.');
      }
      edges.add(
        RouteEdge(
          id,
          from,
          to,
          name,
          e['bidirectional'] as bool,
          List.unmodifiable(points),
          meters,
        ),
      );
    }
    return RouteNetwork._(
      Map.unmodifiable(nodes),
      List.unmodifiable(edges),
      data['synthetic'] as bool,
    );
  }

  Map<String, dynamic> toJson() => {
    'format': 'AMID_ROUTE_NETWORK',
    'version': 1,
    'synthetic': synthetic,
    'nodes': nodes.values.map((n) => n.toJson()).toList(),
    'edges': edges.map((e) => e.toJson()).toList(),
  };

  OfflineRoute shortestPath(String from, String to) {
    if (!nodes.containsKey(from) || !nodes.containsKey(to) || from == to) {
      throw const FormatException(
        'Обери різні початковий і кінцевий вузли мережі.',
      );
    }
    final adjacency = <String, List<RouteLeg>>{};
    for (final edge in edges) {
      (adjacency[edge.from] ??= []).add(RouteLeg(edge, false));
      if (edge.bidirectional) {
        (adjacency[edge.to] ??= []).add(RouteLeg(edge, true));
      }
    }
    final distance = <String, double>{from: 0}, previous = <String, RouteLeg>{};
    final queue = _MinQueue()..add(_Entry(from, 0));
    while (queue.isNotEmpty) {
      final current = queue.remove();
      if (current.meters != distance[current.id]) continue;
      if (current.id == to) break;
      for (final leg in adjacency[current.id] ?? <RouteLeg>[]) {
        final next = current.meters + leg.edge.meters;
        if (next < (distance[leg.to] ?? double.infinity)) {
          distance[leg.to] = next;
          previous[leg.to] = leg;
          queue.add(_Entry(leg.to, next));
        }
      }
    }
    if (!previous.containsKey(to)) {
      throw const FormatException(
        'Між цими вузлами немає дозволеного шляху в цій мережі.',
      );
    }
    final reverse = <RouteLeg>[];
    for (var node = to; node != from;) {
      final leg = previous[node]!;
      reverse.add(leg);
      node = leg.from;
    }
    final legs = reverse.reversed.toList(growable: false);
    final path = [nodes[from]!.point];
    for (final leg in legs) {
      path.addAll(leg.points.skip(1));
    }
    return OfflineRoute(
      List.unmodifiable([nodes[from]!, ...legs.map((l) => nodes[l.to]!)]),
      List.unmodifiable(legs),
      List.unmodifiable(path),
      distance[to]!,
    );
  }
}

OfflineRoute calculateOfflineRoute(Map<String, dynamic> request) =>
    RouteNetwork.parse(request['network'])
        .shortestPath(request['from'] as String, request['to'] as String);

class _Entry {
  const _Entry(this.id, this.meters);
  final String id;
  final double meters;
}

class _MinQueue {
  final _heap = <_Entry>[];
  bool get isNotEmpty => _heap.isNotEmpty;
  void add(_Entry entry) {
    _heap.add(entry);
    var i = _heap.length - 1;
    while (i > 0) {
      final parent = (i - 1) ~/ 2;
      if (_heap[parent].meters <= entry.meters) break;
      _heap[i] = _heap[parent];
      i = parent;
    }
    _heap[i] = entry;
  }

  _Entry remove() {
    final first = _heap.first, last = _heap.removeLast();
    if (_heap.isEmpty) return first;
    var i = 0;
    while (2 * i + 1 < _heap.length) {
      var child = 2 * i + 1;
      if (child + 1 < _heap.length &&
          _heap[child + 1].meters < _heap[child].meters) {
        child++;
      }
      if (last.meters <= _heap[child].meters) break;
      _heap[i] = _heap[child];
      i = child;
    }
    _heap[i] = last;
    return first;
  }
}
