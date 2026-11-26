import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import '../models/street_map.dart';
import '../models/route_network.dart';
import '../services/map_lookup.dart';
import '../widgets/street_style.dart';
import '../widgets/street_credits.dart';
import '../widgets/street_layers_sheet.dart';
import '../services/services.dart';
import '../widgets/common.dart';
import '../widgets/offline_tiles_native.dart'
    if (dart.library.js_interop) '../widgets/offline_tiles_web.dart';
import 'route_planner.dart';
import 'catalog_screen.dart';
import 'place_search_screen.dart';
import 'road_directions_screen.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.services, required this.navigate});
  final Services services;
  final void Function(int) navigate;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = MapController();
  final _scroll = ScrollController();
  Json? _world;
  String? _error;
  String _selected = '';
  bool _ready = false, _locating = false;
  LatLng? _position;
  double? _accuracy;
  MapRouteSelection? _route;
  RoadDirections? _roadRoute;
  final _vectorController = vt.VectorTileLayerController();
  vt.Theme? _vectorTheme;
  String _vectorThemeId = '', _viewFingerprint = '', _lastStreetMode = '';
  vt.VectorTileProvider? _lastProvider;
  vt.TileProviders? _providers;
  bool _outside = false;
  bool _desiredOutside = false, _outsideScheduled = false;
  bool _roadSaving = false, _roadSaved = false;
  String _lastPlaceName = '';

  @override
  void initState() {
    super.initState();
    _selected = widget.services.store.selectedMap;
    _loadWorld();
    widget.services.streets.addListener(_streetChanged);
    unawaited(
      widget.services.streets.selectMode(
        _map == null ? widget.services.store.streetMode : 'overview',
      ),
    );
  }

  Future<void> _loadWorld() async {
    try {
      final data = jsonDecode(
        await rootBundle.loadString('assets/world.geojson'),
      ) as Json;
      if (mounted) setState(() => _world = data);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Json? get _map => widget.services.store.packs
      .where(
        (p) =>
            p['id'] == widget.services.store.selectedMap && p['kind'] == 'map',
      )
      .firstOrNull;
  @override
  void didUpdateWidget(covariant MapScreen old) {
    super.didUpdateWidget(old);
    if (_route != null && !_routeAvailable(_route!)) _route = null;
    if (_selected != widget.services.store.selectedMap) {
      _selected = widget.services.store.selectedMap;
      if (_map != null) {
        unawaited(widget.services.streets.selectMode('overview'));
      }
      WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    }
  }

  bool _routeAvailable(MapRouteSelection route) =>
      widget.services.store.packs.any(
        (p) =>
            p['id'] == route.packId && identical(p['routing'], route.network),
      );

  Future<void> _planRoute() async {
    final route = await Navigator.push<MapRouteSelection>(
      context,
      MaterialPageRoute(
        builder: (_) => RoutePlannerScreen(services: widget.services),
      ),
    );
    if (!mounted || route == null || !_routeAvailable(route)) return;
    setState(() {
      _route = route;
      _roadRoute = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitRoute();
    });
  }

  StreetRegion? get _region => widget.services.store.streetRegions
      .where((r) => r.id == widget.services.streets.mode)
      .firstOrNull;

  void _streetChanged() {
    final s = widget.services.streets;
    final next =
        '${s.mode}|${s.provider?.cacheKey}|${s.loading}|${s.error}|${s.busy}';
    if (next == _viewFingerprint || !mounted) return;
    final changedMode = _lastStreetMode != s.mode;
    _lastStreetMode = s.mode;
    _viewFingerprint = next;
    setState(() {});
    if (changedMode && _region != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    }
  }

  Future<void> _chooseLayer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .86,
        child: StreetLayersSheet(
          streets: widget.services.streets,
          select: (mode) async {
            Navigator.pop(sheet);
            await widget.services.store.selectMap('');
            await widget.services.streets.selectMode(mode);
          },
          download: () {
            Navigator.pop(sheet);
            guarded(context, _downloadArea);
          },
          catalog: () {
            Navigator.pop(sheet);
            Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CatalogScreen(services: widget.services),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _downloadArea() async {
    if (!_ready) return;
    final visible = _controller.camera.visibleBounds;
    double wrap(double value) => (value + 180) % 360 - 180;
    final wholeWorld = visible.east - visible.west >= 360;
    final bounds = StreetBounds(
      wholeWorld ? -180 : wrap(visible.west),
      visible.south.clamp(-85.05112878, 85.05112878),
      wholeWorld ? 180 : wrap(visible.east),
      visible.north.clamp(-85.05112878, 85.05112878),
    );
    final name = TextEditingController(
      text: _lastPlaceName.isEmpty
          ? 'Моя область ${widget.services.store.streetRegions.length + 1}'
          : _lastPlaceName,
    );
    var zoom = 15;
    (String, int)? choice;
    try {
      choice = await showDialog<(String, int)>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            String? problem;
            int count = 0;
            try {
              count = bounds.tiles(zoom).length;
            } on FormatException catch (e) {
              problem = e.message.toString();
            }
            return AlertDialog(
              title: const Text('Зберегти область'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 80,
                      decoration: const InputDecoration(labelText: 'Назва'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Деталізація: $zoom${zoom == 15 ? ' · вулиці й будівлі' : ''}',
                    ),
                    Slider(
                      value: zoom.toDouble(),
                      min: 10,
                      max: 15,
                      divisions: 5,
                      onChanged: (v) => update(() => zoom = v.round()),
                    ),
                    Text(
                      problem ??
                          '$count тайлів · до 50 MiB. Точний розмір залежить від щільності забудови.',
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Зберігається видимий прямокутник у всіх масштабах до вибраного. Якщо область завелика — скасуй і наблизь карту.',
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Назад'),
                ),
                FilledButton(
                  onPressed: problem == null
                      ? () => Navigator.pop(context, (name.text, zoom))
                      : null,
                  child: const Text('Завантажити'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      name.dispose();
    }
    if (choice == null) return;
    final previousMap = widget.services.store.selectedMap;
    await widget.services.streets.download(bounds, choice.$2, choice.$1);
    if (mounted &&
        _region != null &&
        widget.services.store.selectedMap == previousMap) {
      await widget.services.store.selectMap('');
    }
    if (mounted) {
      toast(context, 'Область готова. Її вулиці доступні без мережі.');
    }
  }

  Future<void> _searchPlace() async {
    final place = await Navigator.push<MapPlace>(
      context,
      MaterialPageRoute(
        builder: (_) => PlaceSearchScreen(store: widget.services.store),
      ),
    );
    if (!mounted || place == null) return;
    _lastPlaceName = String.fromCharCodes(place.name.runes.take(80));
    if (place.regionId != null) {
      await widget.services.store.selectMap('');
      await widget.services.streets.selectMode(place.regionId!);
    } else if (_ready) {
      _controller.move(
        LatLng(
          place.point.latitude.clamp(-85.05, 85.05),
          place.point.longitude,
        ),
        16,
      );
    }
  }

  void _showFeature(Offset? offset, LatLng point) {
    if (offset == null) return;
    final hits = _vectorController.queryRenderedFeatures(offset);
    if (hits.isEmpty) return;
    final p = hits.first.properties;
    final rawName =
        p['name:uk'] ??
        p['name:en'] ??
        p['name'] ??
        (p['addr_housenumber'] == null
            ? p['kind_detail'] ?? p['kind'] ?? 'Місце на карті'
            : 'Будинок ${p['addr_housenumber']}');
    final title = String.fromCharCodes(rawName.toString().runes.take(160));
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              SelectableText(
                '${point.latitude.toStringAsFixed(6)}, ${point.longitude.toStringAsFixed(6)}',
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  Navigator.pop(sheet);
                  guarded(
                    context,
                    () => _add(
                      at: point,
                      initialName: String.fromCharCodes(title.runes.take(80)),
                    ),
                  );
                },
                icon: const Icon(Icons.add_location_alt_outlined),
                label: const Text('Зберегти точку'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _chooseRoute() async {
    final online = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.route),
              title: const Text('По дорогах онлайн'),
              subtitle: const Text(
                'Пішки, велосипед або авто · збереження результату',
              ),
              onTap: () => Navigator.pop(context, true),
            ),
            ListTile(
              leading: const Icon(Icons.offline_pin_outlined),
              title: const Text('Офлайн з мережі маршруту'),
              subtitle: const Text('Для імпортованих мереж AMID'),
              onTap: () => Navigator.pop(context, false),
            ),
          ],
        ),
      ),
    );
    if (!mounted || online == null) return;
    if (!online) {
      await _planRoute();
      return;
    }
    final route = await Navigator.push<RoadDirections>(
      context,
      MaterialPageRoute(
        builder: (_) => RoadDirectionsScreen(
          store: widget.services.store,
          initialFrom: _position == null
              ? null
              : MapPlace(
                  'Моя GPS-позиція',
                  RoutePoint(_position!.latitude, _position!.longitude),
                ),
        ),
      ),
    );
    if (!mounted || route == null) return;
    setState(() {
      _roadRoute = route;
      _route = null;
      _roadSaved = false;
    });
    _fitRoad(route);
  }

  void _fitRoad(RoadDirections route) {
    if (!_ready || !mounted) return;
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          route.points
              .map((p) => LatLng(p.latitude.clamp(-85.05, 85.05), p.longitude))
              .toList(),
        ),
        padding: const EdgeInsets.all(45),
        maxZoom: 17,
      ),
    );
  }

  Widget _roadSummary(RoadDirections route) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${route.from.name} → ${route.to.name}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '${routeDistance(route.meters)} · близько ${(route.seconds / 60).ceil()} хв · FOSSGIS / OSM',
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () => _fitRoad(route),
              icon: const Icon(Icons.center_focus_strong),
              label: const Text('До маршруту'),
            ),
            TextButton.icon(
              onPressed: _roadSaving || _roadSaved
                  ? null
                  : () => guarded(context, () => _saveRoad(route)),
              icon: Icon(_roadSaved ? Icons.offline_pin : Icons.save_alt),
              label: Text(_roadSaved ? 'Збережено' : 'Зберегти маршрут'),
            ),
            TextButton.icon(
              onPressed: () => guarded(
                context,
                () => widget.services.files.exportRoute(route.geoJson),
              ),
              icon: const Icon(Icons.ios_share),
              label: const Text('GeoJSON'),
            ),
            IconButton(
              tooltip: 'Прибрати дорожній маршрут',
              onPressed: () => setState(() => _roadRoute = null),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const Text(
          'Для офлайн-перегляду вулиць уздовж маршруту збережи відповідну область карти.',
          style: TextStyle(fontSize: 12),
        ),
        const StreetCredits(routing: true),
      ],
    ),
  );

  Future<void> _saveRoad(RoadDirections route) async {
    if (_roadSaving) return;
    setState(() => _roadSaving = true);
    try {
      final title = String.fromCharCodes(
        '${route.from.name} → ${route.to.name}'.runes.take(120),
      );
      final pack = parsePack({
        'format': 'AMID_OFFGRID_PACK',
        'version': 1,
        'id': 'route-${const Uuid().v4()}',
        'title': title,
        'license': 'OpenStreetMap ODbL · FOSSGIS routing',
        'map': route.geoJson,
        'articles': [
          {
            'id': 'route',
            'title': title,
            'category': 'Маршрути',
            'body':
                '${routeDistance(route.meters)}. Орієнтовно ${(route.seconds / 60).ceil()} хв.\nЗбережений розрахунок FOSSGIS / OpenStreetMap. Без автоматичного перерахунку та даних про поточні перекриття.',
            'source': 'https://routing.openstreetmap.de/',
          },
        ],
      });
      await widget.services.store.importKnowledge(pack);
      if (mounted && identical(_roadRoute, route)) {
        setState(() => _roadSaved = true);
      }
    } finally {
      if (mounted) setState(() => _roadSaving = false);
    }
  }

  void _fitRoute() {
    if (!mounted || !_ready || _route == null) return;
    _controller.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(
          _route!.route.points
              .map((p) => LatLng(p.latitude.clamp(-85.05, 85.05), p.longitude))
              .toList(),
        ),
        padding: const EdgeInsets.all(50),
        maxZoom: 17,
      ),
    );
  }

  void _center() {
    if (!mounted || !_ready) return;
    final region = _region;
    if (region != null) {
      final b = region.bounds;
      if (b.west <= b.east) {
        _controller.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds(
              LatLng(b.south, b.west),
              LatLng(b.north, b.east),
            ),
            padding: const EdgeInsets.all(35),
            maxZoom: 17,
          ),
        );
      } else {
        _controller.move(
          LatLng(b.centerLatitude, b.centerLongitude),
          (region.maxZoom - 3).toDouble(),
        );
      }
      return;
    }
    final c = _map?['center'];
    if (c is List && c.length == 3) {
      _controller.move(
        LatLng((c[0] as num).toDouble(), (c[1] as num).toDouble()),
        (c[2] as num).toDouble(),
      );
    } else {
      _controller.move(const LatLng(48.5, 21), 4);
    }
  }

  LatLng _point(List<dynamic> c) => LatLng(
    (c[1] as num).toDouble().clamp(-85.05, 85.05),
    (c[0] as num).toDouble(),
  );
  void _features(
    Json data,
    List<Polygon> polygons,
    List<Polyline> lines,
    List<Marker> markers, {
    bool world = false,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    for (final raw in data['features'] as List) {
      final f = raw as Map, g = f['geometry'];
      if (g is! Map) continue;
      final c = g['coordinates'];
      void polygon(List<dynamic> rings) {
        if (rings.isEmpty) return;
        polygons.add(
          Polygon(
            points: (rings.first as List)
                .map((e) => _point(e as List))
                .toList(),
            holePointsList: rings
                .skip(1)
                .map((r) => (r as List).map((e) => _point(e as List)).toList())
                .toList(),
            color: world
                ? (dark ? const Color(0xff345347) : const Color(0xffdce7c7))
                : amber.withValues(alpha: .3),
            borderColor: world
                ? (dark ? const Color(0xff71917a) : const Color(0xff879b72))
                : const Color(0xffd69b48),
            borderStrokeWidth: world ? 0.65 : 1.6,
          ),
        );
      }

      switch (g['type']) {
        case 'Polygon':
          polygon(c as List);
        case 'MultiPolygon':
          for (final p in c as List) {
            polygon(p as List);
          }
        case 'LineString':
          lines.add(
            Polyline(
              points: (c as List).map((e) => _point(e as List)).toList(),
              color: const Color(0xffd69b48),
              strokeWidth: 3,
            ),
          );
        case 'MultiLineString':
          for (final l in c as List) {
            lines.add(
              Polyline(
                points: (l as List).map((e) => _point(e as List)).toList(),
                color: const Color(0xffd69b48),
                strokeWidth: 3,
              ),
            );
          }
        case 'Point':
          markers.add(
            Marker(
              point: _point(c as List),
              width: 32,
              height: 36,
              child: Tooltip(
                message:
                    '${f['properties']?['name'] ?? f['properties']?['NAME'] ?? 'Точка GeoJSON'}',
                child: const Icon(
                  Icons.location_on_rounded,
                  color: Color(0xffdfaa63),
                  size: 30,
                ),
              ),
            ),
          );
      }
    }
  }

  Future<void> _locate() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Увімкни геолокацію на пристрої.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Надай доступ до місцезнаходження у налаштуваннях.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 25),
        ),
      );
      if (!mounted) return;
      setState(() {
        _position = LatLng(p.latitude, p.longitude);
        _accuracy = p.accuracy;
      });
      if (_ready) _controller.move(_position!, 14);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _add({LatLng? at, Pin? existing, String? initialName}) async {
    final name = TextEditingController(
          text: existing?.name ?? initialName ?? '',
        ),
        lat = TextEditingController(
          text:
              existing?.latitude.toStringAsFixed(6) ??
              at?.latitude.toStringAsFixed(6) ??
              '',
        ),
        lon = TextEditingController(
          text:
              existing?.longitude.toStringAsFixed(6) ??
              at?.longitude.toStringAsFixed(6) ??
              '',
        );
    try {
      final pin = await showDialog<Pin>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, update) {
            return AlertDialog(
              title: Text(existing == null ? 'Нова точка' : 'Редагувати точку'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: name,
                      maxLength: 100,
                      decoration: const InputDecoration(labelText: 'Назва'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lat,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Широта · −90…90',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: lon,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Довгота · −180…180',
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Скасувати'),
                ),
                FilledButton(
                  onPressed: () {
                    try {
                      final p = Pin.fromJson({
                        'id': existing?.id ?? const Uuid().v4(),
                        'name': name.text.trim(),
                        'latitude': double.tryParse(
                          lat.text.replaceAll(',', '.'),
                        ),
                        'longitude': double.tryParse(
                          lon.text.replaceAll(',', '.'),
                        ),
                      });
                      Navigator.pop(context, p);
                    } catch (_) {
                      toast(context, 'Вкажи назву й коректні координати.');
                    }
                  },
                  child: const Text('Зберегти'),
                ),
              ],
            );
          },
        ),
      );
      if (pin != null) await widget.services.store.savePin(pin);
    } finally {
      name.dispose();
      lat.dispose();
      lon.dispose();
    }
  }

  void _showPin(Pin p) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 5, 24, 25),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(
              p.text,
              style: const TextStyle(fontSize: 18, height: 1.7),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: () => guarded(context, () async {
                await widget.services.store.setDraft(p.text);
                if (context.mounted) Navigator.pop(context);
                widget.navigate(4);
              }),
              icon: const Icon(Icons.chat_bubble_outline_rounded),
              label: const Text('Передати координати'),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                guarded(this.context, () => _add(existing: p));
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Редагувати точку'),
            ),
            TextButton.icon(
              onPressed: () => guarded(context, () async {
                await widget.services.store.deletePin(p.id);
                if (context.mounted) Navigator.pop(context);
              }),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Видалити точку'),
            ),
          ],
        ),
      ),
    ),
  );
  @override
  void dispose() {
    widget.services.streets.removeListener(_streetChanged);
    _scroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>[], lines = <Polyline>[], markers = <Marker>[];
    final route = _route;
    if (_world != null) {
      _features(_world!, polygons, lines, markers, world: true);
    }
    for (final p in widget.services.store.packs) {
      if (p['map'] is Map) {
        _features(Json.from(p['map'] as Map), polygons, lines, markers);
      }
    }
    for (final p in widget.services.store.pins) {
      markers.add(
        Marker(
          point: LatLng(p.latitude, p.longitude),
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: p.name,
            onPressed: () => _showPin(p),
            icon: const Icon(
              Icons.location_on_rounded,
              color: Color(0xfff2c58f),
              size: 34,
            ),
          ),
        ),
      );
    }
    if (route != null) {
      lines.add(
        Polyline(
          points: route.route.points
              .map((p) => LatLng(p.latitude.clamp(-85.05, 85.05), p.longitude))
              .toList(),
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 6,
        ),
      );
      for (final entry in [
        (route.route.nodes.first, 'A'),
        (route.route.nodes.last, 'B'),
      ]) {
        markers.add(
          Marker(
            point: LatLng(
              entry.$1.point.latitude.clamp(-85.05, 85.05),
              entry.$1.point.longitude,
            ),
            width: 38,
            height: 38,
            child: Tooltip(
              message: entry.$1.name,
              child: CircleAvatar(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                child: Text(entry.$2),
              ),
            ),
          ),
        );
      }
    }
    if (_position != null) {
      markers.add(
        Marker(
          point: _position!,
          width: 28,
          height: 28,
          child: const Icon(
            Icons.my_location_rounded,
            color: Color(0xff69b5ff),
          ),
        ),
      );
    }
    final streets = widget.services.streets, map = _map;
    final themeId =
        '${widget.services.store.themeStyle}-${Theme.of(context).brightness.name}';
    if (_vectorThemeId != themeId) {
      _vectorThemeId = themeId;
      _vectorTheme = streetTheme(Theme.of(context).colorScheme, themeId);
    }
    if (!identical(_lastProvider, streets.provider)) {
      _lastProvider = streets.provider;
      _providers = streets.provider == null
          ? null
          : vt.TileProviders({'streets': streets.provider!});
    }
    final roadRoute = _roadRoute;
    if (roadRoute != null) {
      lines.add(
        Polyline(
          points: roadRoute.points
              .map((p) => LatLng(p.latitude.clamp(-85.05, 85.05), p.longitude))
              .toList(),
          color: Theme.of(context).colorScheme.primary,
          strokeWidth: 6,
        ),
      );
    }

    final content = Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Карта',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _region?.title ??
                          (streets.mode == 'online'
                              ? 'Вулиці, дороги та стежки · онлайн'
                              : map?['title'] as String? ??
                                    'Оглядова карта світу · без вулиць'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Шари карти й офлайн-області',
                onPressed: _chooseLayer,
                icon: const Icon(Icons.layers_outlined),
              ),
              IconButton(
                tooltip: 'Побудувати маршрут',
                onPressed: () => guarded(context, _chooseRoute),
                icon: const Icon(Icons.route_outlined),
              ),
              IconButton(
                tooltip: 'Додати точку за координатами',
                onPressed: () => guarded(context, () => _add()),
                icon: const Icon(Icons.add_location_alt_outlined),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _searchPlace,
              icon: const Icon(Icons.search),
              label: const Text('Місце, вулиця або координати'),
            ),
          ),
        ),
        if (streets.loading) const LinearProgressIndicator(),
        if (streets.error != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(streets.error!),
                TextButton(
                  onPressed: () => streets.selectMode(streets.mode),
                  child: const Text('Повторити'),
                ),
              ],
            ),
          ),
        ListenableBuilder(
          listenable: streets,
          builder: (context, _) => streets.busy
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Column(
                    children: [
                      LinearProgressIndicator(value: streets.progress),
                      Row(
                        children: [
                          Expanded(child: Text(streets.label)),
                          IconButton(
                            tooltip: 'Скасувати завантаження області',
                            onPressed: streets.cancelDownload,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                )
              : const SizedBox.shrink(),
        ),
        if (roadRoute != null) _roadSummary(roadRoute),
        if (route != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${route.route.nodes.first.name} → ${route.route.nodes.last.name}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${routeDistance(route.route.meters)} · ${route.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (route.synthetic)
                  const Text('Навчальна мережа · не справжні дороги'),
                Wrap(
                  spacing: 8,
                  children: [
                    TextButton.icon(
                      onPressed: _fitRoute,
                      icon: const Icon(Icons.center_focus_strong),
                      label: const Text('До маршруту'),
                    ),
                    ListenableBuilder(
                      listenable: widget.services.files,
                      builder: (context, _) => TextButton.icon(
                        onPressed: widget.services.files.busy
                            ? null
                            : () => guarded(
                                context,
                                () => widget.services.files.exportRoute(
                                  route.geoJson,
                                ),
                              ),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('GeoJSON'),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Прибрати маршрут',
                      onPressed: () => setState(() => _route = null),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _controller,
                  options: MapOptions(
                    initialCenter: const LatLng(48.5, 21),
                    initialZoom: 4,
                    minZoom: 0,
                    maxZoom: 24,
                    backgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xff1b343b)
                        : const Color(0xffc8dce1),
                    onMapReady: () {
                      _ready = true;
                      _center();
                    },
                    onLongPress: (_, p) => guarded(context, () => _add(at: p)),
                    onTap: (tap, point) => _showFeature(tap.relative, point),
                    onPositionChanged: (camera, _) {
                      final b = _region?.bounds, c = camera.center;
                      final outside =
                          b != null &&
                          (c.latitude < b.south ||
                              c.latitude > b.north ||
                              (b.west <= b.east
                                  ? c.longitude < b.west || c.longitude > b.east
                                  : c.longitude < b.west &&
                                        c.longitude > b.east));
                      _desiredOutside = outside;
                      if (!_outsideScheduled && outside != _outside) {
                        _outsideScheduled = true;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _outsideScheduled = false;
                          if (mounted && _outside != _desiredOutside) {
                            setState(() => _outside = _desiredOutside);
                          }
                        });
                      }
                    },
                  ),
                  children: [
                    PolygonLayer(polygons: polygons),
                    if (_providers != null && _vectorTheme != null)
                      vt.VectorTileLayer(
                        key: ValueKey(streets.provider!.cacheKey),
                        theme: _vectorTheme!,
                        tileProviders: _providers!,
                        controller: _vectorController,
                        concurrency: 2,
                        diskCacheMaximumSizeInBytes: 0,
                        retainAllProperties: true,
                      ),
                    if (map != null && !kIsWeb)
                      OfflineTiles(
                        key: ValueKey(map['path']),
                        path: map['path'] as String,
                      ),
                    PolylineLayer(polylines: lines),
                    MarkerLayer(markers: markers),
                  ],
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: Column(
                    children: [
                      IconButton.filledTonal(
                        tooltip: 'Моя позиція GPS',
                        onPressed: _locating
                            ? null
                            : () => guarded(context, _locate),
                        icon: _locating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded),
                      ),
                      const SizedBox(height: 8),
                      IconButton.filledTonal(
                        tooltip: 'Збільшити карту',
                        onPressed: () => _controller.move(
                          _controller.camera.center,
                          (_controller.camera.zoom + 1).clamp(1, 20),
                        ),
                        icon: const Icon(Icons.add_rounded),
                      ),
                      const SizedBox(height: 8),
                      IconButton.filledTonal(
                        tooltip: 'Зменшити карту',
                        onPressed: () => _controller.move(
                          _controller.camera.center,
                          (_controller.camera.zoom - 1).clamp(1, 20),
                        ),
                        icon: const Icon(Icons.remove_rounded),
                      ),
                      const SizedBox(height: 8),
                      IconButton.filledTonal(
                        tooltip: 'До області карти',
                        onPressed: _center,
                        icon: const Icon(Icons.center_focus_strong_rounded),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 65,
                  bottom: 12,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(9),
                      child: Text(
                        _error ??
                            (_providers != null
                                    ? '$streetAttribution${_region != null && _outside ? ' · Поза збереженою областю' : ''}'
                                    : map != null
                                    ? '${map['attribution']}'
                                    : 'Natural Earth · public domain\\nУтримай карту, щоб зберегти точку.')
                                .replaceAll(r'\n', '\n'),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_accuracy != null)
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              'Оцінка точності позиції: ±${_accuracy!.round()} м',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        if (widget.services.store.pins.isNotEmpty)
          SizedBox(
            height: 72,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              itemCount: widget.services.store.pins.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final p = widget.services.store.pins[i];
                return ActionChip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(p.name),
                  onPressed: () {
                    _controller.move(LatLng(p.latitude, p.longitude), 14);
                    _showPin(p);
                  },
                );
              },
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(14),
            child: Text(
              'У шарах карти можна зберегти область з вулицями. Утримай карту, щоб додати точку.',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final scale = [12.0, 16.0, 22.0]
            .map((size) => scaler.scale(size) / size)
            .reduce((a, b) => a > b ? a : b);
        final minimum =
            (480 +
                (route == null && roadRoute == null ? 0 : 210) +
                (streets.error == null ? 0 : 100) +
                (streets.busy ? 80 : 0)) *
            scale;
        if (constraints.maxHeight >= minimum) return content;
        return Scrollbar(
          controller: _scroll,
          thumbVisibility: true,
          interactive: true,
          child: SingleChildScrollView(
            controller: _scroll,
            child: SizedBox(height: minimum, child: content),
          ),
        );
      },
    );
  }
}
