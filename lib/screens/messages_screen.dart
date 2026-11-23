import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../models/data.dart';
import '../services/services.dart';
import '../widgets/common.dart';

class MessagesScreen extends StatefulWidget {
  const MessagesScreen({super.key, required this.services});
  final Services services;
  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen>
    with WidgetsBindingObserver {
  late TextEditingController _draft;
  Timer? _debounce;
  String _known = '';
  @override
  void initState() {
    super.initState();
    _known = widget.services.store.draft;
    _draft = TextEditingController(text: _known);
    widget.services.store.addListener(_sync);
    WidgetsBinding.instance.addObserver(this);
  }

  void _sync() {
    final value = widget.services.store.draft;
    if (value != _known) {
      _debounce?.cancel();
      _known = value;
      _draft.text = value;
    }
  }

  void _changed(String value) {
    _known = value;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () => _persist(value));
  }

  Future<void> _persist(String value) async {
    try {
      await widget.services.store.setDraft(value);
    } catch (e) {
      if (mounted) toast(context, 'Не вдалося зберегти чернетку: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _debounce?.cancel();
      unawaited(_persist(_draft.text));
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    widget.services.store.removeListener(_sync);
    _draft.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final body = _draft.text.trim();
    if (body.isEmpty) throw StateError('Напиши повідомлення.');
    _debounce?.cancel();
    await widget.services.store.saveMessage(
      Message(
        const Uuid().v4(),
        body,
        DateTime.now().toUtc().toIso8601String(),
        'out',
        'draft',
      ),
    );
    _known = '';
    await widget.services.store.setDraft('');
    _draft.clear();
  }

  Future<void> _share(String text) async {
    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      ),
    );
  }

