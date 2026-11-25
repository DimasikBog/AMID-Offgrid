import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../models/web_page.dart';
import '../services/store.dart';
import '../services/web_reader.dart';
import '../widgets/common.dart';
import 'saved_pages_screen.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({
    super.key,
    required this.store,
    this.reader,
    this.launchExternal,
  });
  final AppStore store;
  final WebReader? reader;
  final Future<bool> Function(Uri)? launchExternal;
  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen>
    with WidgetsBindingObserver {
  final _address = TextEditingController();
  final _history = <({ReaderPage? page, Article? saved})>[];
  late final WebReader _reader = widget.reader ?? WebReader();
  WebViewController? _site;
  ReaderPage? _page;
  Article? _saved;
  String? _error;
  int _generation = 0, _position = -1;
  bool _busy = false, _siteMode = false, _javascript = false;
  bool get _supportsSite => !kIsWeb && WebViewPlatform.instance != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached) &&
        _busy &&
        !_siteMode) {
      _cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _reader.cancel();
    _retireSite();
    _address.dispose();
    super.dispose();
  }

  void _retireSite() {
    final site = _site;
    _site = null;
    if (site == null) return;
    // Detaching a platform view alone need not stop its page's network work.
    unawaited(() async {
      try {
        await site.setJavaScriptMode(JavaScriptMode.disabled);
        await site.loadHtmlString('<!doctype html><html><body></body></html>');
      } catch (_) {
        /* The platform may have already disposed the view. */
      }
    }());
  }

  void _cancel() {
    _generation++;
    _reader.cancel();
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _load(String address) async {
    final generation = ++_generation;
    _retireSite();
    setState(() {
      _busy = true;
      _error = null;
      _siteMode = false;
      _saved = null;
    });
    try {
      final page = await _reader.fetch(address);
      if (!mounted || generation != _generation) return;
      setState(() {
        _remember(page: page);
        _page = page;
        _address.text = page.uri.toString();
      });
    } on ReaderCancelled {
      /* Cancellation is not a page failure. */
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = _errorText(error));
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  String _errorText(Object error) {
    if (error is FormatException) return error.message;
    if (error is TimeoutException) {
      return 'Сайт не відповів вчасно. Спробуй ще раз.';
    }
    return kIsWeb
        ? 'Не вдалося отримати сторінку. Сайт може забороняти читання з вебдодатка (CORS). Скористайся кнопкою відкриття у системному браузері. Збережені матеріали доступні офлайн.'
        : 'Не вдалося отримати сторінку. Перевір з’єднання, спробуй режим «Сайт» або відкрий адресу у системному браузері.';
  }

  Future<void> _openSite() async {
    if (!_supportsSite) return;
    await guarded(context, () async {
      final uri = checkedWebUri(_address.text);
      _cancel();
      final generation = _generation;
      final controller = _site ?? WebViewController();
      _site = controller;
      bool currentSite() =>
          mounted && _siteMode && identical(_site, controller);
      await controller.setJavaScriptMode(
        _javascript ? JavaScriptMode.unrestricted : JavaScriptMode.disabled,
      );
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (!identical(_site, controller)) {
              return NavigationDecision.prevent;
            }
            try {
              checkedWebUri(request.url);
              return NavigationDecision.navigate;
            } on FormatException {
              if (currentSite()) {
                toast(context, 'Цей тип посилання не підтримується.');
              }
              return NavigationDecision.prevent;
            }
          },
          onPageStarted: (_) {
            if (currentSite()) {
              setState(() {
                _busy = true;
                _error = null;
              });
            }
          },
          onPageFinished: (_) {
            if (currentSite()) setState(() => _busy = false);
          },
          onUrlChange: (change) {
            if (!currentSite() || change.url == null) return;
            try {
              _address.text = checkedWebUri(change.url!).toString();
            } on FormatException {
              /* No non-HTTPS addresses. */
            }
          },
          onWebResourceError: (error) {
            if (currentSite() && error.isForMainFrame != false) {
              setState(() {
                _busy = false;
                _error = 'Сторінка недоступна. Перевір адресу та з’єднання.';
              });
            }
          },
        ),
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _siteMode = true;
        _saved = null;
        _busy = true;
        _error = null;
      });
      try {
        await controller.loadRequest(uri);
      } catch (_) {
        if (mounted && generation == _generation) setState(() => _busy = false);
        rethrow;
      }
    });
  }

  void _remember({ReaderPage? page, Article? saved}) {
    if (_position + 1 < _history.length) {
      _history.removeRange(_position + 1, _history.length);
    }
    _history.add((page: page, saved: saved));
    if (_history.length > 12) _history.removeAt(0);
    _position = _history.length - 1;
  }

  Article? _localCopy(Uri uri) {
    for (final article in widget.store.articles.reversed) {
      if (article.packId != AppStore.webPagesId) continue;
      try {
        if (checkedWebUri(article.source) == uri) return article;
      } on FormatException {
        // Old imported sources may not meet the browser's HTTPS policy.
      }
    }
    return null;
  }

  void _showSaved(Article article, {bool remember = true}) {
    _cancel();
    _retireSite();
    setState(() {
      if (remember) _remember(saved: article);
      _saved = article;
      _page = null;
      _siteMode = false;
      _error = null;
      _address.text = article.source;
    });
  }

  Future<void> _openAddress(String address) => guarded(context, () async {
    _cancel();
    final uri = checkedWebUri(address);
    final local = _localCopy(uri);
    if (local != null) {
      _showSaved(local);
    } else {
      await _load(uri.toString());
    }
  });

  Future<void> _followLink(WebLink link) async {
    final local = _localCopy(link.uri);
    if (local != null) {
      _showSaved(local);
      return;
    }
    if (_saved != null) {
      final generation = _generation;
      final download = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Сторінку не збережено'),
          content: Text('Для цього переходу потрібен інтернет.\n\n${link.uri}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Залишитися офлайн'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Завантажити через інтернет'),
            ),
          ],
        ),
      );
      if (!mounted || download != true || generation != _generation) return;
    }
    await _load(link.uri.toString());
  }

  Future<void> _openExternal() => guarded(context, () async {
    final uri = checkedWebUri(_address.text);
    _cancel();
    // No async availability check before launch: web needs a direct user gesture.
    final opened =
        await (widget.launchExternal?.call(uri) ??
            launchUrl(
              uri,
              mode: LaunchMode.externalApplication,
              webOnlyWindowName: '_blank',
            ));
    if (!opened) {
      throw const FormatException(
        'Не вдалося передати адресу браузеру. Скопіюй її та відкрий вручну.',
      );
    }
  });

  int? _historyTarget(int delta) {
    for (var i = _position + delta; i >= 0 && i < _history.length; i += delta) {
      final visit = _history[i];
      if (visit.saved == null ||
          widget.store.articles.any((a) => a.key == visit.saved!.key)) {
        return i;
      }
    }
    return null;
  }

  void _move(int delta) {
    final target = _historyTarget(delta);
    if (target == null) return;
    final visit = _history[target];
    final saved = visit.saved;
    if (saved != null) {
      _showSaved(
        widget.store.articles.firstWhere((a) => a.key == saved.key),
        remember: false,
      );
      setState(() => _position = target);
      return;
    }
    _cancel();
    _retireSite();
    setState(() {
      _position = target;
      _page = visit.page;
      _saved = null;
      _siteMode = false;
      _error = null;
      _address.text = _page!.uri.toString();
    });
  }

  Future<void> _save() => guarded(context, () async {
    final page = _page;
    if (page == null || _siteMode || _saved != null) return '';
    await widget.store.saveWebPage(
      page,
      checkActive: () {
        if (!mounted) throw const ReaderCancelled();
      },
    );
    return 'Текст збережено. Він доступний офлайн, у пошуку та резервній копії.';
  });

  Future<void> _savedPages() async {
    final selected = await Navigator.of(context).push<Article>(
      MaterialPageRoute(builder: (_) => SavedPagesScreen(store: widget.store)),
    );
    if (!mounted || selected == null) return;
    _showSaved(selected);
  }

  Future<void> _clearSession() => guarded(context, () async {
    _cancel();
    final site = _site;
    setState(() {
      _siteMode = false;
      _site = null;
    });
    if (site != null) {
      await site.setJavaScriptMode(JavaScriptMode.disabled);
      await site.loadHtmlString('<!doctype html><html><body></body></html>');
      await site.clearCache();
      await site.clearLocalStorage();
      await WebViewCookieManager().clearCookies();
    }
    if (!mounted) return '';
    setState(() {
      _site = null;
      _siteMode = false;
      _page = null;
      _saved = null;
      _history.clear();
      _position = -1;
      _error = null;
      _address.clear();
      _javascript = false;
    });
    return 'Історію сеансу, кеш, localStorage й cookies очищено. Збережені тексти залишилися.';
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Браузер',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      actions: [
        IconButton(
          tooltip: 'Відкрити у системному браузері',
          onPressed: _openExternal,
          icon: const Icon(Icons.open_in_new),
        ),
        IconButton(
          tooltip: 'Збережені сторінки',
          onPressed: _savedPages,
          icon: const Icon(Icons.offline_pin_outlined),
        ),
        PopupMenuButton<String>(
          tooltip: 'Налаштування браузера',
          onSelected: (_) => unawaited(_clearSession()),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: 'clear',
              child: Text('Очистити історію, кеш і cookies'),
            ),
          ],
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('browser-address'),
                    controller: _address,
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.go,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      hintText: 'https://example.org',
                      labelText: 'Адреса сайту',
                      prefixIcon: Icon(Icons.lock_outline),
                    ),
                    onSubmitted: (_) =>
                        _siteMode ? _openSite() : _openAddress(_address.text),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Відкрити адресу',
                  onPressed: () =>
                      _siteMode ? _openSite() : _openAddress(_address.text),
                  icon: const Icon(Icons.arrow_forward),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Читання'),
                  selected: !_siteMode,
                  onSelected: (_) {
                    if (_siteMode) unawaited(_openAddress(_address.text));
                  },
                ),
                if (_supportsSite)
                  ChoiceChip(
                    label: const Text('Сайт'),
                    selected: _siteMode,
                    onSelected: (_) => _openSite(),
                  ),
                if (!_siteMode) ...[
                  IconButton(
                    tooltip: 'Попередня сторінка',
                    onPressed: _historyTarget(-1) != null
                        ? () => _move(-1)
                        : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Наступна сторінка',
                    onPressed: _historyTarget(1) != null
                        ? () => _move(1)
                        : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Зберегти текст офлайн',
                    onPressed: !_busy && _page != null && _saved == null
                        ? _save
                        : null,
                    icon: const Icon(Icons.download_for_offline_outlined),
                  ),
                  if (_saved != null)
                    IconButton(
                      tooltip: 'Завантажити свіжу сторінку',
                      onPressed: _busy ? null : () => _load(_address.text),
                      icon: const Icon(Icons.refresh),
                    ),
                  if (_busy)
                    IconButton(
                      tooltip: 'Скасувати завантаження',
                      onPressed: _cancel,
                      icon: const Icon(Icons.close),
                    ),
                ],
                if (_siteMode) ...[
                  IconButton(
                    tooltip: 'Назад на сайті',
                    onPressed: () => guarded(context, () => _site!.goBack()),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  IconButton(
                    tooltip: 'Вперед на сайті',
                    onPressed: () => guarded(context, () => _site!.goForward()),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Оновити сайт',
                    onPressed: () => guarded(context, () => _site!.reload()),
                    icon: const Icon(Icons.refresh),
                  ),
                ],
                if (_siteMode)
                  FilterChip(
                    label: const Text('JavaScript'),
                    selected: _javascript,
                    onSelected: (value) => guarded(context, () async {
                      await _site!.setJavaScriptMode(
                        value
                            ? JavaScriptMode.unrestricted
                            : JavaScriptMode.disabled,
                      );
                      if (mounted) setState(() => _javascript = value);
                      await _site!.reload();
                    }),
                  ),
              ],
            ),
          ),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(
            child: _siteMode && _site != null
                ? Column(
                    children: [
                      const Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Для офлайн-збереження відкрий «Читання». Сайт може завантажувати зображення й інші ресурси.',
                        ),
                      ),
                      Expanded(child: WebViewWidget(controller: _site!)),
                    ],
                  )
                : _readerBody(),
          ),
        ],
      ),
    ),
  );

  Widget _readerBody() {
    final saved = _saved, page = _page;
    if (saved == null && page == null) {
      return ListView(
        children: [
          EmptyState(
            'Сайти та читання офлайн',
            'Введи HTTPS-адресу. У режимі читання завантажується текст без виконання скриптів, зображень і відео. Збережені сторінки можна читати без мережі.',
            icon: Icons.travel_explore,
            action: FilledButton.tonalIcon(
              onPressed: _savedPages,
              icon: const Icon(Icons.offline_pin_outlined),
              label: const Text('Збережені сторінки'),
            ),
          ),
          if (kIsWeb)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'У вебверсії читання залежить від CORS. Кнопка ↗ у верхній панелі відкриває адресу у системному браузері або новій вкладці. Вбудований режим «Сайт» доступний на Android, iOS і macOS.',
              ),
            ),
        ],
      );
    }
    final title = saved?.title ?? page!.title;
    final text = saved?.body ?? page!.text;
    final links = saved != null ? archivedWebLinks(saved.body) : page!.links;
    return ListView(
      key: ValueKey('reader:${saved?.key ?? page!.uri}'),
      primary: false,
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Pill(
              saved != null
                  ? 'Збережено на пристрої'
                  : 'Отримано через інтернет',
            ),
            if (saved == null)
              Pill(
                '${(page!.receivedBytes / 1024).toStringAsFixed(1)} KiB текстової відповіді',
              ),
            if (saved == null && page!.truncated)
              const Pill('Скорочений текст', warning: true),
          ],
        ),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        SelectableText(
          saved?.source ?? page!.uri.toString(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            if (saved == null)
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.download_for_offline_outlined),
                label: const Text('Зберегти офлайн'),
              ),
            TextButton.icon(
              onPressed: () => guarded(context, () async {
                await Clipboard.setData(ClipboardData(text: text));
                return 'Текст скопійовано.';
              }),
              icon: const Icon(Icons.copy),
              label: const Text('Копіювати'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        SelectableText(
          text,
          textScaler: TextScaler.linear(widget.store.readerScale),
          style: const TextStyle(height: 1.65, fontSize: 16),
        ),
        if (links.isNotEmpty) ...[
          const Section('Посилання на сторінці'),
          for (final link in links)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(link.title),
              subtitle: Text(
                link.uri.toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Icon(
                _localCopy(link.uri) != null
                    ? Icons.offline_pin_outlined
                    : Icons.north_east,
              ),
              onTap: () => _followLink(link),
            ),
        ],
      ],
    );
  }
}
