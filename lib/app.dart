import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/store.dart';
import 'import/zip_import.dart';
import 'learning/review.dart';
import 'models/word_card.dart';
import 'models/word_group.dart';
import 'screens/group_dialogs.dart';
import 'screens/card_editor.dart';

class ReMagyarApp extends StatelessWidget {
  const ReMagyarApp({super.key, required this.store, this.pickArchive});
  final CardStore store;
  final Future<Uint8List?> Function()? pickArchive;
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ReMagyar',
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: const [Locale('ru')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF8CA7FF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF111318),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF111318)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 52)),
      ),
    ),
    home: HomeScreen(store: store, pickArchive: pickArchive),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store, this.pickArchive});
  final CardStore store;
  final Future<Uint8List?> Function()? pickArchive;
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  List<WordCard> bank = [];
  List<WordGroup> groups = [];
  GroupSelection selection = GroupSelection();
  int overdue = 0;
  bool loading = true;
  bool importing = false;
  String? error;
  Direction direction = Direction.huRu;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !importing) {
      refresh();
    }
  }

  Future<void> refresh() async {
    try {
      final words = await widget.store.cards();
      final count = await widget.store.overdueCount();
      final loadedGroups = await widget.store.groups();
      if (mounted) {
        setState(() {
          bank = words;
          groups = loadedGroups;
          selection = GroupSelection(
            ids: selection.ids.intersection(groups.map((g) => g.id).toSet()),
            ungrouped: selection.ungrouped,
          );
          overdue = count;
          loading = false;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error = 'Не удалось прочитать банк слов.';
        });
      }
    }
  }

  Future<void> importArchive() async {
    if (importing) {
      return;
    }
    setState(() {
      importing = true;
    });
    try {
      Uint8List? bytes;
      if (widget.pickArchive != null) {
        bytes = await widget.pickArchive!();
      } else {
        final file = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: ['zip'],
        );
        bytes = await file?.readAsBytes();
      }
      if (bytes == null) {
        return;
      }
      final rows = await compute(parseZip, bytes);
      final availableGroups = await widget.store.groups();
      if (!mounted) {
        return;
      }
      setState(() {
        importing = false;
      });
      final choice = await showDialog<ImportGroupChoice>(
        context: context,
        builder: (_) => ImportGroupDialog(groups: availableGroups),
      );
      if (choice == null || !mounted) {
        return;
      }
      setState(() {
        importing = true;
      });
      final report = await widget.store.importRows(
        rows,
        groupId: choice.id,
        groupName: choice.name,
      );
      await refresh();
      if (!mounted) {
        return;
      }
      setState(() {
        importing = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Импорт завершён'),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Добавлено: ${report.added}\nПропущено: ${report.warnings.length}',
                  ),
                  if (choice.id != null ||
                      (choice.name?.trim().isNotEmpty ?? false))
                    Text('В группу добавлено: ${report.linked}'),
                  if (report.warnings.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    ...report.warnings.map(
                      (w) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(w),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Готово'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        importing = false;
      });
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Импорт отменён'),
          content: Text(
            e is FormatException ? e.message : 'Не удалось прочитать или сохранить архив. Банк слов не изменён.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Закрыть'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          importing = false;
        });
      }
    }
  }

  Future<void> openBank() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => BankScreen(store: widget.store)),
    );
    await refresh();
  }

  Future<void> start(bool review, {bool onlyOverdue = false}) async {
    try {
      final cards = await widget.store.cards(
        review: review,
        overdue: onlyOverdue,
        selection: onlyOverdue ? null : selection,
      );
      if (!mounted) {
        return;
      }
      if (cards.isEmpty) {
        await refresh();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('В выбранных группах пока нет слов.')),
          );
        }
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => LessonScreen(
            store: widget.store,
            cards: review ? shuffledReviewCards(cards) : cards,
            bank: bank,
            direction: direction,
            review: review,
          ),
        ),
      );
      await refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть занятие.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = !loading && !importing && error == null && bank.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ReMagyar'),
        actions: [
          IconButton(
            tooltip: 'Группы',
            icon: const Icon(Icons.folder_outlined),
            onPressed: importing
                ? null
                : () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => GroupsScreen(store: widget.store),
                      ),
                    );
                    await refresh();
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Всего слов: ${bank.length}',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              key: const Key('groupFilter'),
              onPressed: importing || loading
                  ? null
                  : () async {
                      final selected = await showDialog<GroupSelection>(
                        context: context,
                        builder: (_) => GroupFilterDialog(
                          groups: groups,
                          selection: selection,
                        ),
                      );
                      if (selected != null && mounted) {
                        setState(() {
                          selection = selected;
                        });
                      }
                    },
              icon: const Icon(Icons.expand_more),
              label: Text(
                selection.all
                    ? 'Все слова'
                    : [
                        if (selection.ungrouped) 'Без группы',
                        ...groups
                            .where((g) => selection.ids.contains(g.id))
                            .map((g) => g.name),
                      ].join(', '),
              ),
            ),
            const SizedBox(height: 16),
            SegmentedButton<Direction>(
              segments: const [
                ButtonSegment(value: Direction.huRu, label: Text('HU → RU')),
                ButtonSegment(value: Direction.ruHu, label: Text('RU → HU')),
              ],
              selected: {direction},
              onSelectionChanged: importing
                  ? null
                  : (v) => setState(() {
                      direction = v.single;
                    }),
            ),
            const SizedBox(height: 24),
            if (loading || importing) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                importing ? 'Проверяем и загружаем архив…' : 'Открываем банк…',
              ),
              const SizedBox(height: 16),
            ],
            if (error != null) ...[
              Text(error!),
              TextButton(
                onPressed: refresh,
                child: const Text('Повторить загрузку'),
              ),
            ],
            if (!loading && bank.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: 20),
                child: Text(
                  'Банк пока пуст. Загрузите ZIP со словами, чтобы начать.',
                ),
              ),
            _HomeAction(
              icon: Icons.style_outlined,
              title: 'Изучение слов',
              onTap: enabled ? () => start(false) : null,
            ),
            _HomeAction(
              icon: Icons.refresh,
              title: 'Повторение',
              onTap: enabled ? () => start(true) : null,
            ),
            if (overdue > 0)
              Card(
                color: Theme.of(context).colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Пора повторить: $overdue',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Ещё без успешного ответа или не повторялись 5 дней.',
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: enabled
                            ? () => start(true, onlyOverdue: true)
                            : null,
                        child: const Text('Повторить эти слова'),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: importing ? null : openBank,
              icon: const Icon(Icons.list_alt),
              label: const Text('Банк слов'),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: importing || loading
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CardEditor(store: widget.store),
                        ),
                      );
                      await refresh();
                    },
              icon: const Icon(Icons.add),
              label: const Text('Добавить слово'),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: importing || loading ? null : importArchive,
              icon: const Icon(Icons.file_upload_outlined),
              label: const Text('Загрузить ZIP'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({required this.icon, required this.title, this.onTap});
  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      enabled: onTap != null,
      onTap: onTap,
    ),
  );
}

