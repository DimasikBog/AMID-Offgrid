import 'package:flutter/material.dart';

import '../services/account_service.dart';
import 'common.dart';

class OfflineProfilePanel extends StatefulWidget {
  const OfflineProfilePanel({super.key, required this.account});
  final AccountService account;
  @override
  State<OfflineProfilePanel> createState() => _OfflineProfilePanelState();
}

class _OfflineProfilePanelState extends State<OfflineProfilePanel> {
  final _phrase = TextEditingController(),
      _repeat = TextEditingController(),
      _nickname = TextEditingController();
  @override
  void dispose() {
    _phrase.dispose();
    _repeat.dispose();
    _nickname.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account, vault = account.offline;
    if (vault == null) return const SizedBox.shrink();
    if (!vault.unlocked) {
      return Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Зашифрована копія зберігає ім’я, тему, масштаб тексту та список підготовки. Обери окрему довгу локальну фразу. Вона не надсилається на сервер і не відновлюється через 2FA.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phrase,
              enabled: !account.busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Нова локальна фраза',
                helperText: 'Від 16 символів; до 256 байтів UTF-8',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _repeat,
              enabled: !account.busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: const InputDecoration(
                labelText: 'Повтори локальну фразу',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: account.busy
                  ? null
                  : () => guarded(context, () async {
                      try {
                        if (_phrase.text != _repeat.text) {
                          throw const FormatException(
                            'Локальні фрази не збігаються.',
                          );
                        }
                        await account.enableOffline(_phrase.text);
                      } finally {
                        if (mounted) {
                          _phrase.clear();
                          _repeat.clear();
                        }
                      }
                    }),
              icon: const Icon(Icons.offline_pin_outlined),
              label: Text(
                vault.hasProfile(account.username)
                    ? 'Замінити локальну копію й фразу'
                    : 'Увімкнути офлайн-доступ',
              ),
            ),
          ],
        ),
      );
    }
    return ListenableBuilder(
      listenable: vault.store,
      builder: (context, _) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              vault.displayName,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text('@${vault.username}'),
            const SizedBox(height: 10),
            Text(
              'Остання онлайн-перевірка: ${DateTime.parse(vault.verifiedAt).toUtc().toString().substring(0, 16)} UTC',
            ),
            const SizedBox(height: 12),
            const Text(
              'Зміни теми, масштабу й списку підготовки зберігаються автоматично, поки цей профіль відкритий. Після блокування налаштування пристрою залишаються доступними. Нотатки, файли та карти спільні для пристрою й не шифруються цим профілем.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nickname,
              enabled: !account.busy,
              maxLength: 80,
              decoration: InputDecoration(
                labelText: 'Локальне ім’я',
                hintText: vault.displayName,
              ),
            ),
            TextButton(
              onPressed: account.busy
                  ? null
                  : () => guarded(context, () async {
                      await account.renameOffline(_nickname.text);
                      if (mounted) _nickname.clear();
                    }),
              child: const Text('Зберегти ім’я'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in {
                  'system': 'Системна',
                  'light': 'Світла',
                  'dark': 'Темна',
                }.entries)
                  ChoiceChip(
                    label: Text(entry.value),
                    selected: vault.store.themePreference == entry.key,
                    onSelected: account.busy
                        ? null
                        : (_) => guarded(
                            context,
                            () => vault.store.setThemePreference(entry.key),
                          ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Масштаб тексту: ${(vault.store.readerScale * 100).round()}%'),
            Slider(
              value: vault.store.readerScale,
              min: .8,
              max: 1.8,
              divisions: 10,
              onChanged: account.busy
                  ? null
                  : (value) => guarded(
                      context,
                      () => vault.store.setReaderScale(value),
                    ),
            ),
            const Text(
              'Без мережі неможливо перевірити відкликання сеансу чи видалення акаунту на сервері. Офлайн-профіль не надає серверних прав. Він блокується при згортанні, ручному блокуванні або через 15 хвилин без дій із профілем.',
            ),
            TextButton.icon(
              onPressed: account.busy
                  ? null
                  : () => guarded(
                      context,
                      () => account.forgetOffline(vault.username),
                    ),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Прибрати цю локальну копію'),
            ),
          ],
        ),
      ),
    );
  }
}
