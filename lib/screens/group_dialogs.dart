import 'package:flutter/material.dart';

import '../data/store.dart';
import '../models/word_group.dart';

class ImportGroupDialog extends StatefulWidget {
  const ImportGroupDialog({super.key, required this.groups});
  final List<WordGroup> groups;
  @override
  State<ImportGroupDialog> createState() => _ImportGroupDialogState();
}

class _ImportGroupDialogState extends State<ImportGroupDialog> {
  int selected = -1;
  final name = TextEditingController();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Группа для импорта'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<int>(
            key: ValueKey(selected),
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Существующая группа'),
            items: [
              const DropdownMenuItem(value: -1, child: Text('Без группы')),
              ...widget.groups.map(
                (g) => DropdownMenuItem(
                  value: g.id,
                  child: Text(g.name, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (id) => setState(() {
              selected = id!;
              name.clear();
            }),
          ),
          const SizedBox(height: 16),
          TextField(
            key: const Key('newGroupName'),
            controller: name,
            decoration: const InputDecoration(
              labelText: 'Или название новой группы',
            ),
            onChanged: (_) {
              if (selected != -1) {
                setState(() {
                  selected = -1;
                });
              }
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          ImportGroupChoice(
            id: selected == -1 ? null : selected,
            name: name.text,
          ),
        ),
        child: const Text('Импортировать'),
      ),
    ],
  );
}

class GroupFilterDialog extends StatefulWidget {
  const GroupFilterDialog({
    super.key,
    required this.groups,
    required this.selection,
  });
  final List<WordGroup> groups;
  final GroupSelection selection;
  @override
  State<GroupFilterDialog> createState() => _GroupFilterDialogState();
}

class _GroupFilterDialogState extends State<GroupFilterDialog> {
  late final ids = widget.selection.ids.toSet();
  late bool ungrouped = widget.selection.ungrouped;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Слова для занятия'),
    content: SizedBox(
      width: double.maxFinite,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              title: const Text('Все слова'),
              value: ids.isEmpty && !ungrouped,
              onChanged: (_) => setState(() {
                ids.clear();
                ungrouped = false;
              }),
            ),
            CheckboxListTile(
              title: const Text('Без группы'),
              value: ungrouped,
              onChanged: (v) => setState(() {
                ungrouped = v!;
              }),
            ),
            if (widget.groups.isNotEmpty) const Divider(),
            ...widget.groups.map(
              (g) => CheckboxListTile(
                title: Text(g.name),
                value: ids.contains(g.id),
                onChanged: (v) => setState(() {
                  if (v!) {
                    ids.add(g.id);
                  } else {
                    ids.remove(g.id);
                  }
                }),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(
          context,
          GroupSelection(ids: ids, ungrouped: ungrouped),
        ),
        child: const Text('Применить'),
      ),
    ],
  );
}

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.store});
  final CardStore store;
  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  late Future<List<WordGroup>> groups = widget.store.groups();
  bool busy = false;
  void reload() => setState(() {
    groups = widget.store.groups();
  });
  Future<void> rename(WordGroup group) async {
    var editedName = group.name;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать группу'),
        content: TextFormField(
          key: const Key('renameGroupName'),
          initialValue: group.name,
          onChanged: (value) => editedName = value,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Название'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, editedName),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (name == null || !mounted) {
      return;
    }
    await mutate(() => widget.store.renameGroup(group.id, name));
  }

  Future<void> remove(WordGroup group) async {
    var deleteWords = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Удалить группу «${group.name}»?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Удалить со словами'),
                value: deleteWords,
                onChanged: (v) => setDialogState(() {
                  deleteWords = v!;
                }),
              ),
              Text(
                deleteWords
                    ? 'Карточки, входящие в другие группы, сохранятся. Остальные слова этой группы будут удалены вместе с прогрессом.'
                    : 'Все карточки и их прогресс сохранятся.',
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await mutate(
      () => widget.store.deleteGroup(group.id, deleteWords: deleteWords),
    );
  }

  Future<void> mutate(Future<void> Function() operation) async {
    setState(() {
      busy = true;
    });
    try {
      await operation();
      if (mounted) {
        reload();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException ? e.message : 'Не удалось изменить группу.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Группы')),
    body: FutureBuilder<List<WordGroup>>(
      future: groups,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: TextButton(
              onPressed: reload,
              child: const Text('Повторить загрузку'),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.data!.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Групп пока нет. Новую группу можно создать при импорте.',
              ),
            ),
          );
        }
        return ListView(
          children: snapshot.data!
              .map(
                (g) => ListTile(
                  title: Text(g.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Переименовать ${g.name}',
                        onPressed: busy ? null : () => rename(g),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Удалить группу ${g.name}',
                        onPressed: busy ? null : () => remove(g),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        );
      },
    ),
  );
}
