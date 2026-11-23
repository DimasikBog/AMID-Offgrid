import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/store.dart';
import 'services/services.dart';
import 'screens/basic.dart';
import 'screens/assistant_screen.dart';
import 'screens/packs_screen.dart';
import 'screens/map_screen.dart';
import 'screens/messages_screen.dart';
import 'widgets/common.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
  @override
  void initState() {
    super.initState();
    _store = AppStore.open();
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final colors =
        ColorScheme.fromSeed(
          seedColor: const Color(0xff456f52),
          brightness: brightness,
        ).copyWith(
          primary: dark ? mint : const Color(0xff315e40),
          onPrimary: dark ? ink : Colors.white,
          surface: dark ? const Color(0xff101b19) : const Color(0xfff7f8f2),
          surfaceContainerLow: dark
              ? const Color(0xff192622)
              : const Color(0xffeef1e8),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: colors,
      scaffoldBackgroundColor: colors.surface,
      textTheme: ThemeData(brightness: brightness).textTheme
          .apply(bodyColor: colors.onSurface, displayColor: colors.onSurface),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.surface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(17),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.surface,
        indicatorColor: colors.primaryContainer,
        height: 76,
        labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 11)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

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
                  onPressed: () => setState(() => _store = AppStore.open()),
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
          themeAction: () => setState(
            () => _mode = _mode == ThemeMode.dark
                ? ThemeMode.light
                : ThemeMode.dark,
          ),
        );
      },
    ),
  );
}

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
  int _tab = 0;
  @override
  void initState() {
    super.initState();
    services = Services(widget.store);
    WidgetsBinding.instance.addObserver(this);
  }

  void _navigate(int tab) {
    if (mounted) setState(() => _tab = tab);
  }

  void _packs() => Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => PacksScreen(services: services)),
  );
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(services.assistant.cancel());
      unawaited(services.nearby.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    services.dispose();
    unawaited(widget.store.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.store,
    builder: (context, _) => Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                Icons.bolt_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 23,
              ),
            ),
            const SizedBox(width: 10),
            const Text(
              'AMID',
              style: TextStyle(
                letterSpacing: 2,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              'offgrid',
              style: TextStyle(
                fontSize: 16,
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Світла або темна тема',
            onPressed: widget.themeAction,
            icon: const Icon(Icons.contrast_rounded),
          ),
          IconButton(
            tooltip: 'Пакети та налаштування',
            onPressed: _packs,
            icon: const Icon(Icons.inventory_2_outlined),
          ),
          const SizedBox(width: 7),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: IndexedStack(
              index: _tab,
              children: [
                HomeScreen(
                  services: services,
                  navigate: _navigate,
                  openPacks: _packs,
                ),
                LibraryScreen(services: services, navigate: _navigate),
                AssistantScreen(
                  services: services,
                  navigate: _navigate,
                  openPacks: _packs,
                ),
                MapScreen(services: services, navigate: _navigate),
                MessagesScreen(services: services),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _navigate,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Головна',
          ),
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book_rounded),
            label: 'Знання',
          ),
          NavigationDestination(
            icon: Icon(Icons.auto_awesome_outlined),
            selectedIcon: Icon(Icons.auto_awesome_rounded),
            label: 'Помічник',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map_rounded),
            label: 'Карта',
          ),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            selectedIcon: Icon(Icons.forum_rounded),
            label: 'Зв’язок',
          ),
        ],
      ),
    ),
  );
}
