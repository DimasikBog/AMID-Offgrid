import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart'
    show LicenseRegistry, LicenseEntryWithLineBreaks;
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/store.dart';
import 'services/services.dart';
import 'screens/basic.dart';
import 'screens/assistant_screen.dart';
import 'screens/packs_screen.dart';
import 'screens/map_screen.dart';
import 'screens/messages_screen.dart';
import 'screens/lite_screen.dart';
import 'screens/note_editor.dart';
import 'screens/catalog_screen.dart';
import 'screens/account_screen.dart';
import 'widgets/common.dart';
import 'widgets/app_theme.dart';
import 'services/self_test_native.dart'
    if (dart.library.js_interop) 'services/self_test_web.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Roboto',
    ], await rootBundle.loadString('assets/fonts/OFL-Roboto.txt'));
  });
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'Qwen3-0.6B-GGUF',
    ], await rootBundle.loadString('assets/offline_model/QWEN_LICENSE.txt'));
  });
  if (arguments.contains('--self-test') ||
      arguments.contains('--self-test-full')) {
    await runSelfTest(full: arguments.contains('--self-test-full'));
    return;
  }
  runApp(const OffgridApp());
}

class OffgridApp extends StatefulWidget {
  const OffgridApp({super.key});
  @override
  State<OffgridApp> createState() => _OffgridAppState();
}

class _OffgridAppState extends State<OffgridApp> {
  late Future<AppStore> _store;
  ThemeMode _mode = ThemeMode.system;
  AppStore? _resolved;
  @override
  void initState() {
    super.initState();
    _store = AppStore.open().then(_bind);
  }

  AppStore _bind(AppStore store) {
    if (!mounted) {
      unawaited(store.close());
      return store;
    }
    _resolved?.removeListener(_preferencesChanged);
    _resolved = store;
    store.addListener(_preferencesChanged);
    _preferencesChanged();
    return store;
  }

  void _preferencesChanged() {
    final mode = switch (_resolved?.themePreference) {
      'dark' => ThemeMode.dark,
      'light' => ThemeMode.light,
      _ => ThemeMode.system,
    };
    if (mounted && mode != _mode) setState(() => _mode = mode);
  }

