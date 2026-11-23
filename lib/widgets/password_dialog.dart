import 'package:flutter/material.dart';

Future<String?> requestBackupPassword(
  BuildContext context, {
  bool creating = false,
}) {
  if (!context.mounted) return Future.value(null);
  return showDialog<String>(
    context: context,
    builder: (_) => _PasswordDialog(creating: creating),
  );
}

class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog({required this.creating});
  final bool creating;
  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _form = GlobalKey<FormState>();
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  bool _visible = false;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.creating ? 'Захистити резервну копію' : 'Пароль резервної копії',
    ),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.creating
                  ? 'Пароль не зберігається в застосунку. Збережи його: без нього відкрити цю копію не вдасться.'
                  : 'Введи пароль, установлений під час експорту.',
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _password,
              autofocus: true,
              obscureText: !_visible,
              enableSuggestions: false,
              autocorrect: false,
              maxLength: 1024,
              decoration: InputDecoration(
                labelText: 'Пароль · від 10 символів',
                suffixIcon: IconButton(
                  tooltip: _visible ? 'Приховати пароль' : 'Показати пароль',
                  onPressed: () => setState(() => _visible = !_visible),
                  icon: Icon(
                    _visible
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              validator: (v) => v == null || v.length < 10
                  ? 'Потрібно щонайменше 10 символів.'
                  : null,
            ),
            if (widget.creating) ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _confirmation,
                obscureText: !_visible,
                enableSuggestions: false,
                autocorrect: false,
                maxLength: 1024,
                decoration: const InputDecoration(labelText: 'Повтори пароль'),
                validator: (v) =>
                    v != _password.text ? 'Паролі не збігаються.' : null,
              ),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Скасувати'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _password.text);
          }
        },
        child: Text(widget.creating ? 'Зашифрувати' : 'Відкрити'),
      ),
    ],
  );
}
