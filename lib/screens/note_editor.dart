import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/store.dart';
import '../widgets/common.dart';

Future<void> editNote(
  BuildContext context,
  AppStore store, {
  Article? article,
}) => Navigator.of(context).push<void>(
  MaterialPageRoute(
    builder: (_) => NoteEditor(store: store, article: article),
  ),
);

class NoteEditor extends StatefulWidget {
  const NoteEditor({super.key, required this.store, this.article});
  final AppStore store;
  final Article? article;
  @override
  State<NoteEditor> createState() => _NoteEditorState();
}

class _NoteEditorState extends State<NoteEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _title, _body, _category;
  bool _saving = false;
  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.article?.title ?? '');
    _body = TextEditingController(text: widget.article?.body ?? '');
    _category = TextEditingController(
      text: widget.article?.category ?? 'Мої нотатки',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    _category.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final article = widget.article;
      await widget.store.saveNote(
        id: article?.key.substring(AppStore.notesId.length + 2),
        title: _title.text,
        body: _body.text,
        category: _category.text,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) toast(context, 'Нотатку не збережено: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Scaffold(
      appBar: AppBar(
        title: Text(
          widget.article == null ? 'Нова нотатка' : 'Редагувати нотатку',
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              TextFormField(
                controller: _title,
                enabled: !_saving,
                maxLength: 250,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(labelText: 'Назва'),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Напиши назву.' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _category,
                enabled: !_saving,
                maxLength: 100,
                decoration: const InputDecoration(labelText: 'Категорія'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _body,
                enabled: !_saving,
                minLines: 12,
                maxLines: 30,
                maxLength: 250000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Текст',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Зберігаю…' : 'Зберегти на пристрої'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
