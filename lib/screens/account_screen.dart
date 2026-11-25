import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/account_service.dart';
import '../widgets/common.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key, required this.account});
  final AccountService account;
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final _name = TextEditingController(),
      _password = TextEditingController(),
      _code = TextEditingController(),
      _recovery = TextEditingController();
  int _mode = 0;
  bool _showPassword = false;
  List<String> _codes = [];
  @override
  void dispose() {
    _name.dispose();
    _password.dispose();
    _code.dispose();
    _recovery.dispose();
    _codes = [];
    widget.account.lock();
    super.dispose();
  }

  Future<void> _submit() async {
    final account = widget.account, name = _name.text.trim().toLowerCase();
    try {
      if (_mode == 1) {
        await account.register(name, _password.text);
      } else if (_mode == 2) {
        await account.recover(name, _password.text, _recovery.text);
      } else {
        await account.login(name, _password.text);
      }
    } finally {
      if (mounted) {
        _password.clear();
        _recovery.clear();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Мій акаунт')),
    body: ListenableBuilder(
      listenable: widget.account,
      builder: (context, _) {
        final account = widget.account;
        if (!account.verified) _codes = [];
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 12, 22, 36),
              children: [
                Icon(
                  account.verified
                      ? Icons.verified_user_outlined
                      : Icons.shield_outlined,
                  size: 44,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 18),
                Text(
                  account.verified
                      ? 'Твій захищений простір'
                      : account.signedIn
                      ? 'Підтвердь, що це ти'
                      : 'Твій акаунт AMID',
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Карти, матеріали й локальний ШІ працюють без входу. Акаунт не завантажує твої нотатки, моделі чи місцезнаходження на сервер.',
                ),
                const SizedBox(height: 20),
                if (account.busy)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 20),
                    child: LinearProgressIndicator(),
                  ),
                if (!account.signedIn) ...[
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (var i = 0; i < 3; i++)
                        ChoiceChip(
                          label: Text(
                            const ['Увійти', 'Реєстрація', 'Відновлення'][i],
                          ),
                          selected: _mode == i,
                          onSelected: account.busy
                              ? null
                              : (_) => setState(() {
                                  _mode = i;
                                  _password.clear();
                                  _recovery.clear();
                                  _codes = [];
                                }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  AutofillGroup(
                    child: Column(
                      children: [
                        TextField(
                          controller: _name,
                          enabled: !account.busy,
                          autocorrect: false,
                          enableSuggestions: false,
                          maxLength: 32,
                          autofillHints: const [AutofillHints.username],
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Логін',
                            helperText: '3–32 латинські літери, цифри або _',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _password,
                          enabled: !account.busy,
                          obscureText: !_showPassword,
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: [
                            _mode == 0
                                ? AutofillHints.password
                                : AutofillHints.newPassword,
                          ],
                          decoration: InputDecoration(
                            labelText: _mode == 2 ? 'Новий пароль' : 'Пароль',
                            helperText: 'Від 16 символів; до 72 байтів UTF-8',
                            prefixIcon: const Icon(Icons.lock_outline),
                            suffixIcon: IconButton(
                              tooltip: _showPassword
                                  ? 'Приховати пароль'
                                  : 'Показати пароль',
                              onPressed: () => setState(
                                () => _showPassword = !_showPassword,
                              ),
                              icon: Icon(
                                _showPassword
                                    ? Icons.visibility_off_outlined
                                    : Icons.visibility_outlined,
                              ),
                            ),
                          ),
                          onSubmitted: account.busy
                              ? null
                              : (_) => guarded(context, _submit),
                        ),
                      ],
                    ),
                  ),
                  if (_mode == 2) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _recovery,
                      enabled: !account.busy,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Один резервний код',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Резервний код замінить втрачений доступ до 2FA. Поточні сеанси буде завершено; налаштуєш новий автентифікатор.',
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: account.busy
                        ? null
                        : () => guarded(context, _submit),
                    icon: Icon(
                      _mode == 1
                          ? Icons.person_add_outlined
                          : _mode == 2
                          ? Icons.key_outlined
                          : Icons.login,
                    ),
                    label: Text(
                      account.busy
                          ? 'Захисна перевірка…'
                          : _mode == 1
                          ? 'Створити акаунт'
                          : _mode == 2
                          ? 'Відновити доступ'
                          : 'Увійти',
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Email і номер телефону не збираються. Для реєстрації потрібні логін, надійний пароль та застосунок-автентифікатор з TOTP. Збережи резервні коди після налаштування 2FA. Під час створення й відновлення пароля сервіс HIBP отримує лише перші 5 символів SHA-1, без пароля та логіна, для перевірки відомих витоків.',
                  ),
                ] else ...[
                  Pill(account.username),
                  if (!account.verified) ...[
                    const SizedBox(height: 18),
                    if (account.totpUri.isNotEmpty) ...[
                      const Text(
                        'Додай цей акаунт у свій автентифікатор. Відскануй QR-код з іншого пристрою або введи секрет вручну. Можна тимчасово перейти у свій автентифікатор. Не передавай його іншим.',
                      ),
                      const SizedBox(height: 16),
                      Center(
                        child: Container(
                          color: Colors.white,
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: account.totpUri,
                            size: 200,
                            backgroundColor: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        account.totpSecret,
                        style: const TextStyle(fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 18),
                    ] else
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Text(
                          'Введи поточний код зі свого автентифікатора.',
                        ),
                      ),
                  ] else ...[
                    const SizedBox(height: 18),
                    const Pill('Вхід підтверджено · 2FA'),
                    const SizedBox(height: 18),
                    Panel(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Сесія зберігається тільки в оперативній пам’яті. Після закриття, згортання застосунку або 15 хвилин без дій з акаунтом потрібно увійти повторно.',
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'На сервері зберігаються логін, профіль і дані авторизації. Особисті офлайн-матеріали залишаються на цьому пристрої.',
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  TextField(
                    controller: _code,
                    enabled: !account.busy,
                    keyboardType: TextInputType.number,
                    autofillHints: const [AutofillHints.oneTimeCode],
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Код 2FA · 6 цифр',
                      prefixIcon: Icon(Icons.password_outlined),
                    ),
                    onSubmitted: account.busy ? null : (_) => _verify(),
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: account.busy ? null : _verify,
                    child: Text(
                      account.verified
                          ? 'Повторно підтвердити 2FA'
                          : 'Підтвердити вхід',
                    ),
                  ),
                  if (account.verified) ...[
                    const Section('Відновлення та дані'),
                    OutlinedButton.icon(
                      onPressed: account.busy
                          ? null
                          : () => guarded(context, () async {
                              final yes = await _confirm(
                                'Створити нові резервні коди?',
                                'Попередні резервні коди перестануть працювати. Нові буде показано лише зараз.',
                              );
                              if (!yes) return;
                              final codes = await account.recoveryCodes();
                              if (mounted) setState(() => _codes = codes);
                            }),
                      icon: const Icon(Icons.key_outlined),
                      label: const Text('Створити 8 резервних кодів'),
                    ),
                    if (_codes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        child: Panel(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Збережи ці коди в надійному місці. Кожен можна використати один раз. На сервері зберігаються лише їхні захищені відбитки.',
                              ),
                              const SizedBox(height: 12),
                              SelectableText(
                                _codes.join('\n'),
                                style: const TextStyle(fontFamily: 'monospace'),
                              ),
                              TextButton(
                                onPressed: () => setState(() => _codes = []),
                                child: const Text('Коди збережені — приховати'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: account.busy
                          ? null
                          : () => guarded(context, () async {
                              final data = await account.export();
                              if (!context.mounted) return;
                              await showDialog<void>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Дані мого акаунта'),
                                  content: SingleChildScrollView(
                                    child: SelectableText(data),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(context),
                                      child: const Text('Закрити'),
                                    ),
                                  ],
                                ),
                              );
                            }),
                      icon: const Icon(Icons.description_outlined),
                      label: const Text('Переглянути експорт акаунта'),
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: account.busy
                          ? null
                          : () => guarded(context, account.logoutAll),
                      icon: const Icon(Icons.logout),
                      label: const Text('Завершити всі сеанси'),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      onPressed: account.busy
                          ? null
                          : () => guarded(context, () async {
                              if (await _confirm(
                                'Видалити акаунт назавжди?',
                                'Буде видалено серверний профіль, спосіб входу та резервні коди. Локальні нотатки, моделі й карти залишаться на пристрої. Потрібне свіже підтвердження 2FA.',
                              )) {
                                await account.delete();
                              }
                              if (mounted) setState(() => _codes = []);
                            }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Видалити акаунт'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: account.busy
                        ? null
                        : () {
                            account.lock();
                            setState(() => _codes = []);
                          },
                    child: const Text('Вийти на цьому пристрої'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    ),
  );
  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Назад'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Підтвердити'),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _verify() => guarded(context, () async {
    try {
      await widget.account.verify(_code.text);
    } finally {
      if (mounted) _code.clear();
    }
  });
}
