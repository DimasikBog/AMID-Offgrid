import 'package:flutter/material.dart';

import '../models/route_network.dart';
import '../services/map_lookup.dart';
import '../services/store.dart';
import '../widgets/common.dart';

class PlaceSearchScreen extends StatefulWidget {
  const PlaceSearchScreen({super.key, required this.store});
  final AppStore store;
  @override
  State<PlaceSearchScreen> createState() => _PlaceSearchScreenState();
}

class _PlaceSearchScreenState extends State<PlaceSearchScreen> {
  final _query = TextEditingController(), _lookup = MapLookup();
  List<MapPlace> _places = [];
  bool _busy = false;
  String
  _message =
      'Без мережі доступні твої точки, назви областей і введення координат. Для пошуку інших адрес натисни «Онлайн».',
  _source = '';
  @override
  void dispose() {
    _lookup.dispose();
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(bool online) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _places = [];
    });
    try {
      final query = _query.text.trim(), coordinate = coordinatePlace(query);
      final List<MapPlace> places;
      if (coordinate != null) {
        places = [coordinate];
      } else if (online) {
        places = await _lookup.search(query);
      } else {
        if (query.isEmpty) {
          throw const FormatException('Введи назву або координати.');
        }
        final text = query.toLowerCase();
        places = [
          for (final pin in widget.store.pins)
            if (pin.name.toLowerCase().contains(text))
              MapPlace(
                pin.name,
                RoutePoint(pin.latitude, pin.longitude),
                detail: 'Твоя точка',
              ),
          for (final region in widget.store.streetRegions)
            if (region.title.toLowerCase().contains(text))
              MapPlace(
                region.title,
                RoutePoint(
                  region.bounds.centerLatitude,
                  region.bounds.centerLongitude,
                ),
                detail: 'Збережена область',
                regionId: region.id,
              ),
        ].take(50).toList();
      }
      if (mounted) {
        setState(() {
          _places = places;
          _source = online && coordinate == null
              ? 'Photon · OpenStreetMap'
              : 'На цьому пристрої';
          _message = places.isEmpty
              ? 'Нічого не знайдено. Уточни назву або введи широту й довготу.'
              : '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _message = e.toString().replaceFirst(
            RegExp(r'^(FormatException|Bad state):\s*'),
            '',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Знайти місце')),
    body: Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            TextField(
              controller: _query,
              enabled: !_busy,
              autofocus: true,
              maxLength: 200,
              decoration: const InputDecoration(
                labelText: 'Місто, вулиця, місце або координати',
                helperMaxLines: 3,
                helperText:
                    'Координати: широта, довгота — наприклад 50.03, 15.14',
              ),
              onSubmitted: (_) => _search(false),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : () => _search(false),
                  icon: const Icon(Icons.offline_pin_outlined),
                  label: const Text('На пристрої'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _search(true),
                  icon: const Icon(Icons.travel_explore),
                  label: const Text('Онлайн'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Онлайн-пошук надсилає введений запит сервісу Photon. Самостійних запитів під час набору немає.',
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(20),
                child: LinearProgressIndicator(),
              ),
            if (_message.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Text(_message),
              ),
            if (_source.isNotEmpty) Section(_source),
            for (final place in _places)
              ListTile(
                leading: const Icon(Icons.place_outlined),
                title: Text(place.name),
                subtitle: Text(place.detail),
                onTap: () => Navigator.pop(context, place),
              ),
          ],
        ),
      ),
    ),
  );
}
