import 'dart:async';
import 'dart:typed_data';

import 'package:amid_offgrid/services/raster_archive_native.dart';
import 'package:amid_offgrid/widgets/offline_tiles_native.dart';
import 'package:amid_offgrid/widgets/raster_tile_provider_native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';

// A controlled archive isolates widget ownership from platform I/O and the
// engine decoder. Real SQL, codecs and providers have their own tests.
class _Archive extends Fake implements RasterArchive {
  @override
  final info = <String, dynamic>{'minZoom': 0, 'maxZoom': 24};
  @override
  bool isClosed = false;
  @override
  Future<Uint8List?> readTile(int z, int x, int y) async => null;
  @override
  Future<void> close() async {
    isClosed = true;
  }
}

void main() {
  Widget app(String path, Future<RasterArchive> Function(String) open) =>
      MaterialApp(
        home: Scaffold(
          body: FlutterMap(
            children: [OfflineTiles(path: path, openArchive: open)],
          ),
        ),
      );

  testWidgets('archive arriving after widget disposal is closed', (
    tester,
  ) async {
    final archive = _Archive();
    final pending = Completer<RasterArchive>();
    await tester.pumpWidget(app('a', (_) => pending.future));
    await tester.pumpWidget(const SizedBox.shrink());
    pending.complete(archive);
    await tester.pump();
    expect(archive.isClosed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'switching paths keeps the new archive when old open finishes late',
    (tester) async {
      final a = _Archive(), b = _Archive();
      final first = Completer<RasterArchive>(),
          second = Completer<RasterArchive>();
      Future<RasterArchive> open(String path) =>
          path == 'a' ? first.future : second.future;
      await tester.pumpWidget(app('a', open));
      await tester.pumpWidget(app('b', open));
      second.complete(b);
      await tester.pump();
      first.complete(a);
      await tester.pump();
      expect(a.isClosed, isTrue);
      expect(b.isClosed, isFalse);
      final layer = tester.widget<TileLayer>(find.byType(TileLayer));
      expect((layer.tileProvider as RasterTileProvider).archive, same(b));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(b.isClosed, isTrue);
    },
  );

  testWidgets('an open error can be retried without leaving a stale error', (
    tester,
  ) async {
    final archive = _Archive();
    var attempts = 0;
    Future<RasterArchive> open(String _) async {
      if (attempts++ == 0) throw const FormatException('synthetic open error');
      return archive;
    }

    await tester.pumpWidget(app('retry', open));
    await tester.pump();
    expect(find.textContaining('synthetic open error'), findsOneWidget);
    await tester.tap(find.text('Повторити відкриття'));
    await tester.pump();
    expect(find.byType(TileLayer), findsOneWidget);
    expect(find.textContaining('synthetic open error'), findsNothing);
    expect(attempts, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(archive.isClosed, isTrue);
  });
}
