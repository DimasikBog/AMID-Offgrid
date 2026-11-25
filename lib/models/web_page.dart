import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html;

import 'data.dart';

const maxWebResponseBytes = 1024 * 1024;
const maxWebTextLength = 180000;
const maxWebLinks = 30;

/// The same policy is used by address entry, redirects and extracted links.
Uri checkedWebUri(String address) {
  var value = address.trim();
  if (value.isEmpty ||
      value.length > 2000 ||
      RegExp(r'[\x00-\x20\x7f]').hasMatch(value)) {
    throw const FormatException('Введи адресу HTTPS-сайту без пробілів.');
  }
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(value)) {
    value = 'https://$value';
  }
  final uri = Uri.tryParse(value);
  if (uri == null ||
      uri.scheme != 'https' ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.port != 443 ||
      uri.toString().length > 2000) {
    throw const FormatException(
      'Підтримуються HTTPS-адреси без пароля та нестандартного порту.',
    );
  }
  return uri.removeFragment().normalizePath();
}

class WebLink {
  const WebLink(this.title, this.uri);
  final String title;
  final Uri uri;
}

class ReaderPage {
  const ReaderPage({
    required this.uri,
    required this.title,
    required this.text,
    required this.fetchedAt,
    required this.receivedBytes,
    this.links = const [],
    this.truncated = false,
  });
  final Uri uri;
  final String title, text;
  final DateTime fetchedAt;

  /// Decoded HTTP response-body bytes, not total network or radio traffic.
  final int receivedBytes;
  final List<WebLink> links;
  final bool truncated;

  factory ReaderPage.fromPlainText(
    String source,
    Uri uri, {
    required int receivedBytes,
    DateTime? fetchedAt,
  }) => ReaderPage(
    uri: checkedWebUri(uri.toString()),
    title: uri.host,
    text: boundedText(source.trim(), maxWebTextLength),
    fetchedAt: (fetchedAt ?? DateTime.now()).toUtc(),
    receivedBytes: receivedBytes,
    truncated: source.trim().length > maxWebTextLength,
  );

  factory ReaderPage.fromHtml(
    String source,
    Uri uri, {
    required int receivedBytes,
    DateTime? fetchedAt,
  }) {
    if (utf8.encode(source).length > maxWebResponseBytes * 3) {
      throw const FormatException('Сторінка завелика для режиму читання.');
    }
    final document = html.parse(source);
    // Bound depth before CSS selectors/text getters recurse through the DOM.
    final pending = <(dom.Node, int)>[(document, 0)];
    var nodeCount = 1;
    while (pending.isNotEmpty) {
      final (node, depth) = pending.removeLast();
      if (depth > 150) {
        throw const FormatException('Структура сторінки надто вкладена.');
      }
      for (final child in node.nodes) {
        if (++nodeCount > 25000) {
          throw const FormatException('Структура сторінки надто складна.');
        }
        pending.add((child, depth + 1));
      }
    }
    final title = boundedText(
      document.querySelector('title')?.text.trim() ?? '',
      250,
    );
    for (final element in document.querySelectorAll(
      'script,style,template,noscript,iframe,object,embed,form,input,textarea,select,button,svg,canvas,nav,footer,[hidden],[aria-hidden="true"]',
    )) {
      element.remove();
    }
    final root =
        document.querySelector('article') ??
        document.querySelector('main') ??
        document.body;
    if (root == null) throw const FormatException('На сторінці немає тексту.');
    final buffer = StringBuffer();
    final stack = <(dom.Node, bool)>[(root, false)];
    const blocks = {
      'p',
      'div',
      'section',
      'article',
      'main',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'li',
      'br',
      'tr',
      'blockquote',
      'pre',
    };
    var visited = 0;
    while (stack.isNotEmpty && buffer.length <= maxWebTextLength) {
      final (node, closing) = stack.removeLast();
      if (++visited > 150000) {
        throw const FormatException('Структура сторінки надто складна.');
      }
      if (node is dom.Text) {
        buffer.write(node.data.replaceAll(RegExp(r'\s+'), ' '));
      } else if (node is dom.Element) {
        final block = blocks.contains(node.localName);
        if (block) buffer.write('\n');
        if (!closing) {
          stack.add((node, true));
          for (final child in node.nodes.reversed) {
            stack.add((child, false));
          }
        }
      }
    }
    final text = buffer
        .toString()
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n[ \t]+'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
    if (text.isEmpty) {
      throw const FormatException('Текст недоступний. Спробуй режим «Сайт».');
    }
    final links = <WebLink>[];
    final seen = <String>{};
    for (final element in root.querySelectorAll('a[href]')) {
      if (links.length >= maxWebLinks) break;
      try {
        final target = checkedWebUri(
          uri.resolve(element.attributes['href']!).toString(),
        );
        if (target == uri || !seen.add(target.toString())) continue;
        final label = element.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        links.add(
          WebLink(
            boundedText(label.isEmpty ? target.host : label, 200),
            target,
          ),
        );
      } on FormatException {
        /* Unsupported links are never made actionable. */
      }
    }
    return ReaderPage(
      uri: checkedWebUri(uri.toString()),
      title: title.isEmpty ? uri.host : title,
      text: boundedText(text, maxWebTextLength),
      fetchedAt: (fetchedAt ?? DateTime.now()).toUtc(),
      receivedBytes: receivedBytes,
      links: List.unmodifiable(links),
      truncated: stack.isNotEmpty || text.length > maxWebTextLength,
    );
  }

  String get archiveText => [
    'Джерело: $uri',
    'Отримано: ${fetchedAt.toUtc().toIso8601String()}',
    if (truncated) 'Збережено скорочений текст сторінки.',
    '',
    text,
    if (links.isNotEmpty) '\nПосилання:',
    for (final link in links) '${link.title}\n${link.uri}',
  ].join('\n');
}
