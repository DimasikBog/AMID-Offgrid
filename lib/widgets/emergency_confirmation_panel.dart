import 'package:flutter/material.dart';

import '../models/emergency.dart';

class EmergencyConfirmationPanel extends StatelessWidget {
  const EmergencyConfirmationPanel({
    super.key,
    required this.ticket,
    required this.listening,
    required this.voice,
    required this.cancel,
  });
  final EmergencyTicket ticket;
  final bool listening;
  final VoidCallback voice, cancel;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.errorContainer,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          ticket.training
              ? 'Тренування · без зв’язку'
              : 'Підтвердити ${ticket.action == EmergencyAction.call ? 'виклик' : 'SMS'} ${ticket.number}',
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 12),
        Text(
          'Для голосового підтвердження скажи повністю: «${ticket.phrase}».',
        ),
        const SizedBox(height: 8),
        const Text(
          'Можна одразу підтвердити нижньою кнопкою. Голос працює у нативній програмі за наявності локального розпізнавання.',
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: listening ? null : voice,
              icon: Icon(listening ? Icons.mic : Icons.mic_none),
              label: Text(
                listening ? 'Слухаю до 12 секунд…' : 'Підтвердити голосом',
              ),
            ),
            TextButton(onPressed: cancel, child: const Text('Скасувати')),
          ],
        ),
        if (ticket.action == EmergencyAction.sms)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: SelectableText(ticket.message),
          ),
        if (!ticket.training)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Телефон може попросити додаткове підтвердження. У вікні SMS потрібно самостійно натиснути «Надіслати».',
            ),
          ),
      ],
    ),
  );
}
