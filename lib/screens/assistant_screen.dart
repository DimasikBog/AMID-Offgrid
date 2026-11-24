import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/services.dart';
import '../widgets/common.dart';
import 'basic.dart';

class AssistantScreen extends StatefulWidget {
  const AssistantScreen({
    super.key,
    required this.services,
    required this.navigate,
    required this.openPacks,
  });
  final Services services;
  final void Function(int) navigate;
  final VoidCallback openPacks;
  @override
  State<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends State<AssistantScreen> {
  final _input = TextEditingController();
  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.services.assistant,
    builder: (context, _) {
      final ai = widget.services.assistant;
      final savedModel =
          !kIsWeb &&
          widget.services.store.packs.any(
            (p) =>
                p['kind'] == 'model' &&
                p['id'] == widget.services.store.selectedModel,
          );
      return ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Твій помічник',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              Pill(
                ai.ready
                    ? 'Локальна модель'
                    : savedModel
                    ? 'Модель збережена'
                    : 'Пошук у матеріалах',
              ),
            ],
          ),
          const SizedBox(height: 16),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ai.ready
                      ? 'Обчислення на цьому пристрої'
                      : savedModel
                      ? 'ШІ готовий до першого запиту'
                      : 'Спочатку знайдемо відповідь у довіднику',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 10),
                Text(
                  ai.ready
                      ? 'Запит не надсилається на сервер. Відповідь моделі може містити помилки.'
                      : savedModel
                      ? 'Модель завантажиться в пам’ять автоматично з першим запитом. Обчислення відбуваються на цьому пристрої.'
                      : kIsWeb
                      ? 'У вебверсії працює пошук статей. Для локальної GGUF-моделі встанови нативний застосунок.'
                      : 'Натисни «Встановити все» в офлайн-наборі. Карта й довідник уже вбудовані; модель підготується автоматично.',
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.openPacks,
                  icon: const Icon(Icons.memory_rounded),
                  label: const Text('Керувати моделями'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _input,
            minLines: 2,
            maxLines: 5,
            maxLength: 2000,
            textInputAction: TextInputAction.newline,
            decoration: const InputDecoration(
              hintText: 'Що хочеш дізнатися?',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: ai.busy
                      ? null
                      : () => guarded(context, () => ai.ask(_input.text)),
                  icon: const Icon(Icons.arrow_upward_rounded),
                  label: Text(
                    ai.loading
                        ? 'Запускаю модель…'
                        : (ai.ready || savedModel)
                        ? 'Запитати модель'
                        : 'Знайти у довіднику',
                  ),
                ),
              ),
              if (ai.generating || ai.searching)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: IconButton.filledTonal(
                    tooltip: 'Зупинити генерацію',
                    onPressed: ai.cancel,
                    icon: const Icon(Icons.stop_rounded),
                  ),
                ),
            ],
          ),
          if (ai.question.isNotEmpty) ...[
            const SizedBox(height: 24),
            Text(ai.question, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 14),
            if (ai.generating || ai.searching) const LinearProgressIndicator(),
            if (ai.generated && (ai.answer.isNotEmpty || ai.generating))
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      ai.answer.isEmpty ? 'Обмірковую запит…' : ai.answer,
                      style: const TextStyle(height: 1.7, fontSize: 16),
                    ),
                    if (!ai.generating) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Локально · ${ai.elapsed.inSeconds} с',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      TextButton.icon(
                        onPressed: ai.answer.isEmpty
                            ? null
                            : () => guarded(context, () async {
                                await widget.services.store.setDraft(ai.answer);
                                widget.navigate(4);
                              }),
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('До повідомлення'),
                      ),
                    ],
                  ],
                ),
              ),
            if (ai.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  ai.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Section(
              ai.sources.isEmpty
                  ? 'У довіднику немає збігів'
                  : 'Знайдені джерела',
            ),
            if (ai.sources.isEmpty)
              const Text('Спробуй коротший запит або додай свої матеріали.')
            else
              for (final entry in ai.sources.asMap().entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Panel(
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      leading: Text(
                        '[${entry.key + 1}]',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      title: Text(entry.value.title),
                      subtitle: Text(entry.value.category),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => openArticle(
                        context,
                        entry.value,
                        widget.services,
                        widget.navigate,
                      ),
                    ),
                  ),
                ),
          ] else ...[
            const Section('Спробуй запитати'),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  [
                        'Що підготувати офлайн?',
                        'Як додати карту?',
                        'Як з’єднати телефони?',
                      ]
                      .map(
                        (q) => ActionChip(
                          label: Text(q),
                          onPressed: () {
                            _input.text = q;
                            guarded(context, () => ai.ask(q));
                          },
                        ),
                      )
                      .toList(),
            ),
          ],
        ],
      );
    },
  );
}
