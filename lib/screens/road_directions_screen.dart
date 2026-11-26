import 'package:flutter/material.dart';

import '../services/map_lookup.dart';
import '../services/store.dart';
import '../widgets/common.dart';
import '../widgets/street_credits.dart';
import 'place_search_screen.dart';
import 'route_planner.dart';

class RoadDirectionsScreen extends StatefulWidget {
  const RoadDirectionsScreen({
    super.key,
    required this.store,
    this.initialFrom,
  });
  final AppStore store;
  final MapPlace? initialFrom;
  @override
  State<RoadDirectionsScreen> createState() => _RoadDirectionsScreenState();
}

class _RoadDirectionsScreenState extends State<RoadDirectionsScreen> {
  final _lookup = MapLookup();
  MapPlace? _from, _to;
  String _mode = 'foot';
  RoadDirections? _result;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _from = widget.initialFrom;
  }

  @override
  void dispose() {
    _lookup.dispose();
    super.dispose();
  }

  Future<void> _choose(bool from) async {
    final place = await Navigator.push<MapPlace>(
      context,
      MaterialPageRoute(builder: (_) => PlaceSearchScreen(store: widget.store)),
    );
    if (!mounted || place == null) return;
    setState(() {
      if (from) {
        _from = place;
      } else {
        _to = place;
      }
      _result = null;
    });
  }

  Future<void> _calculate() async {
    if (_busy || _from == null || _to == null) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final result = await _lookup.route(_from!, _to!, _mode);
      if (mounted) setState(() => _result = result);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Маршрут по дорогах')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Куди вирушаємо?',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 18),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _choose(true),
              icon: const Icon(Icons.trip_origin),
              label: Text(_from?.name ?? 'Обрати старт'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _busy ? null : () => _choose(false),
              icon: const Icon(Icons.location_on_outlined),
              label: Text(_to?.name ?? 'Обрати фініш'),
            ),
            if (_from != null && _to != null)
              TextButton.icon(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                        final old = _from;
                        _from = _to;
                        _to = old;
                        _result = null;
                      }),
                icon: const Icon(Icons.swap_vert),
                label: const Text('Поміняти місцями'),
              ),
            const Section('Як рухаєшся'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in {
                  'foot': ('Пішки', Icons.directions_walk),
                  'bike': ('Велосипед', Icons.pedal_bike),
                  'car': ('Авто', Icons.directions_car),
                }.entries)
                  ChoiceChip(
                    avatar: Icon(entry.value.$2, size: 18),
                    label: Text(entry.value.$1),
                    selected: _mode == entry.key,
                    onSelected: _busy
                        ? null
                        : (_) => setState(() {
                            _mode = entry.key;
                            _result = null;
                          }),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            const Text(
              'Розрахунок онлайн: координати старту й фінішу буде передано FOSSGIS / OpenStreetMap. Збережений результат можна показувати без мережі; для нового розрахунку потрібен інтернет.',
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _busy || _from == null || _to == null
                  ? null
                  : () => guarded(context, _calculate),
              icon: const Icon(Icons.route),
              label: Text(_busy ? 'Шукаю дорогу…' : 'Побудувати маршрут'),
            ),
            const StreetCredits(routing: true),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
            if (_result != null) ...[
              const Section('Маршрут готовий'),
              Text(
                '${routeDistance(_result!.meters)} · близько ${(_result!.seconds / 60).ceil()} хв',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, _result),
                icon: const Icon(Icons.map_outlined),
                label: const Text('Показати на карті'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Це розрахунок за даними доріг, без інформації про поточні перекриття та небезпеки. Орієнтовний час залежить від умов і темпу руху.',
              ),
            ],
          ],
        ),
      ),
    ),
  );
}