class BankScreen extends StatefulWidget {
  const BankScreen({super.key, required this.store});
  final CardStore store;
  @override
  State<BankScreen> createState() => _BankScreenState();
}

class _BankScreenState extends State<BankScreen> {
  late Future<List<WordCard>> words = widget.store.cards();
  bool deletingAll = false;

  Future<void> removeAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить все слова?'),
        content: const Text(
          'Все карточки, изображения и результаты повторения будут удалены. '
          'Группы сохранятся пустыми. Отменить удаление нельзя.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить все'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => deletingAll = true);
    try {
      await widget.store.deleteAllCards();
      if (mounted) {
        setState(() {
          words = widget.store.cards();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить слова.')),
        );
      }
    } finally {
      if (mounted) setState(() => deletingAll = false);
    }
  }

  Future<void> remove(WordCard card) async {
    try {
      await widget.store.delete(card.id!);
      if (mounted) {
        setState(() {
          words = widget.store.cards();
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось удалить карточку.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Банк слов'),
      actions: [
        TextButton(
          onPressed: deletingAll ? null : removeAll,
          child: const Text('Удалить все'),
        ),
      ],
    ),
    body: FutureBuilder<List<WordCard>>(
      future: words,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('Не удалось прочитать банк.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final cards = snapshot.data!;
        if (cards.isEmpty) {
          return const Center(child: Text('Банк пока пуст'));
        }
        return ListView.separated(
          itemCount: cards.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final card = cards[index];
            return ListTile(
              title: Text(card.hungarian),
              onTap: deletingAll
                  ? null
                  : () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              CardEditor(store: widget.store, cardId: card.id),
                        ),
                      );
                      if (mounted) {
                        setState(() {
                          words = widget.store.cards();
                        });
                      }
                    },
              subtitle: Text(
                '${card.russian.join(' / ')}\n${card.lastResult == null
                    ? 'Ещё не повторяли'
                    : card.lastResult!
                    ? 'Последний ответ: верно'
                    : 'Последний ответ: неверно'}',
              ),
              trailing: IconButton(
                tooltip: 'Удалить ${card.hungarian}',
                icon: const Icon(Icons.delete_outline),
                onPressed: deletingAll ? null : () => remove(card),
              ),
            );
          },
        );
      },
    ),
  );
}

class LessonScreen extends StatefulWidget {
  const LessonScreen({
    super.key,
    required this.store,
    required this.cards,
    required this.bank,
    required this.direction,
    required this.review,
  });
  final CardStore store;
  final List<WordCard> cards;
  final List<WordCard> bank;
  final Direction direction;
  final bool review;
  @override
  State<LessonScreen> createState() => _LessonScreenState();
}