  @override
  void dispose() {
    _resolved?.removeListener(_preferencesChanged);
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => offgridTheme(brightness);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'AMID Offgrid',
    debugShowCheckedModeBanner: false,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    themeMode: _mode,
    locale: const Locale('uk'),
    supportedLocales: const [Locale('uk'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: FutureBuilder<AppStore>(
      future: _store,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: EmptyState(
                'Не вдалося відкрити сховище',
                '${snapshot.error}',
                action: FilledButton(
                  onPressed: () =>
                      setState(() => _store = AppStore.open().then(_bind)),
                  child: const Text('Спробувати ще'),
                ),
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return OffgridShell(
          store: snapshot.data!,
          themeAction: () => guarded(
            context,
            () => snapshot.data!.setThemePreference(
              _mode == ThemeMode.dark ? 'light' : 'dark',
            ),
          ),
        );
      },
    ),
  );
}

const _labels = ['Головна', 'Знання', 'Помічник', 'Карта', 'Зв’язок'];
const _icons = [
  Icons.grid_view_outlined,
  Icons.menu_book_outlined,
  Icons.auto_awesome_outlined,
  Icons.map_outlined,
  Icons.forum_outlined,
];
const _selectedIcons = [
  Icons.grid_view_rounded,
  Icons.menu_book_rounded,
  Icons.auto_awesome_rounded,
  Icons.map_rounded,
  Icons.forum_rounded,
];

class OffgridShell extends StatefulWidget {
  const OffgridShell({
    super.key,
    required this.store,
    required this.themeAction,
  });
  final AppStore store;
  final VoidCallback themeAction;
  @override
  State<OffgridShell> createState() => _OffgridShellState();
}

class _OffgridShellState extends State<OffgridShell>
    with WidgetsBindingObserver {
  late Services services;
  final _visited = <int>{0};
  final _searchFocus = FocusNode(debugLabel: 'Library search');
  int _tab = 0;
  bool _favoritesOnly = false;
  int _libraryRequest = 0;
  @override
  void initState() {
    super.initState();
    services = Services(widget.store);
    unawaited(services.setup.initialize());
    WidgetsBinding.instance.addObserver(this);
  }

  void _navigate(int tab) {
    if (tab != 1) _searchFocus.unfocus();
    if (mounted) {
      setState(() {
        _visited.add(tab);
        _tab = tab;
        _favoritesOnly = false;
        if (tab == 1) _libraryRequest++;
      });
    }
  }

  void _openFavorites() {
    _searchFocus.unfocus();
    setState(() {
      _visited.add(1);
      _tab = 1;
      _favoritesOnly = true;
      _libraryRequest++;
    });
  }

  void _search() {
    _navigate(1);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && ModalRoute.of(context)?.isCurrent == true) {
        _searchFocus.requestFocus();
      }
    });
  }

  void _packs() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => PacksScreen(services: services, openMap: _openMap),
    ),
  );

  void _openMap() {
    Navigator.of(context).popUntil((route) => route.isFirst);
    _navigate(3);
  }

  void _catalog() => Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => CatalogScreen(services: services, openMap: _openMap),
    ),
  );
  void _account() => Navigator.of(context).push<void>(
    MaterialPageRoute(builder: (_) => AccountScreen(account: services.account)),
  );

  void _lite() => unawaited(
    guarded(context, () async {
      await services.assistant.unload();
      await services.nearby.stop();
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => LiteScreen(services: services)),
      );
    }),
  );

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.hidden && services.account.verified) {
      services.account.lock();
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      // Let the unfinished AAL1 flow survive an authenticator-app switch.
      // No profile access is possible before TOTP; the idle timeout still applies.
      if (services.account.verified || state == AppLifecycleState.detached) {
        services.account.lock();
      }
      unawaited(services.assistant.cancel());
      unawaited(services.nearby.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchFocus.dispose();
    services.dispose();
    scheduleMicrotask(() => unawaited(widget.store.close()));
    super.dispose();
  }

  Widget _page(int i) => switch (i) {
    0 => HomeScreen(
      services: services,
      navigate: _navigate,
      openPacks: _packs,
      openSearch: _search,
      openFavorites: _openFavorites,
    ),
    1 => LibraryScreen(
      services: services,
      navigate: _navigate,
      searchFocusNode: _searchFocus,
      favoritesOnly: _favoritesOnly,
      filterRequest: _libraryRequest,
    ),
    2 => AssistantScreen(
      services: services,
      navigate: _navigate,
      openPacks: _packs,
    ),
    3 => MapScreen(services: services, navigate: _navigate),
    _ => MessagesScreen(services: services),
  };

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _search,
      const SingleActivator(LogicalKeyboardKey.keyK, meta: true): _search,
      const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
          unawaited(editNote(context, widget.store)),
      const SingleActivator(LogicalKeyboardKey.keyN, meta: true): () =>
          unawaited(editNote(context, widget.store)),
      for (var i = 0; i < 5; i++)
        SingleActivator(
          const [
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4,
            LogicalKeyboardKey.digit5,
          ][i],
          alt: Theme.of(context).platform != TargetPlatform.macOS,
          meta: Theme.of(context).platform == TargetPlatform.macOS,
        ): () =>
            _navigate(i),
    },
    child: Focus(
      autofocus: true,
      child: PopScope(
        canPop: _tab == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _navigate(0);
        },
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => LayoutBuilder(
            builder: (context, size) {
              final rail = size.maxWidth >= 840 && size.maxHeight >= 480;
              final extended =
                  size.maxWidth >= 1200 ||
                  MediaQuery.textScalerOf(context).scale(14) > 20;
              final content = Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      for (var i = 0; i < 5; i++)
                        _visited.contains(i)
                            ? _page(i)
                            : const SizedBox.shrink(),
                    ],
                  ),
                ),
              );
              return Scaffold(
                appBar: AppBar(
                  title: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.terrain_rounded,
                          size: 23,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      const Flexible(
                        child: Text(
                          'AMID',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            letterSpacing: 2,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (size.maxWidth >= 500) ...[
                        const SizedBox(width: 8),
                        Text(
                          'OFFGRID',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 2,
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                      ],
                    ],
                  ),
                  actions: [
                    if (size.maxWidth >= 500)
                      IconButton(
                        tooltip: 'Змінити тему',
                        onPressed: widget.themeAction,
                        icon: Icon(
                          Theme.of(context).brightness == Brightness.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                        ),
                      ),
                    IconButton(
                      tooltip: 'Пошук · Ctrl/⌘ K',
                      onPressed: _search,
                      icon: const Icon(Icons.search_rounded),
                    ),
                    IconButton(
                      tooltip: 'Пакети та налаштування',
                      onPressed: _packs,
                      icon: const Icon(Icons.inventory_2_outlined),
                    ),
                    PopupMenuButton<String>(
                      tooltip: 'Швидкі дії',
                      onSelected: (value) {
                        switch (value) {
                          case 'catalog':
                            _catalog();
                          case 'account':
                            _account();
                          case 'note':
                            unawaited(editNote(context, widget.store));
                          case 'theme':
                            widget.themeAction();
                          case 'lite':
                            _lite();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'catalog',
                          child: Text('Карти та локальний ШІ'),
                        ),
                        PopupMenuItem(
                          value: 'account',
                          child: Text('Мій акаунт'),
                        ),
                        PopupMenuItem(
                          value: 'note',
                          child: Text('Нова нотатка · Ctrl/⌘ N'),
                        ),
                        PopupMenuItem(
                          value: 'lite',
                          child: Text('Легкий режим'),
                        ),
                        PopupMenuItem(
                          value: 'theme',
                          child: Text('Світла або темна тема'),
                        ),
                      ],
                    ),
                  ],
                ),
                body: SafeArea(
                  top: false,
                  child: rail
                      ? Row(
                          children: [
                            NavigationRail(
                              selectedIndex: _tab,
                              onDestinationSelected: _navigate,
                              extended: extended,
                              minWidth: 88,
                              minExtendedWidth: 210,
                              labelType: extended
                                  ? null
                                  : NavigationRailLabelType.all,
                              destinations: [
                                for (var i = 0; i < 5; i++)
                                  NavigationRailDestination(
                                    icon: Icon(_icons[i]),
                                    selectedIcon: Icon(_selectedIcons[i]),
                                    label: Text(_labels[i]),
                                  ),
                              ],
                            ),
                            const VerticalDivider(width: 1),
                            Expanded(child: content),
                          ],
                        )
                      : content,
                ),
                bottomNavigationBar: rail
                    ? null
                    : NavigationBar(
                        selectedIndex: _tab,
                        onDestinationSelected: _navigate,
                        labelBehavior:
                            MediaQuery.textScalerOf(context).scale(14) > 20
                            ? NavigationDestinationLabelBehavior
                                  .onlyShowSelected
                            : null,
                        destinations: [
                          for (var i = 0; i < 5; i++)
                            NavigationDestination(
                              icon: Icon(_icons[i]),
                              selectedIcon: Icon(_selectedIcons[i]),
                              label: _labels[i],
                            ),
                        ],
                      ),
              );
            },
          ),
        ),
      ),
    ),
  );
}
