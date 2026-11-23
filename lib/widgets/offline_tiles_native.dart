import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:mbtiles/mbtiles.dart';

class OfflineTiles extends StatefulWidget {
  const OfflineTiles({
    super.key,
    required this.path,
    this.minZoom = 0,
    this.maxZoom = 20,
  });
  final String path;
  final double minZoom, maxZoom;
  @override
  State<OfflineTiles> createState() => _OfflineTilesState();
}

class _OfflineTilesState extends State<OfflineTiles> {
  MbTiles? _db;
  MbTilesTileProvider? _provider;
  String? _error;
  @override
  void initState() {
    super.initState();
    try {
      _db = MbTiles(path: widget.path);
      _provider = MbTilesTileProvider(mbtiles: _db!, silenceTileNotFound: true);
    } catch (e) {
      _error = '$e';
    }
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _error != null
      ? Align(
          alignment: Alignment.bottomCenter,
          child: Material(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('Не вдалося відкрити карту: $_error'),
            ),
          ),
        )
      : TileLayer(
          tileProvider: _provider!,
          minNativeZoom: widget.minZoom.floor(),
          maxNativeZoom: widget.maxZoom.floor(),
        );
}
