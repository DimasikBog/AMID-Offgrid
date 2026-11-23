import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';
import '../widgets/offline_tiles_native.dart'
    if (dart.library.js_interop) '../widgets/offline_tiles_web.dart';
import 'route_planner.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.services, required this.navigate});
  final Services services;
  final void Function(int) navigate;
  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final _controller = MapController();
  Json? _world;
  String? _error;
  String _selected = '';
  bool _ready = false, _locating = false;
  LatLng? _position;
  double? _accuracy;
  MapRouteSelection? _route;
  @override
  void initState() {
    super.initState();
    _selected = widget.services.store.selectedMap;
    _loadWorld();
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
    setState(() => _route = route);
    _fitRoute();
  }

  void _fitRoute() {
    if (!_ready || _route == null) return;
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
                message: '${f['properties']?['name'] ?? 'Точка GeoJSON'}',
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
        throw StateError('Увімкни геолокацію на телефоні.');
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

  Future<void> _add({LatLng? at, Pin? existing}) async {
    final name = TextEditingController(text: existing?.name ?? ''),
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
    final map = _map;
    return Column(
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
                      'Карта без мережі',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      map?['title'] as String? ??
                          'Оглядова карта світу · без вулиць',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Побудувати офлайн-маршрут',
                onPressed: () => guarded(context, _planRoute),
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
                  ),
                  children: [
                    PolygonLayer(polygons: polygons),
                    if (map != null && !kIsWeb)
                      OfflineTiles(
                        key: ValueKey(map['path']),
                        path: map['path'] as String,
                        minZoom: (map['minZoom'] as num? ?? 0).toDouble(),
                        maxZoom: (map['maxZoom'] as num? ?? 20).toDouble(),
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
                            (map != null
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
              'Детальні карти додавай у «Пакетах» як MBTiles.',
              style: TextStyle(fontSize: 12),
            ),
          ),
      ],
    );
  }
}
