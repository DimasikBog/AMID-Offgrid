import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:amid_offgrid/models/data.dart';
import 'package:amid_offgrid/models/route_network.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Json examplePack() =>
    decodeObject(File('examples/route_network.json').readAsStringSync());
Json exampleNetwork() => Json.from(examplePack()['routing'] as Map);

void main() {
  test('native background calculation returns the complete route', () async {
    final route = await compute(calculateOfflineRoute, <String, dynamic>{
      'network': exampleNetwork(),
      'from': 'a',
      'to': 'c',
    });
    expect(route.nodes.map((n) => n.id), ['a', 'b', 'c']);
    expect(route.points, hasLength(3));
  });
  test('geodesic distance and canonical network round trip', () {
    expect(
      const RoutePoint(0, 0).metersTo(const RoutePoint(0, 1)),
      closeTo(111195.08, .1),
    );
    expect(const RoutePoint(0, 0).metersTo(const RoutePoint(0, 0)), 0);
    final network = RouteNetwork.parse(exampleNetwork());
    expect(RouteNetwork.parse(network.toJson()).toJson(), network.toJson());
    expect(network.nodes, hasLength(4));
  });

  test('shortest distance wins over fewer edges; direction is respected', () {
    final network = RouteNetwork.parse(exampleNetwork());
    final forward = network.shortestPath('a', 'c');
    expect(forward.nodes.map((n) => n.id), ['a', 'b', 'c']);
    expect(forward.legs.map((l) => l.edge.id), ['ab', 'bc']);
    expect(forward.meters, closeTo(222.39016, .01));
    final backward = network.shortestPath('c', 'a');
    expect(backward.legs.single.edge.id, 'ac-detour');
    expect(backward.legs.single.reversed, isTrue);
    expect(backward.points.map((p) => p.toJson()), [
      [.002, 0.0],
      [.001, .002],
      [0.0, 0.0],
    ]);
    expect(backward.meters, greaterThan(forward.meters));
  });

  test(
    'disconnected, unknown and identical endpoints do not invent a route',
    () {
      final network = RouteNetwork.parse(exampleNetwork());
      for (final pair in [
        ('a', 'd'),
        ('d', 'a'),
        ('a', 'missing'),
        ('a', 'a'),
      ]) {
        expect(
          () => network.shortestPath(pair.$1, pair.$2),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'coincident geometry does not create a junction between distinct IDs',
    () {
      final data = exampleNetwork();
      (data['nodes'] as List).add({
        'id': 'b-other-level',
        'name': 'Інший рівень',
        'coordinate': [.001, 0],
      });
      (data['edges'] as List).add({
        'id': 'isolated',
        'from': 'b-other-level',
        'to': 'd',
        'name': 'Окремий шлях',
        'bidirectional': true,
      });
      expect(
        () => RouteNetwork.parse(data).shortestPath('a', 'd'),
        throwsFormatException,
      );
    },
  );

  test('malformed and oversized networks are rejected before import', () {
    final invalid = <Json>[];
    Json changed(void Function(Json) mutate) {
      final n = exampleNetwork();
      mutate(n);
      return n;
    }

    invalid.addAll([
      {...exampleNetwork(), 'version': 2},
      {...exampleNetwork(), 'synthetic': 'false'},
      {...exampleNetwork(), 'nodes': []},
      {...exampleNetwork(), 'edges': []},
      changed((n) => (n['nodes'] as List).add((n['nodes'] as List).first)),
      changed((n) => (n['edges'] as List).add((n['edges'] as List).first)),
      changed((n) => n['edges'][0]['from'] = 'missing'),
      changed((n) => n['edges'][0]['to'] = 'a'),
      changed((n) => n['edges'][0]['bidirectional'] = 'yes'),
      changed((n) => n['nodes'][0]['coordinate'] = [0, double.nan]),
      changed((n) => n['nodes'][0]['coordinate'] = [181, 0]),
      changed(
        (n) => n['edges'][0]['via'] = List.filled(
          RouteNetwork.maxViaPoints + 1,
          [0, 0],
        ),
      ),
      changed((n) => n['nodes'] = List.filled(RouteNetwork.maxNodes + 1, {})),
      changed((n) => n['edges'] = List.filled(RouteNetwork.maxEdges + 1, {})),
      changed((n) {
        n['nodes'][0]['coordinate'] = [179, 0];
        n['nodes'][1]['coordinate'] = [-179, 0];
      }),
      changed((n) => n['nodes'][1]['coordinate'] = [0, 0]),
    ]);
    for (var i = 0; i < invalid.length; i++) {
      expect(
        () => RouteNetwork.parse(invalid[i]),
        throwsFormatException,
        reason: 'invalid case $i',
      );
    }
  });

  test(
    'route export carries full ordered geometry, provenance and direction',
    () {
      final network = RouteNetwork.parse(exampleNetwork());
      final route = network.shortestPath('c', 'a');
      final geoJson = route.toGeoJson(
        networkTitle: 'Джерело',
        license: 'Власні дані',
        synthetic: true,
      );
      final feature = (geoJson['features'] as List).single as Map;
      expect(feature['properties']['node_ids'], ['c', 'a']);
      expect(feature['properties']['edge_ids'], ['ac-detour']);
      expect(feature['properties']['license'], 'Власні дані');
      expect(feature['properties']['synthetic'], isTrue);
      expect(
        feature['geometry']['coordinates'],
        route.points.map((p) => p.toJson()).toList(),
      );
      expect(
        validateGeoJson(decodeObject(jsonEncode(geoJson)))['features'],
        hasLength(1),
      );
    },
  );

  test(
    'Dijkstra agrees with Floyd-Warshall on random directed multigraphs',
    () {
      final random = math.Random(734);
      for (var trial = 0; trial < 50; trial++) {
        const count = 10;
        final nodes = [
          for (var i = 0; i < count; i++)
            {
              'id': '$i',
              'name': 'Вузол $i',
              'coordinate': [random.nextDouble(), random.nextDouble()],
            },
        ];
        final edges = <Json>[];
        for (var i = 0; i < 28; i++) {
          final from = random.nextInt(count), to = random.nextInt(count);
          if (from == to) continue;
          edges.add({
            'id': '$i',
            'from': '$from',
            'to': '$to',
            'name': 'Ділянка $i',
            'bidirectional': random.nextBool(),
          });
        }
        final network = RouteNetwork.parse({
          'format': 'AMID_ROUTE_NETWORK',
          'version': 1,
          'synthetic': true,
          'nodes': nodes,
          'edges': edges,
        });
        final distances = List.generate(
          count,
          (i) => List.generate(count, (j) => i == j ? 0.0 : double.infinity),
        );
        for (final edge in network.edges) {
          final from = int.parse(edge.from), to = int.parse(edge.to);
          distances[from][to] = math.min(distances[from][to], edge.meters);
          if (edge.bidirectional) {
            distances[to][from] = math.min(distances[to][from], edge.meters);
          }
        }
        for (var k = 0; k < count; k++) {
          for (var i = 0; i < count; i++) {
            for (var j = 0; j < count; j++) {
              distances[i][j] = math.min(
                distances[i][j],
                distances[i][k] + distances[k][j],
              );
            }
          }
        }
        for (var i = 0; i < count; i++) {
          for (var j = 0; j < count; j++) {
            if (i == j) continue;
            if (!distances[i][j].isFinite) {
              expect(
                () => network.shortestPath('$i', '$j'),
                throwsFormatException,
              );
            } else {
              final result = network.shortestPath('$i', '$j');
              expect(result.meters, closeTo(distances[i][j], 1e-6));
              expect(result.nodes.first.id, '$i');
              expect(result.nodes.last.id, '$j');
              expect(
                result.legs
                    .map((l) => l.edge.meters)
                    .fold(0.0, (a, b) => a + b),
                closeTo(result.meters, 1e-6),
              );
            }
          }
        }
      }
    },
  );

  test(
    'a maximum-node chain reconstructs the complete path without recursion',
    () {
      const count = RouteNetwork.maxNodes;
      final network = RouteNetwork.parse({
        'format': 'AMID_ROUTE_NETWORK',
        'version': 1,
        'synthetic': true,
        'nodes': [
          for (var i = 0; i < count; i++)
            {
              'id': '$i',
              'name': 'N$i',
              'coordinate': [i / 100000, 0],
            },
        ],
        'edges': [
          for (var i = 1; i < count; i++)
            {
              'id': '$i',
              'from': '${i - 1}',
              'to': '$i',
              'name': 'E$i',
              'bidirectional': false,
            },
        ],
      });
      final result = network.shortestPath('0', '${count - 1}');
      expect(result.nodes, hasLength(count));
      expect(result.points, hasLength(count));
      expect(result.legs, hasLength(count - 1));
    },
  );
}
