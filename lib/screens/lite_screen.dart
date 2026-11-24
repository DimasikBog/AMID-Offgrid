import 'package:flutter/material.dart';

import '../models/preferences.dart';
import '../services/services.dart';
import '../widgets/common.dart';
import 'basic.dart';
import 'note_editor.dart';

class LiteScreen extends StatelessWidget {
  const LiteScreen({super.key, required this.services});
  final Services services;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AMID · легкий режим')),
    body: ListenableBuilder(
      listenable: services.store,
      builder: (context, _) {
        final store = services.store;
        final favorites = store.articles
            .where((a) => store.favoriteKeys.contains(a.key))
            .take(20)
            .toList();
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Лише потрібне зараз',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Обране, нотатки й особистий список. На цьому екрані немає запуску моделі, карти або Bluetooth. Це режим того самого застосунку; окремі мініпрограми годинників збираються окремо.',
                ),
                const Section('Моя підготовка'),
                Text(
                  '${store.preparation.length} із ${preparationItems.length} позначено власноруч',
                ),
                for (final item in preparationItems.entries)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.value),
                    value: store.preparation.contains(item.key),
                    onChanged: (value) => guarded(
                      context,
                      () => store.setPrepared(item.key, value ?? false),
                    ),
                  ),
                const Section('Обране · до 20 матеріалів'),
                if (favorites.isEmpty)
                  const Text('Додай зірочку до потрібної статті в довіднику.'),
                for (final a in favorites)
                  Card(
                    child: ListTile(
                      title: Text(a.title),
                      subtitle: Text(a.category),
                      onTap: () => openArticle(
                        context,
                        a,
                        services,
                        (_) {},
                        readerOnly: true,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => editNote(context, store),
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Швидка нотатка'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}
