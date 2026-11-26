import 'package:amid_offgrid/models/route_network.dart';
import 'package:amid_offgrid/services/map_lookup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'coordinates are local, bounded, and preserve longitude/latitude order',
    () {
      final point = coordinatePlace('50.059, 15.107')!;
      expect(point.point.latitude, 50.059);
      expect(point.point.longitude, 15.107);
      for (final query in ['NaN, 3', '91, 0', '50, 181', 'street']) {
        expect(coordinatePlace(query), isNull);
      }
      final places = MapLookup.parsePlaces({
        'features': [
          {
            'geometry': {
              'type': 'Point',
              'coordinates': [15.107, 50.059],
            },
            'properties': {
              'street': 'Pražská',
              'housenumber': '12',
              'city': 'Velim',
            },
          },
          {
            'geometry': {
              'type': 'Point',
              'coordinates': [500, 50],
            },
            'properties': {'name': 'Bad'},
          },
        ],
      });
      expect(places, hasLength(1));
      expect(places.single.name, 'Pražská 12');
    },
  );
  test(
    'routing rejects wrong geometry and distant snaps; exports a valid line',
    () {
      const from = MapPlace('A', RoutePoint(50.059, 15.107)),
          to = MapPlace('B', RoutePoint(50.060, 15.108));
      Map<String, dynamic> response(Object geometry) => {
        'code': 'Ok',
        'routes': [
          {'distance': 200, 'duration': 120, 'geometry': geometry},
        ],
      };
      final geometry = {
        'type': 'LineString',
        'coordinates': [
          [15.107, 50.059],
          [15.108, 50.060],
        ],
      };
      final route = RoadDirections.parse(response(geometry), from, to, 'foot');
      expect(route.geoJson['features'][0]['geometry'], geometry);
      expect(route.meters, 200);
      expect(
        () => RoadDirections.parse(
          response({
            'type': 'LineString',
            'coordinates': [
              [0, 0],
              [1, 1],
            ],
          }),
          from,
          to,
          'foot',
        ),
        throwsFormatException,
      );
      expect(
        () => RoadDirections.parse(
          response({
            'type': 'Point',
            'coordinates': [15, 50],
          }),
          from,
          to,
          'foot',
        ),
        throwsFormatException,
      );
    },
  );
}