  Future<void> _join({bool scan = false}) async {
    String? code;
    if (scan) {
      code = await Navigator.of(context)
          .push<String>(MaterialPageRoute(builder: (_) => const _Scanner()));
    } else {
      final input = TextEditingController();
      try {
        code = await showDialog<String>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Код сполучення AMID'),
            content: TextField(
              controller: input,
              minLines: 3,
              maxLines: 6,
              maxLength: 500,
              decoration: const InputDecoration(
                hintText: 'Встав код із другого телефона',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Скасувати'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, input.text),
                child: const Text('З’єднати'),
              ),
            ],
          ),
        );
      } finally {
        input.dispose();
      }
    }
    if (code != null && code.trim().isNotEmpty) {
      await widget.services.nearby.join(code);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.services.store,
      widget.services.nearby,
    ]),
    builder: (context, _) {
      final radio = widget.services.nearby, store = widget.services.store;
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Text(
            'Поруч із тобою',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      radio.connected
                          ? Icons.link_rounded
                          : Icons.bluetooth_rounded,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        radio.status,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text(
                  'Один телефон створює сеанс. Інший сканує його QR-код і обирає AMID у списку. Обидва тримають застосунок відкритим.',
                ),
                const SizedBox(height: 14),
                if (!radio.supported)
                  const Text(
                    'Bluetooth доступний у встановленому застосунку Android та iPhone. Тут можна готувати повідомлення.',
                  )
                else if (!radio.hosting && !radio.scanning && !radio.connected)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: radio.busy
                            ? null
                            : () => guarded(context, radio.startHost),
                        icon: const Icon(Icons.qr_code_rounded),
                        label: const Text('Створити сеанс'),
                      ),
                      OutlinedButton.icon(
                        onPressed: radio.busy
                            ? null
                            : () => guarded(context, () => _join(scan: true)),
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Сканувати QR'),
                      ),
                      TextButton(
                        onPressed: radio.busy
                            ? null
                            : () => guarded(context, _join),
                        child: const Text('Вставити код'),
                      ),
                    ],
                  ),
                if (radio.busy || radio.sending)
                  const Padding(
                    padding: EdgeInsets.only(top: 15),
                    child: LinearProgressIndicator(),
                  ),
                if (radio.hosting &&
                    radio.ticket != null &&
                    !radio.connected) ...[
                  const SizedBox(height: 15),
                  Center(
                    child: Container(
                      color: Colors.white,
                      padding: const EdgeInsets.all(12),
                      child: QrImageView(
                        data: radio.ticket!.encode(),
                        size: 205,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Цей QR містить секрет сеансу. Покажи його лише співрозмовнику.',
                    style: TextStyle(fontSize: 12),
                  ),
                  TextButton.icon(
                    onPressed: () => guarded(context, () async {
                      await Clipboard.setData(
                        ClipboardData(text: radio.ticket!.encode()),
                      );
                      return 'Код скопійовано.';
                    }),
                    icon: const Icon(Icons.copy_rounded),
                    label: const Text('Скопіювати код'),
                  ),
                ],
                if (radio.scanning) ...[
                  const SizedBox(height: 15),
                  if (radio.discoveries.isEmpty)
                    const Text(
                      'Шукаю телефони… Другий телефон має показувати QR створеного сеансу.',
                    ),
                  for (final device in radio.discoveries)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.phone_android_rounded),
                      title: Text(device.advertisement.name ?? 'AMID поблизу'),
                      subtitle: Text('Сигнал: ${device.rssi} dBm'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: radio.busy
                          ? null
                          : () => guarded(context, () => radio.connect(device)),
                    ),
                ],
                if (radio.hosting || radio.scanning || radio.connected)
                  TextButton.icon(
                    onPressed: () => guarded(context, radio.stop),
                    icon: const Icon(Icons.link_off_rounded),
                    label: const Text('Завершити сеанс'),
                  ),
                const SizedBox(height: 10),
                Text(
                  'Експериментальний прямий BLE-зв’язок. Дальність залежить від умов. Перевірку на парі фізичних Android/iPhone ще не виконано.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const Section('Нове повідомлення'),
          TextField(
            controller: _draft,
            onChanged: _changed,
            minLines: 3,
            maxLines: 7,
            maxLength: 4000,
            decoration: const InputDecoration(
              hintText: 'Текст або координати…',
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: () => guarded(context, _save),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Зберегти чернетку'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Поділитися текстом',
                onPressed: () => guarded(context, () => _share(_draft.text)),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            ],
          ),
          const Section('Повідомлення на пристрої'),
          if (store.messages.isEmpty)
            const EmptyState(
              'Тут з’являться повідомлення',
              'Підготуй текст зараз, а передай, коли з’єднаєш телефони.',
              icon: Icons.chat_bubble_outline_rounded,
            )
          else
            for (final message in store.messages.reversed)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            message.direction == 'in'
                                ? Icons.south_west_rounded
                                : Icons.north_east_rounded,
                            size: 16,
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              message.direction == 'in'
                                  ? 'Вхідне'
                                  : 'Твоє повідомлення',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                          ),
                          Text(
                            message.statusLabel,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SelectableText(
                        message.body,
                        style: const TextStyle(height: 1.6),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        children: [
                          if (message.direction == 'out')
                            TextButton.icon(
                              onPressed: !radio.connected || radio.sending
                                  ? null
                                  : () => guarded(
                                      context,
                                      () => radio.send(message),
                                    ),
                              icon: const Icon(
                                Icons.bluetooth_rounded,
                                size: 18,
                              ),
                              label: const Text('Передати поруч'),
                            ),
                          TextButton.icon(
                            onPressed: () =>
                                guarded(context, () => _share(message.body)),
                            icon: const Icon(Icons.ios_share_rounded, size: 18),
                            label: const Text('Поділитися'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
        ],
      );
    },
  );
}

class _Scanner extends StatefulWidget {
  const _Scanner();
  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _done = false;
  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Скануй QR другого AMID')),
    body: kIsWeb
        ? const EmptyState(
            'Відкрий мобільний застосунок',
            'Сканування для сполучення працює на телефоні.',
          )
        : Column(
            children: [
              Expanded(
                child: MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    final value = capture.barcodes.firstOrNull?.rawValue;
                    if (!_done && value != null) {
                      _done = true;
                      Navigator.pop(context, value);
                    }
                  },
                  errorBuilder: (context, error) => EmptyState(
                    'Камера недоступна',
                    'Надай доступ до камери або встав код вручну. ${error.errorCode.name}',
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text(
                  'QR-код відкриває зашифрований сеанс між двома телефонами.',
                ),
              ),
            ],
          ),
  );
}
