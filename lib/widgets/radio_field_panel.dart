import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import '../models/radio_field_test.dart';
import '../services/radio_dock.dart';
import 'common.dart';

class RadioFieldPanel extends StatelessWidget {
  const RadioFieldPanel({super.key, required this.radio});
  final RadioDockService radio;

  Future<void> _export(BuildContext context, RadioFieldReport report) =>
      guarded(context, () async {
        final path = await FilePicker.saveFile(
          fileName: 'AMID_Radio_Test_${report.id}.json',
          mimeType: 'application/json',
          bytes: Uint8List.fromList(
            utf8.encode(
              const JsonEncoder.withIndent('  ').convert(report.toJson()),
            ),
          ),
        );
        if (context.mounted && path != null) {
          toast(context, 'Радіозвіт експортовано.');
        }
      });

  void _details(BuildContext context, RadioFieldReport report) {
    final value = report.toJson();
    String summary(String key, String unit) {
      final s = value[key] as Json;
      if (s['count'] == 0) return 'Немає вимірювань';
      String n(String k) => (s[k] as num).toStringAsFixed(1);
      return '${s['count']} зразків · ${n('min')}…${n('max')} $unit · середнє ${n('mean')} $unit';
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheet) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheet).height * .8,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Section('Польовий звіт LoRa'),
              Text(
                'AMID ${value['appVersion']} · FW ${value['firmware']} · регіон ${value['region']}',
              ),
              Text(
                'Тривалість: ${(report.durationMs / 1000).toStringAsFixed(1)} с',
              ),
              Text('Завершення: ${_reason(value['reason'] as String)}'),
              const SizedBox(height: 12),
              Text(
                'ACK адресата: ${report.acknowledged}/${report.unicastAttempts} одноадресних спроб',
              ),
              for (final key in ['unicast', 'broadcast']) ...[
                Section(key == 'unicast' ? 'Одному вузлу' : 'Розсилка'),
                Text(_counts(value[key] as Json)),
              ],
              Text(
                'Нових LoRa-текстів: ${report.received} · помилок обробки: ${value['processingErrors']}',
              ),
              const Section('Затримка ACK у додатку'),
              Text(summary('ackMs', 'мс')),
              const Text(
                'Включає Bluetooth, чергу та весь маршрут; це не час поширення радіосигналу. ACK не підтверджує прочитання.',
              ),
              const Section('Останній радіострибок'),
              Text('RSSI: ${summary('rssiDbm', 'dBm')}'),
              Text('SNR: ${summary('snrDb', 'dB')}'),
              const Text(
                'Лише нові тексти й відповідні радіовідповіді без MQTT. Ретранслятори змінюють маршрут: ці значення не визначають відстань між телефонами.',
              ),
              const SizedBox(height: 12),
              const Text(
                'Неперевірені спостереження додатка. Експорт не містить текстів, ключів, адрес вузлів або координат. Імпортований звіт не стає підтвердженим фізичним тестом.',
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: () => _export(sheet, report),
                    icon: const Icon(Icons.download_outlined),
                    label: const Text('Зберегти JSON'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => guarded(sheet, () async {
                      await Clipboard.setData(
                        ClipboardData(
                          text: const JsonEncoder.withIndent('  ')
                              .convert(report.toJson()),
                        ),
                      );
                      if (sheet.mounted) toast(sheet, 'Радіозвіт скопійовано.');
                    }),
                    icon: const Icon(Icons.copy_outlined),
                    label: const Text('Копіювати JSON'),
                  ),
                  TextButton(
                    onPressed: () => guarded(sheet, () async {
                      await radio.store.deleteRadioReport(report.id);
                      if (sheet.mounted) Navigator.pop(sheet);
                    }),
                    child: const Text('Видалити звіт'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _counts(Json v) =>
      'Спроб: ${v['attempted']} · ACK: ${v['acknowledged']} · відмов: ${v['failed']} · без ACK: ${v['unconfirmed']} · перервано: ${v['interrupted']}';
  static String _reason(String reason) => switch (reason) {
    'manual' => 'вручну',
    'disconnected' => 'від’єднання',
    'timeLimit' => '60 хвилин',
    'capacity' => '100 спроб',
    'configurationChanged' => 'зміна конфігурації',
    _ => reason,
  };

  @override
  Widget build(BuildContext context) {
    final active = radio.fieldTest;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Section('Польовий тест'),
        const Text(
          'Ручні повідомлення, до 100 спроб або 60 хвилин. Автоматичних передач немає. Звіт зберігається локально при завершенні або від’єднанні.',
        ),
        if (active != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'Тест активний · спроб ${active.attempts} · ACK ${active.acknowledged} · отримано ${active.receivedTexts}',
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              key: const ValueKey('radio-field-start'),
              onPressed:
                  radio.ready &&
                      active == null &&
                      !radio.fieldSaving &&
                      radio.fieldSaveError == null
                  ? () => guarded(context, () async => radio.startFieldTest())
                  : null,
              icon: const Icon(Icons.science_outlined),
              label: const Text('Почати тест'),
            ),
            OutlinedButton(
              key: const ValueKey('radio-field-finish'),
              onPressed: active == null
                  ? null
                  : () => guarded(context, radio.finishFieldTest),
              child: const Text('Завершити й зберегти'),
            ),
          ],
        ),
        if (radio.fieldSaving) const Text('Зберігаю звіт…'),
        if (radio.fieldSaveError != null) ...[
          Text(radio.fieldSaveError!),
          OutlinedButton(
            onPressed: () => guarded(context, radio.saveFieldReport),
            child: const Text('Повторити збереження'),
          ),
        ],
        const SizedBox(height: 8),
        const Text(
          'Збережено останні 20 звітів. Вони входять у резервну копію; старіші замінюються новими.',
        ),
        for (final report in radio.store.radioReports)
          ListTile(
            key: ValueKey('radio-report-${report.id}'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: Text(
              '${report.createdAt} · ${(report.durationMs / 1000).toStringAsFixed(0)} с',
            ),
            subtitle: Text(
              'Спроб ${report.attempts} · ACK ${report.acknowledged}/${report.unicastAttempts} · отримано ${report.received}',
            ),
            onTap: () => _details(context, report),
          ),
      ],
    );
  }
}
