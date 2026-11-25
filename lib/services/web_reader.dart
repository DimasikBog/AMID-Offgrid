import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/web_page.dart';
import 'cancellable_reader.dart';

class ReaderCancelled implements Exception {
  const ReaderCancelled();
  @override
  String toString() => 'Завантаження скасовано.';
}

/// Direct HTTPS reader. No public proxy, radio gateway or account credentials.
class WebReader {
  WebReader({
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 25),
  }) : _clientFactory = clientFactory ?? http.Client.new;
  final http.Client Function() _clientFactory;
  final Duration timeout;
  _ReadJob? _job;

  Future<ReaderPage> fetch(String address) async {
    cancel();
    final uri = checkedWebUri(address);
    final job = _ReadJob(_clientFactory());
    _job = job;
    try {
      return await Future.any([
        _load(job, uri),
        job.cancelled.future.then<ReaderPage>(
          (_) => throw const ReaderCancelled(),
        ),
      ]).timeout(timeout);
    } finally {
      job.close();
      if (identical(_job, job)) _job = null;
    }
  }

  Future<ReaderPage> _load(_ReadJob job, Uri uri) async {
    for (var redirects = 0; redirects <= 5; redirects++) {
      job.check();
      final request = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['Accept'] =
            'text/html,application/xhtml+xml,text/plain;q=0.9';
      final response = await job.client.send(request);
      job.check();
      if ({301, 302, 303, 307, 308}.contains(response.statusCode)) {
        await response.stream.listen((_) {}).cancel();
        final location = response.headers['location'];
        if (location == null || redirects == 5) {
          throw const FormatException(
            'Забагато перенаправлень або відсутня адреса.',
          );
        }
        uri = checkedWebUri(uri.resolve(location).toString());
        continue;
      }
      if (response.statusCode != 200) {
        throw FormatException('Сайт відповів HTTP ${response.statusCode}.');
      }
      final type = (response.headers['content-type'] ?? '').toLowerCase();
      final mime = type.split(';').first.trim();
      if (!{
        'text/html',
        'application/xhtml+xml',
        'text/plain',
      }.contains(mime)) {
        throw const FormatException(
          'Це не текстова сторінка. Завантаження файлів тут не підтримується.',
        );
      }
      if ((response.contentLength ?? 0) > maxWebResponseBytes) {
        throw const FormatException('Ліміт сторінки в режимі читання — 1 MiB.');
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in job.reader.read(response.stream, job.check)) {
        if (bytes.length + chunk.length > maxWebResponseBytes) {
          throw const FormatException(
            'Ліміт сторінки в режимі читання — 1 MiB.',
          );
        }
        bytes.add(chunk);
      }
      job.check();
      final raw = bytes.takeBytes();
      final charset = RegExp(r'charset\s*=\s*["\x27]?([^;\s"\x27]+)')
          .firstMatch(type)
          ?.group(1);
      final source = switch (charset) {
        null ||
        'utf-8' ||
        'utf8' ||
        'us-ascii' => utf8.decode(raw, allowMalformed: true),
        'iso-8859-1' || 'latin1' => latin1.decode(raw),
        _ => throw const FormatException(
          'Кодування сторінки не підтримується. Спробуй режим «Сайт».',
        ),
      };
      if (mime == 'text/plain') {
        return ReaderPage.fromPlainText(source, uri, receivedBytes: raw.length);
      }
      return ReaderPage.fromHtml(source, uri, receivedBytes: raw.length);
    }
    throw const FormatException('Забагато перенаправлень.');
  }

  void cancel() {
    _job?.cancel();
    _job = null;
  }
}

class _ReadJob {
  _ReadJob(this.client);
  final http.Client client;
  final reader = CancellableReader();
  final cancelled = Completer<void>();
  bool active = true;
  void check() {
    if (!active) throw const ReaderCancelled();
  }

  void cancel() {
    if (!cancelled.isCompleted) cancelled.complete();
    close();
  }

  void close() {
    if (!active) return;
    active = false;
    reader.cancel();
    client.close();
  }
}