class _LessonScreenState extends State<LessonScreen> {
  late final session = ReviewSession(
    cards: widget.cards,
    save: widget.store.record,
  );
  final input = TextEditingController();
  final random = Random();
  int studyIndex = 0;
  bool revealed = false;
  int mode = 0;
  List<String> choices = [];
  late Future<Uint8List?> picture;
  WordCard get card =>
      widget.review ? session.current : widget.cards[studyIndex];
  @override
  void initState() {
    super.initState();
    loadCard();
    session.addListener(changed);
  }

  void changed() {
    if (mounted) {
      setState(() {});
    }
  }

  void loadCard() {
    picture = widget.store.image(card.id!);
    choices = choicesFor(card, widget.bank, widget.direction, random);
    input.clear();
    revealed = false;
    mode = 0;
  }

  @override
  void dispose() {
    session.removeListener(changed);
    session.dispose();
    input.dispose();
    super.dispose();
  }

  Future<void> submit(bool correct) async {
    FocusScope.of(context).unfocus();
    await session.submit(correct);
  }

  void advance() {
    session.next();
    if (!session.finished) {
      loadCard();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (widget.review && session.finished) {
      return Scaffold(
        appBar: AppBar(title: const Text('Повторение')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle_outline, size: 64),
                const SizedBox(height: 20),
                const Text('Занятие завершено', style: TextStyle(fontSize: 26)),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('На главный экран'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final showAnswer = widget.review ? session.result != null : revealed;
    final index = widget.review ? session.index : studyIndex;
    return PopScope(
      canPop: !session.saving,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.review ? 'Повторение' : 'Изучение слов'),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                'Карточка ${index + 1} из ${widget.cards.length}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 10),
              LinearProgressIndicator(value: (index + 1) / widget.cards.length),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        widget.direction == Direction.huRu
                            ? 'ВЕНГЕРСКИЙ'
                            : 'РУССКИЙ',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FutureBuilder<Uint8List?>(
                        future: picture,
                        builder: (context, snapshot) => snapshot.data == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.only(bottom: 20),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.memory(
                                    snapshot.data!,
                                    height: 160,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                      ),
                      Text(
                        card.prompt(widget.direction),
                        key: const Key('prompt'),
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      if (showAnswer) ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Divider(),
                        ),
                        Text(
                          card.answers(widget.direction).join(' / '),
                          key: const Key('answer'),
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (card.example.isNotEmpty) ...[
                          const SizedBox(height: 20),
                          Text(
                            card.example,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (!widget.review) ...[
                if (!revealed)
                  FilledButton.icon(
                    onPressed: () => setState(() {
                      revealed = true;
                    }),
                    icon: const Icon(Icons.visibility_outlined),
                    label: const Text('Показать перевод'),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: studyIndex == 0
                            ? null
                            : () => setState(() {
                                studyIndex--;
                                loadCard();
                              }),
                        child: const Text('Назад'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: studyIndex == widget.cards.length - 1
                            ? null
                            : () => setState(() {
                                studyIndex++;
                                loadCard();
                              }),
                        child: const Text('Вперёд'),
                      ),
                    ),
                  ],
                ),
              ] else if (showAnswer) ...[
                Text(
                  session.result! ? 'Верно' : 'Не получилось — повторим позже',
                  style: TextStyle(
                    fontSize: 20,
                    color: session.result!
                        ? Colors.lightGreenAccent
                        : Theme.of(context).colorScheme.error,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(onPressed: advance, child: const Text('Далее')),
              ] else ...[
                SegmentedButton<int>(
                  segments: [
                    const ButtonSegment(value: 0, label: Text('Написать')),
                    ButtonSegment(
                      value: 1,
                      label: const Text('4 варианта'),
                      enabled: choices.isNotEmpty,
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: session.saving
                      ? null
                      : (v) => setState(() {
                          mode = v.single;
                        }),
                ),
                const SizedBox(height: 16),
                if (mode == 0) ...[
                  TextField(
                    key: const Key('typedAnswer'),
                    controller: input,
                    enabled: !session.saving,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'Ваш перевод'),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (v) {
                      if (v.trim().isNotEmpty) {
                        submit(isCorrect(card, widget.direction, v));
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: session.saving || input.text.trim().isEmpty
                        ? null
                        : () => submit(
                            isCorrect(card, widget.direction, input.text),
                          ),
                    child: const Text('Проверить'),
                  ),
                ] else
                  ...choices.map(
                    (choice) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: OutlinedButton(
                        onPressed: session.saving
                            ? null
                            : () => submit(
                                isCorrect(card, widget.direction, choice),
                              ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(choice),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: session.saving ? null : () => submit(false),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Показать ответ'),
                ),
                const Text(
                  'Подсказка засчитывается как неудачный ответ.',
                  textAlign: TextAlign.center,
                ),
                if (choices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      'Для четырёх вариантов пока недостаточно разных переводов в банке.',
                    ),
                  ),
                if (session.saving) const LinearProgressIndicator(),
                if (session.error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      session.error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
