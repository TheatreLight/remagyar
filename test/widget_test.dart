import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/import/zip_import.dart';
import 'package:remagyar/models/word_card.dart';

import 'fixtures.dart';

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
  });
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
  testWidgets('delete all requires confirmation and refreshes home counts', (
    tester,
  ) async {
    await store.importRows(parseZip(makeZip(words)));
    await tester.pumpWidget(ReMagyarApp(store: store));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Банк слов'), 250);
    await settle(tester);
    await tester.tap(find.text('Банк слов'));
    await settle(tester);
    await tester.tap(find.text('Удалить все'));
    await settle(tester);
    expect(find.text('Удалить все слова?'), findsOneWidget);
    await tester.tap(find.text('Отмена'));
    await settle(tester);
    expect((await store.cards()).length, 5);
    await tester.tap(find.text('Удалить все'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить все'));
    await settle(tester);
    expect(find.text('Банк пока пуст'), findsOneWidget);
    expect(await store.cards(), isEmpty);
    await tester.tap(find.byTooltip('Назад'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Всего слов: 0'), -250);
    await settle(tester);
    expect(find.text('Всего слов: 0'), findsOneWidget);
    expect(find.textContaining('Пора повторить:'), findsNothing);
  });
  testWidgets('empty app, cancelled and valid import with report', (
    tester,
  ) async {
    var cancel = true;
    await tester.pumpWidget(
      ReMagyarApp(
        store: store,
        pickArchive: () async => cancel ? null : makeZip(words),
      ),
    );
    await settle(tester);
    expect(find.textContaining('Банк пока пуст.'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Загрузить ZIP'), 250);
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Загрузить ZIP'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);
    expect(find.text('Импорт завершён'), findsNothing);
    cancel = false;
    await tester.runAsync(() async {
      await tester.tap(find.text('Загрузить ZIP'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);
    expect(find.text('Группа для импорта'), findsOneWidget);
    await tester.tap(find.text('Импортировать'));
    await settle(tester);
    expect(find.text('Импорт завершён'), findsOneWidget);
    expect(find.textContaining('Добавлено: 5'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Всего слов: 5'), -250);
    expect(find.text('Всего слов: 5'), findsOneWidget);
  });
  testWidgets('invalid archive leaves bank empty and shows reason', (
    tester,
  ) async {
    await tester.pumpWidget(
      ReMagyarApp(
        store: store,
        pickArchive: () async => makeZip('${header}bad,'),
      ),
    );
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Загрузить ZIP'), 250);
    await settle(tester);
    await tester.runAsync(() async {
      await tester.tap(find.text('Загрузить ZIP'));
      await Future<void>.delayed(const Duration(milliseconds: 500));
    });
    await settle(tester);
    expect(find.text('Импорт отменён'), findsOneWidget);
    expect(find.textContaining('ожидается 4 поля'), findsOneWidget);
  });
  testWidgets('study reveals and navigates without recording success', (
    tester,
  ) async {
    await store.importRows(parseZip(makeZip(words)));
    final cards = await store.cards();
    await tester.pumpWidget(
      MaterialApp(
        home: LessonScreen(
          store: store,
          cards: cards,
          bank: cards,
          direction: Direction.huRu,
          review: false,
        ),
      ),
    );
    await settle(tester);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Назад'))
          .onPressed,
      isNull,
    );
    expect(find.byKey(const Key('answer')), findsNothing);
    await tester.tap(find.text('Показать перевод'));
    await settle(tester);
    expect(find.text('яблоко'), findsOneWidget);
    await tester.tap(find.text('Вперёд'));
    await settle(tester);
    expect(find.text('ház'), findsOneWidget);
    expect(find.byKey(const Key('answer')), findsNothing);
    await tester.tap(find.text('Назад'));
    await settle(tester);
    expect(find.text('alma'), findsOneWidget);
    expect((await store.cards()).every((c) => c.lastResult == null), true);
  });
  testWidgets('reverse study and one-card boundaries', (tester) async {
    await store.importRows(
      parseZip(makeZip('${header}ház,дом|здание,пример,')),
    );
    final cards = await store.cards();
    await tester.pumpWidget(
      MaterialApp(
        home: LessonScreen(
          store: store,
          cards: cards,
          bank: cards,
          direction: Direction.ruHu,
          review: false,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('дом / здание'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Вперёд'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('Показать перевод'));
    await settle(tester);
    expect(find.text('ház'), findsOneWidget);
    expect(find.text('пример'), findsOneWidget);
  });
  testWidgets(
    'review accepts typed alternate then peek fails and next completes',
    (tester) async {
      await store.importRows(
        parseZip(makeZip('${header}ház,дом|здание,,\nalma,яблоко,,')),
      );
      final cards = await store.cards();
      await tester.pumpWidget(
        MaterialApp(
          home: LessonScreen(
            store: store,
            cards: cards,
            bank: cards,
            direction: Direction.huRu,
            review: true,
          ),
        ),
      );
      await settle(tester);
      expect(find.textContaining('недостаточно'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('typedAnswer')), ' ЗДАНИЕ ');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Проверить'));
      await tester.tap(find.text('Проверить'));
      await settle(tester);
      expect(find.text('Верно'), findsOneWidget);
      await tester.tap(find.text('Далее'));
      await settle(tester);
      await tester.ensureVisible(find.text('Показать ответ'));
      await tester.tap(find.text('Показать ответ'));
      await settle(tester);
      expect(find.textContaining('Не получилось'), findsOneWidget);
      await tester.tap(find.text('Далее'));
      await settle(tester);
      expect(find.text('Занятие завершено'), findsOneWidget);
      final saved = await store.cards();
      expect(saved[0].lastResult, true);
      expect(saved[1].lastResult, false);
    },
  );
  testWidgets('choice mode and bank deletion', (tester) async {
    await store.importRows(parseZip(makeZip(words)));
    final cards = await store.cards();
    await tester.pumpWidget(
      MaterialApp(
        home: LessonScreen(
          store: store,
          cards: cards,
          bank: cards,
          direction: Direction.ruHu,
          review: true,
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('4 варианта'));
    await settle(tester);
    await tester.ensureVisible(find.text('alma'));
    await tester.tap(find.text('alma'));
    await settle(tester);
    expect(find.text('Верно'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: BankScreen(store: store)));
    await settle(tester);
    await tester.tap(find.byTooltip('Удалить alma'));
    await settle(tester);
    expect(find.text('alma'), findsNothing);
    expect((await store.cards()).length, 4);
  });
}
