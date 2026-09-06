import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/import/zip_import.dart';
import 'package:remagyar/models/word_group.dart';

import '../test/fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android import, study, review, reopen, rollback and delete', (
    tester,
  ) async {
    final path = p.join(await getDatabasesPath(), 'integration-only.db');
    await deleteDatabase(path);
    var store = await CardStore.open(path: path);
    final bytes = makeZip(
      '${header}alma,яблоко,Ez egy alma.,images/a.png\nház,дом|здание,,\nvíz,вода,,\nkenyér,хлеб,,',
      images: {'images/a.png': png()},
    );
    await tester.pumpWidget(
      ReMagyarApp(store: store, pickArchive: () async => bytes),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Загрузить ZIP'), 250);
    await tester.tap(find.text('Загрузить ZIP'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('newGroupName')),
      'Тестовая группа',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Импортировать'));
    await tester.tap(find.text('Импортировать'));
    await tester.pumpAndSettle();
    expect(find.text('Импорт завершён'), findsOneWidget);
    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    final importedGroup = (await store.groups()).single;
    expect(
      (await store.cards(selection: GroupSelection(ids: {importedGroup.id})))
          .length,
      4,
    );
    await tester.scrollUntilVisible(find.byKey(const Key('groupFilter')), -250);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('groupFilter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Тестовая группа'));
    await tester.tap(find.text('Применить'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Изучение слов'), -250);
    await tester.tap(find.text('Изучение слов'));
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsOneWidget);
    await tester.ensureVisible(find.text('Показать перевод'));
    await tester.tap(find.text('Показать перевод'));
    await tester.pumpAndSettle();
    expect(find.text('яблоко'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    expect((await store.cards()).first.lastSuccessAt, isNull);
    await tester.ensureVisible(find.text('Повторение'));
    await tester.tap(find.text('Повторение'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('typedAnswer')));
    final reviewCards = tester
        .widget<LessonScreen>(find.byType(LessonScreen))
        .cards;
    expect(reviewCards.map((c) => c.id).toSet().length, 4);
    await tester.enterText(
      find.byKey(const Key('typedAnswer')),
      ' ${reviewCards[0].russian.first.toUpperCase()} ',
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Проверить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Проверить'));
    await tester.pumpAndSettle();
    expect(find.text('Верно'), findsOneWidget);
    await tester.ensureVisible(find.text('Далее'));
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4 варианта'));
    await tester.pumpAndSettle();
    final choice = find.widgetWithText(
      OutlinedButton,
      reviewCards[1].russian.firstWhere(
        (answer) =>
            find.widgetWithText(OutlinedButton, answer).evaluate().isNotEmpty,
      ),
    );
    await tester.ensureVisible(choice);
    await tester.tap(choice);
    await tester.pumpAndSettle();
    expect(find.text('Верно'), findsOneWidget);
    await tester.tap(find.text('Далее'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Показать ответ'));
    await tester.tap(find.text('Показать ответ'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Не получилось'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    final before = await store.cards();
    expect(
      before.singleWhere((c) => c.id == reviewCards[0].id).lastResult,
      true,
    );
    expect(
      before.singleWhere((c) => c.id == reviewCards[1].id).lastResult,
      true,
    );
    expect(
      before.singleWhere((c) => c.id == reviewCards[2].id).lastResult,
      false,
    );
    await tester.pumpWidget(const SizedBox());
    await store.close();
    store = await CardStore.open(path: path);
    expect(
      (await store.cards()).first.lastSuccessAt,
      before.first.lastSuccessAt,
    );
    expect(await store.image(before.first.id!), png());
    expect((await store.importRows(parseZip(bytes))).added, 0);
    expect(
      () => parseZip(makeZip('${header}new,новый,,\nbad,')),
      throwsFormatException,
    );
    await store.db.execute(
      "CREATE TRIGGER integration_failure BEFORE INSERT ON cards WHEN NEW.hungarian = 'fail' BEGIN SELECT RAISE(ABORT, 'test'); END",
    );
    await expectLater(
      store.importRows(
        parseZip(makeZip('${header}new,новый,,\nfail,ошибка,,')),
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.cards()).length, 4);
    await store.delete(before.first.id!);
    expect(await store.image(before.first.id!), isNull);
    await store.importRows([parseZip(bytes).first]);
    expect((await store.cards()).last.lastSuccessAt, isNull);
    await store.importRows([parseZip(bytes)[1]], groupName: 'Общая');
    await store.deleteGroup(importedGroup.id, deleteWords: true);
    expect((await store.cards()).map((c) => c.hungarian).toSet(), {
      'alma',
      'ház',
    });
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    await tester.pumpWidget(ReMagyarApp(store: store));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Банк слов'), 250);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Банк слов'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Удалить все'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Удалить все'));
    await tester.pumpAndSettle();
    expect(find.text('Банк пока пуст'), findsOneWidget);
    expect(await store.cards(), isEmpty);
    expect(await store.db.query('card_to_groups'), isEmpty);
    expect((await store.groups()).single.name, 'Общая');
    await tester.pumpWidget(const SizedBox());
    await store.close();
    await deleteDatabase(path);
  });
}
