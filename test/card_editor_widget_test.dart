import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/app.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/models/word_card.dart';
import 'package:remagyar/screens/card_editor.dart';

import 'fixtures.dart';
import 'widget_test.dart' show settle;

Finder translation(int n) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == 'Русский перевод $n *',
);

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
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await settle(tester);
    await tester.tap(finder);
    await settle(tester);
  }

  testWidgets(
    'home add and bank edit share form, translations and group selection',
    (tester) async {
      await store.importRows([], groupName: 'A');
      await store.importRows([], groupName: 'B');
      await tester.pumpWidget(ReMagyarApp(store: store));
      await settle(tester);
      await tester.scrollUntilVisible(find.text('Добавить слово'), 250);
      await settle(tester);
      await tester.tap(find.text('Добавить слово'));
      await settle(tester);
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      expect(find.text('Обязательное поле'), findsNWidgets(2));
      await tester.enterText(find.byKey(const Key('cardHungarian')), 'ház');
      await tester.enterText(translation(1), 'дом');
      for (var i = 2; i <= 5; i++) {
        await tapVisible(tester, find.text('Добавить перевод'));
        await tester.enterText(translation(i), 'значение $i');
      }
      expect(find.text('Добавить перевод'), findsNothing);
      await tapVisible(tester, find.byTooltip('Удалить перевод 5'));
      await tapVisible(tester, find.text('Добавить перевод'));
      await tester.enterText(translation(5), 'значение 5');
      await tester.scrollUntilVisible(
        find.text('Создать группу'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('Создать группу'));
      await settle(tester);
      await tester.enterText(
        find.byKey(const Key('editorNewGroup')),
        'Моя группа',
      );
      await tester.tap(find.text('Добавить'));
      await settle(tester);
      expect((await store.groups()).length, 2);
      await tapVisible(tester, find.text('A'));
      await tapVisible(tester, find.text('B'));
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      final saved = (await store.cards()).single;
      expect(saved.russian.length, 5);
      expect((await store.cardGroupIds(saved.id!)).length, 3);
      await tester.scrollUntilVisible(find.text('Банк слов'), -250);
      await settle(tester);
      await tester.tap(find.text('Банк слов'));
      await settle(tester);
      await tester.tap(find.text('ház'));
      await settle(tester);
      expect(find.text('Редактировать слово'), findsOneWidget);
      expect(
        tester.widget<TextField>(translation(2)).controller!.text,
        'значение 2',
      );
      await tester.scrollUntilVisible(
        find.text('Без группы'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await settle(tester);
      await tester.tap(find.text('Без группы'));
      await tester.tap(find.text('Сохранить'));
      await settle(tester);
      expect(await store.cardGroupIds(saved.id!), isEmpty);
    },
  );

  testWidgets('cancel leaves edits and pending new group unsaved', (
    tester,
  ) async {
    final id = await store.saveCard(
      const WordCard(hungarian: 'alma', russian: ['яблоко']),
    );
    await tester.pumpWidget(MaterialApp(home: BankScreen(store: store)));
    await settle(tester);
    await tester.tap(find.text('alma'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cardHungarian')), 'changed');
    await tester.scrollUntilVisible(
      find.text('Создать группу'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);
    await tester.tap(find.text('Создать группу'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('editorNewGroup')), 'Черновик');
    await tester.tap(find.text('Добавить'));
    await settle(tester);
    await tester.tap(find.byType(BackButton));
    await settle(tester);
    expect((await store.card(id)).hungarian, 'alma');
    expect(await store.groups(), isEmpty);
  });

  testWidgets(
    'image cancel, invalid replacement, valid replacement and removal',
    (tester) async {
      final id = await store.saveCard(
        WordCard(hungarian: 'alma', russian: ['яблоко'], image: png()),
      );
      Uint8List? picked;
      await tester.pumpWidget(
        MaterialApp(
          home: CardEditor(
            store: store,
            cardId: id,
            pickImage: () async => picked,
          ),
        ),
      );
      await settle(tester);
      expect(find.byType(Image), findsOneWidget);
      await tapVisible(tester, find.text('Заменить изображение'));
      expect(find.byType(Image), findsOneWidget);
      picked = Uint8List.fromList([1, 2]);
      await tester.runAsync(() async {
        await tester.tap(find.text('Заменить изображение'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settle(tester);
      expect(
        find.text('Выберите корректное изображение PNG или JPEG.'),
        findsOneWidget,
      );
      picked = png();
      await tester.runAsync(() async {
        await tester.tap(find.text('Заменить изображение'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await settle(tester);
      expect(find.byType(Image), findsOneWidget);
      await tapVisible(tester, find.text('Удалить изображение'));
      expect(find.byType(Image), findsNothing);
      expect((await store.card(id)).image, png());
    },
  );

  testWidgets('duplicate save keeps form open and existing data', (
    tester,
  ) async {
    await store.saveCard(
      const WordCard(hungarian: 'alma', russian: ['яблоко']),
    );
    await tester.pumpWidget(MaterialApp(home: CardEditor(store: store)));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('cardHungarian')), 'alma');
    await tester.enterText(translation(1), 'другое');
    await tester.tap(find.text('Сохранить'));
    await settle(tester);
    expect(
      find.text('Карточка с таким венгерским словом уже существует.'),
      findsOneWidget,
    );
    expect(find.byType(CardEditor), findsOneWidget);
    expect((await store.cards()).single.russian, ['яблоко']);
  });
}
