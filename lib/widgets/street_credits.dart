import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'common.dart';

class StreetCredits extends StatelessWidget {
  const StreetCredits({super.key, this.routing = false});
  final bool routing;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 4,
    children: [
      for (final entry in {
        '© OpenStreetMap · ODbL': 'https://www.openstreetmap.org/copyright',
        'Protomaps': 'https://protomaps.com',
        if (routing) 'Маршрути FOSSGIS': 'https://routing.openstreetmap.de',
        'Виправити карту': 'https://www.openstreetmap.org/fixthemap',
      }.entries)
        TextButton(
          onPressed: () => guarded(context, () async {
            if (!await launchUrl(
              Uri.parse(entry.value),
              mode: LaunchMode.externalApplication,
            )) {
              throw StateError('Не вдалося відкрити посилання.');
            }
          }),
          child: Text(entry.key),
        ),
    ],
  );
}
