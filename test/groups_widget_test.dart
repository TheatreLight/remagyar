import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/import/zip_import.dart';
import 'package:remagyar/models/word_group.dart';
import 'package:remagyar/screens/group_dialogs.dart';

import 'fixtures.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 150)),
  );
  await tester.pumpAndSettle();
}

void main() {
  sqfliteFfiInit();
  late CardStore store;
  setUp(() async {
    store = await CardStore.open(
      factory: databaseFactoryFfiNoIsolate,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.close());

  testWidgets(
    'group import dialog accepts existing, new, none and cancellation',
    (tester) async {
      ImportGroupChoice? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  result = await showDialog<ImportGroupChoice>(
                    context: context,
                    builder: (_) =>
                        const ImportGroupDialog(groups: [WordGroup(1, 'Еда')]),
                  );
                },
                child: const Text('Открыть'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Открыть'));
      await settle(tester);
      await tester.tap(find.text('Импортировать'));
      await settle(tester);
      expect(result!.id, isNull);
      expect(result!.name, '');
      await tester.tap(find.text('Открыть'));
      await settle(tester);
      await tester.tap(find.text('Без группы'));
      await settle(tester);
      await tester.tap(find.text('Еда').last);
      await settle(tester);
      await tester.tap(find.text('Импортировать'));
      await settle(tester);
      expect(result!.id, 1);
      await tester.tap(find.text('Открыть'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('newGroupName')), 'Новая');
      await tester.tap(find.text('Импортировать'));
      await settle(tester);
      expect(result!.id, isNull);
      expect(result!.name, 'Новая');
      await tester.tap(find.text('Открыть'));
      await settle(tester);
      await tester.tap(find.text('Отмена'));
      await settle(tester);
      expect(result, isNull);
    },
  );

  testWidgets('home filters study by group and keeps total count global', (
    tester,
  ) async {
    final rows = parseZip(makeZip(words));
    await store.importRows([rows[0]], groupName: 'Еда');
    await store.importRows([rows[1]]);
    await tester.pumpWidget(ReMagyarApp(store: store));
    await settle(tester);
    expect(find.text('Всего слов: 2'), findsOneWidget);
    await tester.tap(find.byKey(const Key('groupFilter')));
    await settle(tester);
    await tester.tap(find.text('Еда'));
    await tester.tap(find.text('Применить'));
    await settle(tester);
    expect(find.text('Всего слов: 2'), findsOneWidget);
    await tester.tap(find.text('Изучение слов'));
    await settle(tester);
    expect(find.text('Карточка 1 из 1'), findsOneWidget);
    expect(find.text('alma'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await settle(tester);
    await tester.tap(find.byKey(const Key('groupFilter')));
    await settle(tester);
    await tester.tap(find.text('Еда').last);
    await tester.tap(find.text('Без группы'));
    await tester.tap(find.text('Применить'));
    await settle(tester);
    await tester.tap(find.text('Изучение слов'));
    await settle(tester);
    expect(find.text('ház'), findsOneWidget);
  });

  testWidgets('group union picker and All words reset', (tester) async {
    GroupSelection? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                result = await showDialog<GroupSelection>(
                  context: context,
                  builder: (_) => GroupFilterDialog(
                    groups: const [WordGroup(1, 'A'), WordGroup(2, 'B')],
                    selection: GroupSelection(),
                  ),
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть'));
    await settle(tester);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('B'));
    await tester.tap(find.text('Без группы'));
    await settle(tester);
    await tester.tap(find.text('Применить'));
    await settle(tester);
    expect(result!.ids, {1, 2});
    expect(result!.ungrouped, true);
    await tester.tap(find.text('Открыть'));
    await settle(tester);
    await tester.tap(find.text('A'));
    await tester.tap(find.text('Все слова'));
    await tester.tap(find.text('Применить'));
    await settle(tester);
    expect(result!.all, true);
  });

  testWidgets(
    'rename and delete group through UI; shared cards survive delete with words',
    (tester) async {
      final rows = parseZip(makeZip(words));
      await store.importRows([rows[0], rows[1]], groupName: 'A');
      await store.importRows([rows[1]], groupName: 'B');
      await tester.pumpWidget(MaterialApp(home: GroupsScreen(store: store)));
      await settle(tester);
      await tester.tap(find.byTooltip('Переименовать A'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('renameGroupName')), 'Новое');
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      expect(find.text('Новое'), findsOneWidget);
      await tester.tap(find.byTooltip('Удалить группу Новое'));
      await settle(tester);
      await tester.tap(find.text('Удалить со словами'));
      await tester.tap(find.text('Удалить'));
      await settle(tester);
      expect((await store.cards()).single.hungarian, 'ház');
      await tester.tap(find.byTooltip('Удалить группу B'));
      await settle(tester);
      await tester.tap(find.text('Удалить'));
      await settle(tester);
      expect((await store.cards()).length, 1);
      expect(await store.groups(), isEmpty);
    },
  );
}
