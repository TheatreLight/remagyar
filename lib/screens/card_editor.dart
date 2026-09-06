import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../data/store.dart';
import '../models/word_card.dart';
import '../models/word_group.dart';

bool validCardImage(Uint8List bytes) {
  try {
    return img.decodePng(bytes) != null || img.decodeJpg(bytes) != null;
  } catch (_) {
    return false;
  }
}

class CardEditor extends StatefulWidget {
  const CardEditor({
    super.key,
    required this.store,
    this.cardId,
    this.pickImage,
  });
  final CardStore store;
  final int? cardId;
  final Future<Uint8List?> Function()? pickImage;
  @override
  State<CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<CardEditor> {
  final form = GlobalKey<FormState>();
  final hungarian = TextEditingController();
  final example = TextEditingController();
  final translations = <TextEditingController>[];
  final removedTranslations = <TextEditingController>[];
  List<WordGroup> groups = [];
  Set<int> selectedIds = {};
  final newGroups = <String>{};
  Uint8List? image;
  bool loading = true;
  bool busy = false;
  String? loadError;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final available = await widget.store.groups();
      final id = widget.cardId;
      final card = id == null ? null : await widget.store.card(id);
      final ids = id == null ? <int>{} : await widget.store.cardGroupIds(id);
      if (!mounted) return;
      setState(() {
        groups = available;
        selectedIds = ids;
        hungarian.text = card?.hungarian ?? '';
        example.text = card?.example ?? '';
        image = card?.image;
        translations.addAll(
          (card?.russian ?? ['']).map(
            (text) => TextEditingController(text: text),
          ),
        );
        loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          loadError = 'Не удалось открыть карточку.';
        });
      }
    }
  }

  @override
  void dispose() {
    hungarian.dispose();
    example.dispose();
    for (final controller in [...translations, ...removedTranslations]) {
      controller.dispose();
    }
    super.dispose();
  }

  void showError(String message) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));

  Future<void> chooseImage() async {
    setState(() => busy = true);
    try {
      Uint8List? bytes;
      if (widget.pickImage != null) {
        bytes = await widget.pickImage!();
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg'],
        );
        bytes = await file?.readAsBytes();
      }
      if (bytes == null) return;
      if (!await compute(validCardImage, bytes)) {
        throw const FormatException(
          'Выберите корректное изображение PNG или JPEG.',
        );
      }
      if (mounted) setState(() => image = bytes);
    } catch (error) {
      if (mounted) {
        showError(
          error is FormatException
              ? error.message
              : 'Не удалось прочитать изображение.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addGroup() async {
    var name = '';
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Новая группа'),
          content: TextField(
            key: const Key('editorNewGroup'),
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Название',
              errorText: error,
            ),
            onChanged: (value) => name = value,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final cleaned = cleanGroupName(name);
                if (cleaned.isEmpty) {
                  update(() => error = 'Введите название группы.');
                  return;
                }
                Navigator.pop(context, cleaned);
              },
              child: const Text('Добавить'),
            ),
          ],
        ),
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      final existing = groups
          .where((g) => groupNameKey(g.name) == groupNameKey(result))
          .firstOrNull;
      if (existing != null) {
        selectedIds.add(existing.id);
      } else if (!newGroups.any(
        (name) => groupNameKey(name) == groupNameKey(result),
      )) {
        newGroups.add(result);
      }
    });
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      await widget.store.saveCard(
        WordCard(
          id: widget.cardId,
          hungarian: hungarian.text,
          russian: translations.map((c) => c.text).toList(),
          example: example.text,
          image: image,
        ),
        groupIds: selectedIds,
        newGroupNames: newGroups.toList(),
      );
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        showError(
          error is FormatException
              ? error.message
              : 'Не удалось сохранить карточку.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? requiredText(String? value) =>
      value == null || value.trim().isEmpty ? 'Обязательное поле' : null;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.cardId == null ? 'Добавить слово' : 'Редактировать слово',
      ),
      actions: [
        TextButton(
          onPressed: loading || busy || loadError != null ? null : save,
          child: const Text('Сохранить'),
        ),
      ],
    ),
    body: loading
        ? const Center(child: CircularProgressIndicator())
        : loadError != null
        ? Center(child: Text(loadError!))
        : AbsorbPointer(
            absorbing: busy,
            child: Form(
              key: form,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  TextFormField(
                    key: const Key('cardHungarian'),
                    controller: hungarian,
                    validator: requiredText,
                    decoration: const InputDecoration(
                      labelText: 'Венгерское слово *',
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...translations.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: TextFormField(
                        key: ObjectKey(entry.value),
                        controller: entry.value,
                        validator: requiredText,
                        minLines: 1,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'Русский перевод ${entry.key + 1} *',
                          suffixIcon: translations.length > 1
                              ? IconButton(
                                  tooltip: 'Удалить перевод ${entry.key + 1}',
                                  icon: const Icon(Icons.close),
                                  onPressed: () => setState(
                                    () => removedTranslations.add(
                                      translations.removeAt(entry.key),
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                  if (translations.length < 5)
                    TextButton.icon(
                      onPressed: () => setState(
                        () => translations.add(TextEditingController()),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('Добавить перевод'),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    key: const Key('cardExample'),
                    controller: example,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Примеры'),
                  ),
                  const SizedBox(height: 16),
                  if (image != null)
                    Image.memory(image!, height: 180, fit: BoxFit.contain),
                  TextButton.icon(
                    onPressed: chooseImage,
                    icon: const Icon(Icons.image_outlined),
                    label: Text(
                      image == null
                          ? 'Добавить изображение'
                          : 'Заменить изображение',
                    ),
                  ),
                  if (image != null)
                    TextButton(
                      onPressed: () => setState(() => image = null),
                      child: const Text('Удалить изображение'),
                    ),
                  const SizedBox(height: 16),
                  Text(
                    'Группы',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Без группы'),
                    value: selectedIds.isEmpty && newGroups.isEmpty,
                    onChanged: (_) => setState(() {
                      selectedIds.clear();
                      newGroups.clear();
                    }),
                  ),
                  ...groups.map(
                    (group) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(group.name),
                      value: selectedIds.contains(group.id),
                      onChanged: (checked) => setState(() {
                        if (checked!) {
                          selectedIds.add(group.id);
                        } else {
                          selectedIds.remove(group.id);
                        }
                      }),
                    ),
                  ),
                  ...newGroups.map(
                    (name) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(name),
                      value: true,
                      onChanged: (_) => setState(() => newGroups.remove(name)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: addGroup,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Создать группу'),
                  ),
                  if (busy) const LinearProgressIndicator(),
                ],
              ),
            ),
          ),
  );
}
