import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/route_network.dart';
import '../services/services.dart';
import 'packs_screen.dart';

typedef RouteCalculator = Future<OfflineRoute> Function(Json request);

String routeDistance(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(2)} км'
    : '${meters.round()} м';

class MapRouteSelection {
  const MapRouteSelection(
    this.packId,
    this.title,
    this.license,
    this.network,
    this.route,
  );
  final String packId, title, license;
  final Json network;
  final OfflineRoute route;
  bool get synthetic => network['synthetic'] as bool;
  Json get geoJson => route.toGeoJson(
    networkTitle: title,
    license: license,
    synthetic: synthetic,
  );
}

class RoutePlannerScreen extends StatefulWidget {
  const RoutePlannerScreen({super.key, required this.services, this.calculate});
  final Services services;
  final RouteCalculator? calculate;
  @override
  State<RoutePlannerScreen> createState() => _RoutePlannerScreenState();
}

class _RoutePlannerScreenState extends State<RoutePlannerScreen> {
  String? _packId, _from, _to, _error;
  Json? _network;
  List<RouteNode> _nodes = [];
  OfflineRoute? _result;
  bool _busy = false;
  int _request = 0;

  List<Json> get _packs =>
      widget.services.store.packs.where((p) => p['routing'] is Map).toList();
  Json? get _pack => _packs.where((p) => p['id'] == _packId).firstOrNull;

  @override
  void initState() {
    super.initState();
    _load(_packs.firstOrNull);
    widget.services.store.addListener(_storeChanged);
  }

  void _load(Json? pack) {
    _request++;
    _busy = false;
    _packId = pack?['id'] as String?;
    _network = pack?['routing'] as Json?;
    _nodes = _network == null
        ? []
        : (_network!['nodes'] as List)
              .map(RouteNode.parse)
              .toList(growable: false);
    _from = _to = _error = null;
    _result = null;
  }

  void _storeChanged() {
    if (!mounted) return;
    setState(() {
      if (_network == null || !identical(_pack?['routing'], _network)) {
        _load(_pack ?? _packs.firstOrNull);
      }
    });
  }

  Future<void> _choose(bool start) async {
    final network = _network;
    final node = await showDialog<RouteNode>(
      context: context,
      builder: (_) => _NodePicker(
        title: start ? 'Початок маршруту' : 'Кінець маршруту',
        nodes: _nodes,
      ),
    );
    if (!mounted || node == null || !identical(network, _network)) return;
    setState(() {
      _request++;
      _busy = false;
      if (start) {
        _from = node.id;
      } else {
        _to = node.id;
      }
      _result = null;
      _error = null;
    });
  }

