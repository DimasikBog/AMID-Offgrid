import 'package:flutter/material.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;

/// A bundled style: no remote styles, sprites or fonts needed offline.
vt.Theme streetTheme(ColorScheme scheme, String id) {
  final dark = scheme.brightness == Brightness.dark;
  String hex(Color c) =>
      '#${c.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
  final text = hex(scheme.onSurface), accent = hex(scheme.primary);
  final earth = dark ? '#18232a' : '#f5f2e8',
      water = dark ? '#102e42' : '#b8d8e9';
  final green = dark ? '#223c31' : '#d8e6c8',
      casing = dark ? '#344753' : '#c8c1af';
  final road = dark ? '#889ea9' : '#ffffff',
      major = dark ? '#d1b67b' : '#f5cc78';
  final name = [
    'coalesce',
    ['get', 'name:uk'],
    ['get', 'name:en'],
    ['get', 'name'],
  ];
  Map<String, Object?> layer(
    String name,
    String type,
    String source,
    Map<String, Object?> paint, {
    Object? filter,
    num minZoom = 0,
    Map<String, Object?>? layout,
  }) => {
    'id': name,
    'type': type,
    'source': 'streets',
    'source-layer': source,
    'minzoom': minZoom,
    'paint': paint,
    'filter': ?filter,
    'layout': ?layout,
  };
  Object roadWidth(num scale) => [
    'interpolate',
    ['linear'],
    ['zoom'],
    5,
    .5 * scale,
    12,
    2 * scale,
    16,
    7 * scale,
    20,
    18 * scale,
  ];
  final labels = <String, Object?>{
    'text-field': name,
    'text-font': ['Roboto'],
    'text-size': [
      'interpolate',
      ['linear'],
      ['zoom'],
      4,
      11,
      14,
      13,
      20,
      16,
    ],
  };
  final labelPaint = <String, Object?>{
    'text-color': text,
    'text-halo-color': earth,
    'text-halo-width': 1.5,
  };
  return const vt.ThemeReader().read({
    'version': 8,
    'name': 'AMID Streets',
    'sources': {
      'streets': {'type': 'vector'},
    },
    'layers': [
      {
        'id': 'background',
        'type': 'background',
        'paint': {'background-color': water},
      },
      layer('earth', 'fill', 'earth', {'fill-color': earth}),
      layer(
        'landcover',
        'fill',
        'landcover',
        {'fill-color': green},
        filter: ['in', 'kind', 'forest', 'grassland', 'scrub'],
      ),
      layer(
        'parks',
        'fill',
        'landuse',
        {'fill-color': green},
        filter: [
          'in',
          'kind',
          'forest',
          'wood',
          'park',
          'garden',
          'grass',
          'nature_reserve',
          'recreation_ground',
        ],
      ),
      layer(
        'urban',
        'fill',
        'landuse',
        {'fill-color': dark ? '#293038' : '#eee8dc'},
        filter: ['in', 'kind', 'residential', 'industrial', 'commercial'],
      ),
      layer(
        'water',
        'fill',
        'water',
        {'fill-color': water},
        filter: ['==', r'$type', 'Polygon'],
      ),
      layer(
        'streams',
        'line',
        'water',
        {
          'line-color': water,
          'line-width': [
            'interpolate',
            ['linear'],
            ['zoom'],
            10,
            1,
            18,
            5,
          ],
        },
        filter: ['==', r'$type', 'LineString'],
      ),
      layer(
        'buildings',
        'fill',
        'buildings',
        {
          'fill-color': dark ? '#43505a' : '#d4c7b7',
          'fill-outline-color': dark ? '#56636c' : '#bcaf9f',
        },
        filter: ['==', r'$type', 'Polygon'],
        minZoom: 13,
      ),
      layer(
        'road-casings',
        'line',
        'roads',
        {'line-color': casing, 'line-width': roadWidth(1.35)},
        filter: ['in', 'kind', 'highway', 'major_road', 'minor_road'],
        layout: {'line-cap': 'round', 'line-join': 'round'},
      ),
      layer(
        'roads',
        'line',
        'roads',
        {'line-color': road, 'line-width': roadWidth(1)},
        filter: ['in', 'kind', 'highway', 'major_road', 'minor_road'],
        layout: {'line-cap': 'round', 'line-join': 'round'},
      ),
      layer(
        'major-roads',
        'line',
        'roads',
        {'line-color': major, 'line-width': roadWidth(1.1)},
        filter: ['in', 'kind', 'highway', 'major_road'],
        layout: {'line-cap': 'round', 'line-join': 'round'},
      ),
      layer(
        'paths',
        'line',
        'roads',
        {
          'line-color': dark ? '#edbd8d' : '#a77a4a',
          'line-width': roadWidth(.3),
          'line-dasharray': [3, 2],
        },
        filter: ['==', 'kind', 'path'],
        minZoom: 11,
      ),
      layer(
        'rail',
        'line',
        'roads',
        {
          'line-color': dark ? '#a5afb8' : '#787f85',
          'line-width': roadWidth(.4),
          'line-dasharray': [4, 2],
        },
        filter: ['==', 'kind', 'rail'],
        minZoom: 10,
      ),
      layer('boundaries', 'line', 'boundaries', {
        'line-color': dark ? '#71839c' : '#9e8caa',
        'line-width': 1,
        'line-dasharray': [4, 4],
      }),
      layer(
        'road-names',
        'symbol',
        'roads',
        labelPaint,
        filter: ['in', 'kind', 'major_road', 'minor_road', 'path'],
        minZoom: 13,
        layout: {
          ...labels,
          'symbol-placement': 'line',
          'text-size': 12,
          'symbol-spacing': 180,
        },
      ),
      layer(
        'house-numbers',
        'symbol',
        'buildings',
        labelPaint,
        filter: ['==', 'kind', 'address'],
        minZoom: 17,
        layout: {
          ...labels,
          'text-field': ['get', 'addr_housenumber'],
          'text-size': 10,
        },
      ),
      layer('poi-dots', 'circle', 'pois', {
        'circle-color': accent,
        'circle-radius': 2,
        'circle-stroke-color': earth,
        'circle-stroke-width': 1,
      }, minZoom: 15),
      layer(
        'poi-names',
        'symbol',
        'pois',
        labelPaint,
        minZoom: 15,
        layout: {
          ...labels,
          'text-size': 11,
          'text-anchor': 'top',
          'text-offset': [0, .7],
          'text-max-width': 10,
        },
      ),
      layer(
        'place-names',
        'symbol',
        'places',
        labelPaint,
        layout: {
          ...labels,
          'text-size': [
            'interpolate',
            ['linear'],
            ['zoom'],
            4,
            12,
            10,
            15,
            16,
            18,
          ],
        },
      ),
    ],
  }, id: id);
}
