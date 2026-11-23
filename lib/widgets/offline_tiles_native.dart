import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/data.dart';
import '../services/raster_archive_native.dart';
import 'raster_tile_provider_native.dart';

class OfflineTiles extends StatefulWidget {
  const OfflineTiles({super.key, required this.path, this.openArchive});
  final String path;
  final Future<RasterArchive> Function(String)? openArchive;
  @override
  State<OfflineTiles> createState() => _OfflineTilesState();
}

class _OfflineTilesState extends State<OfflineTiles> {
  RasterTileProvider? _provider;
  String? _error, _issue;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(OfflineTiles oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.openArchive != widget.openArchive) {
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_generation;
    _provider?.dispose();
    setState(() {
      _provider = null;
      _error = _issue = null;
    });
    try {
      final archive =
          await (widget.openArchive?.call(widget.path) ??
              RasterArchive.open(widget.path));
      if (!mounted || generation != _generation) {
        await archive.close();
        return;
      }
      setState(
        () => _provider = RasterTileProvider(
          archive,
          onIssue: (error) => _report(error, generation),
        ),
      );
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = boundedText('$error', 350));
      }
    }
  }

  void _report(Object error, int generation) {
    if (mounted && generation == _generation && _issue == null) {
      setState(() => _issue = boundedText('$error', 250));
    }
  }

  @override
  void dispose() {
    _generation++;
    _provider?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = _provider;
    final generation = _generation;
    if (_error != null) {
      return Align(
        alignment: Alignment.topCenter,
        child: Material(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Не вдалося відкрити карту: $_error',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
                TextButton(
                  onPressed: _load,
                  child: const Text('Повторити відкриття'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (provider == null) {
      return const Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(
            semanticsLabel: 'Відкриваю офлайн-карту',
          ),
        ),
      );
    }
    return Stack(
      children: [
        TileLayer(
          key: ValueKey(provider),
          tileProvider: provider,
          minNativeZoom: (provider.archive.info['minZoom'] as num).toInt(),
          maxNativeZoom: (provider.archive.info['maxZoom'] as num).toInt(),
          errorImage: MemoryImage(TileProvider.transparentImage),
          errorTileCallback: (_, error, _) => _report(error, generation),
        ),
        if (_issue != null)
          Positioned(
            top: 12,
            left: 12,
            right: 70,
            child: Material(
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  'Частину тайлів пропущено: $_issue',
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