  Future<void> _calculate() async {
    if (_network == null || _from == null || _to == null || _busy) return;
    final request = ++_request;
    final input = <String, dynamic>{
      'network': _network,
      'from': _from,
      'to': _to,
    };
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final route =
          await (widget.calculate?.call(input) ??
              compute(calculateOfflineRoute, input));
      if (mounted && request == _request) setState(() => _result = route);
    } catch (e) {
      if (mounted && request == _request) {
        setState(() => _error = e is FormatException ? e.message : '$e');
      }
    } finally {
      if (mounted && request == _request) setState(() => _busy = false);
    }
  }

  String _name(String? id) =>
      _nodes.where((n) => n.id == id).firstOrNull?.name ?? 'Обрати вузол';

  @override
  void dispose() {
    _request++;
    widget.services.store.removeListener(_storeChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pack = _pack, result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Офлайн-маршрут')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
            children: [
              const Text(
                'Найкоротший шлях за відстанню в доданій мережі. Усі обчислення — на пристрої.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Потрібен пакет AMID із мережею вузлів і ділянок. MBTiles та звичайні лінії GeoJSON не визначають прохідні шляхи.',
              ),
              if (pack == null) ...[
                const SizedBox(height: 24),
                const Text('Маршрутних мереж поки немає.'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.push<void>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PacksScreen(services: widget.services),
                    ),
                  ),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Додати пакет мережі'),
                ),
              ] else ...[
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  key: ValueKey(_packId),
                  initialValue: _packId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Мережа шляхів'),
                  items: _packs
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            p['title'] as String,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (id) => setState(
                    () => _load(_packs.where((p) => p['id'] == id).firstOrNull),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  '${_nodes.length} вузлів · ${(_network!['edges'] as List).length} ділянок',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_network!['synthetic'] == true)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('Навчальні дані: це не справжні дороги.'),
                  ),
                const SizedBox(height: 14),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.trip_origin),
                  title: const Text('Початок'),
                  subtitle: Text(_name(_from)),
                  trailing: const Icon(Icons.search),
                  onTap: () => _choose(true),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Кінець'),
                  subtitle: Text(_name(_to)),
                  trailing: const Icon(Icons.search),
                  onTap: () => _choose(false),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _from == null && _to == null
                        ? null
                        : () => setState(() {
                            final old = _from;
                            _from = _to;
                            _to = old;
                            _request++;
                            _busy = false;
                            _result = null;
                            _error = null;
                          }),
                    icon: const Icon(Icons.swap_vert),
                    label: const Text('Поміняти напрямок'),
                  ),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: _busy || _from == null || _to == null
                      ? null
                      : _calculate,
                  icon: const Icon(Icons.route_outlined),
                  label: Text(_busy ? 'Шукаю шлях…' : 'Побудувати маршрут'),
                ),
                if (_busy) ...[
                  const SizedBox(height: 12),
                  const LinearProgressIndicator(),
                  TextButton(
                    onPressed: () => setState(() {
                      _request++;
                      _busy = false;
                    }),
                    child: const Text('Скасувати обчислення'),
                  ),
                ],
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                if (result != null) ...[
                  const SizedBox(height: 20),
                  Text(
                    routeDistance(result.meters),
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  Text(
                    '${result.legs.length} ділянок · ${result.nodes.first.name} → ${result.nodes.last.name}',
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () => Navigator.pop(
                      context,
                      MapRouteSelection(
                        _packId!,
                        pack['title'] as String,
                        pack['license'] as String,
                        _network!,
                        result,
                      ),
                    ),
                    icon: const Icon(Icons.map_outlined),
                    label: const Text('Показати на карті'),
                  ),
                  const SizedBox(height: 12),
                  Text('Джерело: ${pack['title']}\n${pack['license']}'),
                  const SizedBox(height: 12),
                  const Text(
                    'Відстань обчислена за геометрією мережі. Час у дорозі, поточний стан і доступність шляхів не визначаються.',
                  ),
                  const Divider(height: 28),
                  for (var i = 0; i < result.legs.length.clamp(0, 100); i++)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text('${i + 1}. ${result.legs[i].edge.name}'),
                      subtitle: Text(
                        '${result.nodes[i].name} → ${result.nodes[i + 1].name}',
                      ),
                      trailing: Text(routeDistance(result.legs[i].edge.meters)),
                    ),
                  if (result.legs.length > 100)
                    const Text(
                      'Показано перші 100 ділянок; експорт містить весь маршрут.',
                    ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NodePicker extends StatefulWidget {
  const _NodePicker({required this.title, required this.nodes});
  final String title;
  final List<RouteNode> nodes;
  @override
  State<_NodePicker> createState() => _NodePickerState();
}

class _NodePickerState extends State<_NodePicker> {
  String _query = '';
  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final nodes = widget.nodes
        .where(
          (n) =>
              n.name.toLowerCase().contains(query) ||
              n.id.toLowerCase().contains(query),
        )
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        height: MediaQuery.sizeOf(context).height * .5,
        child: Column(
          children: [
            TextField(
              autofocus: false,
              decoration: const InputDecoration(
                labelText: 'Назва або ID вузла',
              ),
              onChanged: (value) => setState(() => _query = value),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: nodes.isEmpty
                  ? const Center(child: Text('Вузлів не знайдено.'))
                  : ListView.builder(
                      itemCount: nodes.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(nodes[i].name),
                        subtitle: Text(nodes[i].id),
                        onTap: () => Navigator.pop(context, nodes[i]),
                      ),
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
      ],
    );
  }
}
