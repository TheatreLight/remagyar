import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/models/word_card.dart';

import 'widget_test.dart' show settle;

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
  Finder translation(int n) => find.byWidgetPredicate(
    (w) => w is TextField && w.decoration?.labelText == 'Русский перевод $n *',
  );

  test('search handles languages, alternatives, NFC, case and literal regex characters', () {
    const card = WordCard(
      hungarian: 'ház',
      russian: ['дом', 'большое здание', 'a.*[b'],
    );
    for (final q in ['', ' HÁ ', 'ha\u0301z', 'ДОМ', 'здани', '.*[']) {
      expect(matchesCardSearch(card, q), true, reason: q);
    }
    for (final q in ['haz', '^h', '.*z', 'несуществующее']) {
      expect(matchesCardSearch(card, q), false, reason: q);
    }
  });

  testWidgets('bank filters on input and updates matches after editing', (
    tester,
  ) async {
    await store.saveCard(
      const WordCard(hungarian: 'ház', russian: ['дом', 'здание']),
    );
    await store.saveCard(
      const WordCard(hungarian: 'házi', russian: ['домашний']),
    );
    await store.saveCard(
      const WordCard(hungarian: 'alma', russian: ['яблоко']),
    );
    await tester.pumpWidget(MaterialApp(home: BankScreen(store: store)));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('bankSearch')), 'HÁ');
    await settle(tester);
    expect(find.text('ház'), findsOneWidget);
    expect(find.text('házi'), findsOneWidget);
    expect(find.text('alma'), findsNothing);
    await tester.enterText(find.byKey(const Key('bankSearch')), 'здани');
    await settle(tester);
    expect(find.text('házi'), findsNothing);
    await tester.tap(find.text('ház'));
    await settle(tester);
    await tester.enterText(translation(2), 'строение');
    await tester.tap(find.text('Сохранить'));
    await settle(tester);
    expect(find.text('Слова не найдены'), findsOneWidget);
    await tester.tap(find.byTooltip('Очистить поиск'));
    await settle(tester);
    expect(find.text('ház'), findsOneWidget);
    expect(find.text('alma'), findsOneWidget);
  });

  testWidgets(
    'study edit refreshes current card and survives next/back navigation',
    (tester) async {
      final id = await store.saveCard(
        const WordCard(hungarian: 'ház', russian: ['дом']),
      );
      await store.saveCard(
        const WordCard(hungarian: 'alma', russian: ['яблоко']),
      );
      await store.record(id, true, DateTime.utc(2026));
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
      await tester.tap(find.text('Показать перевод'));
      await settle(tester);
      await tester.tap(find.byTooltip('Редактировать слово'));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('cardHungarian')), 'házikó');
      await tester.enterText(translation(1), 'домик');
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      expect(find.text('házikó'), findsOneWidget);
      expect(find.text('домик'), findsOneWidget);
      expect((await store.card(id)).lastSuccessAt, isNull);
      await tester.ensureVisible(find.text('Вперёд'));
      await settle(tester);
      await tester.tap(find.text('Вперёд'));
      await settle(tester);
      expect(find.text('alma'), findsOneWidget);
      await tester.tap(find.text('Назад'));
      await settle(tester);
      expect(find.text('házikó'), findsOneWidget);
      expect(find.text('Карточка 1 из 2'), findsOneWidget);
      expect(cards.first.hungarian, 'ház');
    },
  );
}
