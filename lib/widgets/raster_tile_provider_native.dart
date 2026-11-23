import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_map/flutter_map.dart';

import '../models/raster_limits.dart';
import '../services/raster_archive_native.dart';
import '../services/raster_codec_native.dart';

class RasterTileProvider extends TileProvider {
  RasterTileProvider(this.archive, {required this.onIssue});
  final RasterArchive archive;
  final void Function(Object) onIssue;
  final _keys = <_RasterImage>{};
  bool _disposed = false;
  Future<void>? _closing;

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    if (_disposed) return MemoryImage(TileProvider.transparentImage);
    final image = _RasterImage(
      this,
      coordinates.x,
      coordinates.y,
      coordinates.z,
    );
    _keys.remove(image);
    _keys.add(image);
    if (_keys.length > RasterLimits.cacheKeys) {
      final old = _keys.first;
      _keys.remove(old);
      PaintingBinding.instance.imageCache.evict(old);
    }
    return image;
  }

  Future<void> close() {
    if (_closing != null) return _closing!;
    _disposed = true;
    return _closing = () async {
      try {
        for (final key in _keys) {
          PaintingBinding.instance.imageCache.evict(key);
        }
      } finally {
        _keys.clear();
        await archive.close();
      }
    }();
  }

  @override
  void dispose() {
    close().ignore();
    super.dispose();
  }
}

class _RasterImage extends ImageProvider<_RasterImage> {
  const _RasterImage(this.owner, this.x, this.y, this.z);
  final RasterTileProvider owner;
  final int x, y, z;

  @override
  Future<_RasterImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _RasterImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: _load(decode),
    scale: 1,
    debugLabel: 'MBTiles $z/$x/$y',
  );

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    try {
      final bytes = await owner.archive.readTile(z, x, y);
      if (bytes != null && !owner._disposed) {
        return await decodeRasterTile(bytes, owner.archive.format, decode);
      }
    } catch (error) {
      if (!owner._disposed) owner.onIssue(error);
    }
    return decode(
      await ui.ImmutableBuffer.fromUint8List(TileProvider.transparentImage),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is _RasterImage &&
      identical(owner, other.owner) &&
      x == other.x &&
      y == other.y &&
      z == other.z;
  @override
  int get hashCode => Object.hash(owner, x, y, z);
}
