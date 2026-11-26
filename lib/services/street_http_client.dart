import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/street_map.dart';

/// The archive is planet-sized. Never accept a server ignoring Range.
class StreetHttpClient extends http.BaseClient {
  StreetHttpClient({http.Client? inner}) : _inner = inner ?? http.Client();
  final http.Client _inner;
  final _waiting = Queue<Completer<void>>();
  int _active = 0;
  bool _closed = false;
  String? etag, dataDate;

  Future<void> _acquire() async {
    if (_closed) throw http.ClientException('Завантаження карти скасовано.');
    if (_active >= 3) {
      final waiter = Completer<void>();
      _waiting.add(waiter);
      await waiter.future;
      if (_closed) throw http.ClientException('Завантаження карти скасовано.');
      return;
    }
    if (_closed) throw http.ClientException('Завантаження карти скасовано.');
    _active++;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _active--;
    }
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final range = RegExp(r'^bytes=(\d+)-(\d+)$')
        .firstMatch(request.headers['range'] ?? request.headers['Range'] ?? '');
    if (request.method != 'GET' ||
        request.url.toString() != streetArchiveUrl ||
        range == null) {
      throw http.ClientException('Непідтримуваний запит карти.');
    }
    final start = int.parse(range[1]!), end = int.parse(range[2]!);
    if (end < start || end - start + 1 > 2 * 1024 * 1024) {
      throw http.ClientException('Завеликий фрагмент карти.');
    }
    await _acquire();
    try {
      request.followRedirects = false;
      if (!kIsWeb) {
        request.headers['User-Agent'] =
            'AMID-Offgrid (+https://github.com/DimasikBog/AMID-Offgrid)';
      }
      final response = await _inner
          .send(request)
          .timeout(const Duration(seconds: 25));
      final contentRange = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$')
          .firstMatch(response.headers['content-range'] ?? '');
      if (response.statusCode != 206 ||
          contentRange == null ||
          int.parse(contentRange[1]!) != start ||
          int.parse(contentRange[2]!) != end ||
          int.parse(contentRange[3]!) <= end) {
        await response.stream.listen((_) {}).cancel();
        throw http.ClientException(
          'Джерело не надало потрібний фрагмент карти.',
        );
      }
      final currentTag = response.headers['etag'];
      if (etag != null && currentTag != etag) {
        await response.stream.listen((_) {}).cancel();
        throw http.ClientException(
          'Джерело карти оновилося. Повтори завантаження.',
        );
      }
      etag ??= currentTag;
      dataDate ??= response.headers['last-modified'];
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 25),
      )) {
        if (bytes.length + chunk.length > end - start + 1) {
          throw http.ClientException('Завелика відповідь джерела карти.');
        }
        bytes.add(chunk);
      }
      if (bytes.length != end - start + 1) {
        throw http.ClientException('Неповний фрагмент карти.');
      }
      return http.StreamedResponse(
        Stream.value(bytes.takeBytes()),
        206,
        headers: response.headers,
        request: request,
        contentLength: end - start + 1,
      );
    } finally {
      _release();
    }
  }

  @override
  void close() {
    _closed = true;
    _inner.close();
    while (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    }
  }
}
