import 'dart:async';
import 'dart:convert';

import 'package:amid_offgrid/models/web_page.dart';
import 'package:amid_offgrid/services/web_reader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.StreamedResponse> Function(http.BaseRequest) handler;
  bool closed = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
  @override
  void close() {
    closed = true;
  }
}

http.StreamedResponse _response(
  String body, {
  int status = 200,
  Map<String, String>? headers,
}) => http.StreamedResponse(
  Stream.value(utf8.encode(body)),
  status,
  headers: headers ?? {'content-type': 'text/html; charset=utf-8'},
);

void main() {
  test('overly deep or numerous HTML nodes fail before selector traversal', () {
    for (final source in [
      '${'<div>' * 200}deep${'</div>' * 200}',
      '<body>${'<b>x</b>' * 14000}</body>',
    ]) {
      expect(
        () => ReaderPage.fromHtml(
          source,
          Uri.parse('https://example.org'),
          receivedBytes: source.length,
        ),
        throwsFormatException,
      );
    }
  });
  test('addresses, redirect targets and links share HTTPS-only policy', () {
    expect(
      checkedWebUri('example.org/a/../b#part').toString(),
      'https://example.org/b',
    );
    for (final address in [
      'http://example.org',
      'file:///etc/passwd',
      'javascript:alert(1)',
      'data:text/html,hello',
      'https://user:secret@example.org',
      'https://example.org:8443',
      'https://example.org/with space',
      '',
      'https:///',
    ]) {
      expect(
        () => checkedWebUri(address),
        throwsFormatException,
        reason: address,
      );
    }
  });

  test('HTML becomes inert readable text and bounded safe links', () {
    final page = ReaderPage.fromHtml(
      '''<html><head><title>Карти &amp; зв’язок</title></head>
      <body><nav>Navigation noise</nav><article><h1>Офлайн</h1><p>Ліс &amp; гори.</p>
      <script>secretScript()</script><style>.secretStyle{}</style><form>password field</form>
      <div hidden>hiddenSecret</div><iframe>iframeSecret</iframe>
      <a href="/next">Наступна</a><a href="/next#x">Повтор</a>
      <a href="javascript:alert(1)">Небезпечне</a><a href="http://example.org">HTTP</a>
      <a href="data:text/html,test">DATA</a></article><footer>footerSecret</footer></body></html>''',
      Uri.parse('https://example.org/start'),
      receivedBytes: 600,
    );
    expect(page.title, 'Карти & зв’язок');
    expect(page.text, contains('Ліс & гори.'));
    for (final hidden in [
      'secretScript',
      'secretStyle',
      'password field',
      'hiddenSecret',
      'iframeSecret',
      'footerSecret',
      'Navigation noise',
    ]) {
      expect(page.text, isNot(contains(hidden)));
    }
    expect(page.links.map((l) => l.uri.toString()), [
      'https://example.org/next',
    ]);
  });

  test('long text and many long links fit the existing portable pack limit', () {
    final page = ReaderPage.fromHtml(
      '<html><body><p>${'я' * 190000}</p>${List.generate(80, (i) => '<a href="https://example.org/$i/${'x' * 1900}">${'L' * 210}</a>').join()}</body></html>',
      Uri.parse('https://example.org/'),
      receivedBytes: 500000,
    );
    expect(page.text.length, lessThanOrEqualTo(maxWebTextLength));
    expect(page.truncated, isTrue);
    expect(page.links.length, maxWebLinks);
    expect(page.archiveText.length, lessThanOrEqualTo(250000));
  });

  test(
    'fetch follows bounded HTTPS redirects and records final source',
    () async {
      final requests = <http.BaseRequest>[];
      final client = _Client((request) async {
        requests.add(request);
        return request.url.path == '/start'
            ? _response('', status: 302, headers: {'location': '/final'})
            : _response('<title>Final</title><p>Збережена відповідь</p>');
      });
      final page = await WebReader(clientFactory: () => client)
          .fetch('https://example.org/start');
      expect(page.uri.path, '/final');
      expect(page.text, contains('Збережена відповідь'));
      expect(requests, hasLength(2));
      expect(requests.every((r) => !r.followRedirects), isTrue);
      expect(client.closed, isTrue);
    },
  );

  test('redirect cannot downgrade to HTTP or open a local file', () async {
    for (final location in ['http://example.org/', 'file:///tmp/a']) {
      var count = 0;
      final client = _Client((_) async {
        count++;
        return _response('', status: 302, headers: {'location': location});
      });
      await expectLater(
        WebReader(clientFactory: () => client).fetch('example.org'),
        throwsFormatException,
      );
      expect(count, 1);
      expect(client.closed, isTrue);
    }
  });

  test(
    'binary responses, HTTP errors and oversized streams are rejected',
    () async {
      final factories =
          <Future<http.StreamedResponse> Function(http.BaseRequest)>[
            (_) async => _response(
              'binary',
              headers: {'content-type': 'application/octet-stream'},
            ),
            (_) async => _response('forbidden', status: 403),
            (_) async => http.StreamedResponse(
              Stream.value(List.filled(maxWebResponseBytes + 1, 65)),
              200,
              headers: {'content-type': 'text/html'},
            ),
            (_) async => http.StreamedResponse(
              const Stream.empty(),
              200,
              contentLength: maxWebResponseBytes + 1,
              headers: {'content-type': 'text/html'},
            ),
          ];
      for (final handler in factories) {
        final client = _Client(handler);
        await expectLater(
          WebReader(clientFactory: () => client).fetch('example.org'),
          throwsFormatException,
        );
        expect(client.closed, isTrue);
      }
    },
  );

  test('plain text preserves newlines and treats markup as text', () async {
    final client = _Client(
      (_) async => _response(
        'Перший\nДругий <script>literal</script>',
        headers: {'content-type': 'text/plain'},
      ),
    );
    final page = await WebReader(clientFactory: () => client)
        .fetch('example.org');
    expect(page.text, 'Перший\nДругий <script>literal</script>');
    expect(page.links, isEmpty);
  });

  test(
    'cancel completes even while the transport is waiting for headers',
    () async {
      final waiting = Completer<http.StreamedResponse>();
      final client = _Client((_) => waiting.future);
      final reader = WebReader(clientFactory: () => client);
      final result = expectLater(
        reader.fetch('example.org'),
        throwsA(isA<ReaderCancelled>()),
      );
      reader.cancel();
      await result;
      expect(client.closed, isTrue);
      waiting.complete(_response('<p>late</p>'));
      await Future<void>.delayed(Duration.zero);
    },
  );

  test(
    'cancel stops an idle body subscription and a timeout closes transport',
    () async {
      var cancelled = false;
      final started = Completer<void>();
      final stream = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final client = _Client((_) async {
        started.complete();
        return http.StreamedResponse(
          stream.stream,
          200,
          headers: {'content-type': 'text/html'},
        );
      });
      final reader = WebReader(clientFactory: () => client);
      final pending = expectLater(
        reader.fetch('example.org'),
        throwsA(isA<ReaderCancelled>()),
      );
      await started.future;
      await Future<void>.delayed(Duration.zero);
      reader.cancel();
      await pending;
      await Future<void>.delayed(Duration.zero);
      expect(cancelled, isTrue);
      await stream.close();
      final timeoutClient = _Client(
        (_) => Completer<http.StreamedResponse>().future,
      );
      await expectLater(
        WebReader(
          clientFactory: () => timeoutClient,
          timeout: const Duration(milliseconds: 20),
        ).fetch('example.org'),
        throwsA(isA<TimeoutException>()),
      );
      expect(timeoutClient.closed, isTrue);
    },
  );

  test(
    'a replacement invalid address still cancels the previous request',
    () async {
      final client = _Client((_) => Completer<http.StreamedResponse>().future);
      final reader = WebReader(clientFactory: () => client);
      final previous = expectLater(
        reader.fetch('example.org'),
        throwsA(isA<ReaderCancelled>()),
      );
      await expectLater(reader.fetch('file:///bad'), throwsFormatException);
      await previous;
      expect(client.closed, isTrue);
    },
  );
}
