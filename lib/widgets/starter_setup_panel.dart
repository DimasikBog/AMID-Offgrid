import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/starter_setup.dart';
import 'common.dart';

class StarterSetupPanel extends StatelessWidget {
  const StarterSetupPanel({super.key, required this.setup});
  final StarterSetup setup;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: setup,
    builder: (context, _) => Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kIsWeb ? 'Базовий вебнабір' : 'Усе для старту — разом',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _item(
            context,
            setup.mapReady,
            'Карта всього світу',
            'Оглядова, без вулиць та адрес. Уже всередині застосунку.',
          ),
          _item(
            context,
            setup.knowledgeReady,
            'Довідник AMID',
            'Матеріали й пошук доступні без мережі.',
          ),
          _item(
            context,
            setup.modelReady,
            'Локальний ШІ · Qwen3 0.6B',
            kIsWeb
                ? 'GGUF працює у встановленій нативній версії.'
                : setup.modelReady
                ? 'Файл перевірено під час встановлення. Модель запуститься з першим запитом.'
                : setup.bundled
                ? 'Є в цій збірці. Підготовка без завантаження з інтернету.'
                : '${setup.catalog == null ? '639 MB' : prettyBytes(setup.catalog!.model.bytes)} · одноразове завантаження. Краще через Wi-Fi.',
          ),
          if (setup.busy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: setup.files.busy && setup.files.progress > 0
                  ? setup.files.progress
                  : null,
            ),
            const SizedBox(height: 8),
            Text(
              setup.files.busy ? setup.files.label : 'Перевіряю офлайн-набір…',
            ),
            if (setup.installing)
              TextButton.icon(
                onPressed: setup.pause,
                icon: const Icon(Icons.pause_rounded),
                label: const Text('Пауза · продовжу пізніше'),
              ),
          ] else if (!kIsWeb) ...[
            const SizedBox(height: 12),
            if (!setup.ready)
              FilledButton.icon(
                onPressed: () => setup.install(),
                icon: const Icon(Icons.download_for_offline_rounded),
                label: Text(
                  setup.paused || setup.error != null
                      ? 'Продовжити встановлення'
                      : 'Встановити все',
                ),
              )
            else ...[
              const Text(
                'Набір установлено. Можна користуватися без інтернету.',
              ),
              TextButton.icon(
                onPressed: () => setup.install(repair: true),
                icon: const Icon(Icons.fact_check_outlined),
                label: const Text('Перевірити та відновити набір'),
              ),
            ],
            const SizedBox(height: 8),
            const Text(
              'Детальні карти вулиць додаються як окремі регіональні MBTiles. На підготовку моделі потрібно ще близько 640 MB вільного місця. Після підготовки можна перейти в авіарежим.',
              style: TextStyle(fontSize: 12),
            ),
          ],
          if (setup.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                setup.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          if (setup.paused)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Підготовку призупинено. Збережені частини залишилися на пристрої.',
              ),
            ),
        ],
      ),
    ),
  );

  Widget _item(
    BuildContext context,
    bool ready,
    String title,
    String subtitle,
  ) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ready ? Icons.check_circle_rounded : Icons.circle_outlined,
          color: ready
              ? Theme.of(context).colorScheme.primary
              : Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(subtitle),
            ],
          ),
        ),
      ],
    ),
  );
}
