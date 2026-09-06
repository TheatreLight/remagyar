import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android manually create, reopen and edit card and groups', (
    tester,
  ) async {
    final path = p.join(await getDatabasesPath(), 'editor-integration-only.db');
    await deleteDatabase(path);
    final store = await CardStore.open(path: path);
    await tester.pumpWidget(ReMagyarApp(store: store));
    await tester.pumpAndSettle();
    Future<void> tap(String text, {double delta = 250}) async {
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text(text),
        delta,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(text));
      await tester.pumpAndSettle();
    }

    Finder translation(int n) => find.byWidgetPredicate(
      (w) =>
          w is TextField && w.decoration?.labelText == 'Русский перевод $n *',
    );
    await tap('Добавить слово');
    await tester.enterText(find.byKey(const Key('cardHungarian')), 'ház');
    await tester.enterText(translation(1), 'дом');
    await tap('Добавить перевод');
    await tester.enterText(translation(2), 'здание');
    await tap('Создать группу');
    await tester.enterText(find.byKey(const Key('editorNewGroup')), 'Жильё');
    await tester.tap(find.text('Добавить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    final card = (await store.cards()).single;
    expect(card.russian, ['дом', 'здание']);
    expect((await store.cardGroupIds(card.id!)).length, 1);
    final time = DateTime.utc(2026);
    await store.record(card.id!, true, time);
    await tap('Банк слов', delta: -250);
    await tester.enterText(find.byKey(const Key('bankSearch')), 'ЗДА');
    await tester.pumpAndSettle();
    expect(find.text('ház'), findsOneWidget);
    await tester.tap(find.text('ház'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(translation(2)).controller!.text, 'здание');
    await tester.ensureVisible(find.byKey(const Key('cardExample')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cardExample')), 'Ez egy ház.');
    await tap('Без группы');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(
      (await store.card(card.id!)).lastSuccessAt,
      time.millisecondsSinceEpoch,
    );
    expect(await store.cardGroupIds(card.id!), isEmpty);
    await tester.tap(find.text('ház'));
    await tester.pumpAndSettle();
    await tester.enterText(translation(1), 'домик');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect((await store.card(card.id!)).lastSuccessAt, isNull);
    await tester.tap(find.byTooltip('Назад'));
    await tester.pumpAndSettle();
    await tap('Изучение слов', delta: -250);
    await tester.tap(find.byTooltip('Редактировать слово'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('cardHungarian')), 'házikó');
    await tester.tap(find.text('Сохранить'));
    await tester.pumpAndSettle();
    expect(find.text('házikó'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await store.close();
    final reopened = await CardStore.open(path: path);
    expect((await reopened.card(card.id!)).russian, ['домик', 'здание']);
    expect((await reopened.card(card.id!)).example, 'Ez egy ház.');
    await reopened.close();
    await deleteDatabase(path);
  });
}
