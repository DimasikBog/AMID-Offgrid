import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/emergency.dart';
import 'common.dart';

class EmergencyLocationPanel extends StatelessWidget {
  const EmergencyLocationPanel({
    super.key,
    required this.fix,
    required this.status,
    required this.locating,
    required this.refresh,
  });
  final EmergencyFix? fix;
  final String status;
  final bool locating;
  final VoidCallback refresh;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Section('Твоя позиція'),
      Text(status),
      if (fix != null) ...[
        SelectableText(
          fix!.coordinates,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          '${fix!.accuracy > 0 ? 'Точність приблизно ±${fix!.accuracy.ceil()} м' : 'Точність невідома'} · UTC ${fix!.measuredAt.toIso8601String()}',
        ),
        if (!fix!.fresh(DateTime.now()))
          const Text(
            'Позиція застаріла або має некоректний час. Онови її або поясни оператору місце самостійно.',
          ),
      ],
      Wrap(
        spacing: 8,
        children: [
          TextButton.icon(
            onPressed: locating ? null : refresh,
            icon: const Icon(Icons.my_location),
            label: Text(
              locating ? 'Визначаю до 8 секунд…' : 'Визначити / оновити GPS',
            ),
          ),
          if (fix != null)
            TextButton.icon(
              onPressed: () => guarded(context, () async {
                await Clipboard.setData(
                  ClipboardData(
                    text:
                        'GPS WGS84: ${fix!.coordinates}; UTC ${fix!.measuredAt.toIso8601String()}; +/-${fix!.accuracy.ceil()} m',
                  ),
                );
                if (context.mounted) {
                  toast(context, 'Координати скопійовано');
                }
              }),
              icon: const Icon(Icons.copy),
              label: const Text('Копіювати координати'),
            ),
        ],
      ),
      const Text(
        'Під час справжнього екстреного дзвінка телефон може передати місце через AML, якщо це підтримують пристрій і мережа. AMID не отримує підтвердження від диспетчера. Без мобільного зв’язку цей екран не створює канал до служб; LoRa/Bluetooth не підключені до диспетчерів.',
      ),
    ],
  );
}

class EmergencyDetailsForm extends StatelessWidget {
  const EmergencyDetailsForm({
    super.key,
    required this.place,
    required this.description,
    required this.name,
    required this.people,
    required this.cannotSpeak,
    required this.changed,
    required this.cannotSpeakChanged,
  });
  final TextEditingController place, description, name, people;
  final bool cannotSpeak;
  final VoidCallback changed;
  final ValueChanged<bool> cannotSpeakChanged;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Section('Уточнення для SMS'),
      TextField(
        controller: place,
        maxLength: 150,
        decoration: const InputDecoration(
          labelText: 'Де саме: адреса або орієнтир',
        ),
        onChanged: (_) => changed(),
      ),
      TextField(
        controller: description,
        maxLength: 200,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Що сталося'),
        onChanged: (_) => changed(),
      ),
      TextField(
        controller: name,
        maxLength: 80,
        decoration: const InputDecoration(
          labelText: 'Твоє ім’я та прізвище (за можливості)',
        ),
        onChanged: (_) => changed(),
      ),
      TextField(
        controller: people,
        keyboardType: TextInputType.number,
        maxLength: 3,
        decoration: const InputDecoration(
          labelText: 'Кількість людей, якщо відома',
        ),
        onChanged: (_) => changed(),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Не можу говорити'),
        subtitle: const Text(
          'Додати прохання відповідати SMS. Мікрофон самостійно не вмикається.',
        ),
        value: cannotSpeak,
        onChanged: (v) {
          cannotSpeakChanged(v);
        },
      ),
    ],
  );
}
