import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/models/word_card.dart';
import 'package:remagyar/screens/card_editor.dart';
import 'package:image/image.dart' as img;

import 'dart:typed_data';

import 'fixtures.dart';

void main() {
  sqfliteFfiInit();
  late CardStore store;
  setUp(() async {
    store = await CardStore.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
  });
  tearDown(() => store.close());

  test('create with five translations and groups, then replace memberships and image', () async {
    final id = await store.saveCard(
      WordCard(
        hungarian: ' ha\u0301z ',
        russian: ['дом', 'здание', 'жильё', 'строение', 'палата'],
        image: png(),
      ),
      newGroupNames: [' Дом ', 'дом', 'Другое'],
    );
    final saved = await store.card(id);
    expect(saved.hungarian, 'ház');
    expect(saved.russian.length, 5);
    expect(saved.image, png());
    expect((await store.cardGroupIds(id)).length, 2);
    expect((await store.groups()).length, 2);
    final group = (await store.groups()).first;
    await store.saveCard(
      WordCard(
        id: id,
        hungarian: saved.hungarian,
        russian: saved.russian,
        example: ' Пример ',
      ),
      groupIds: {group.id},
    );
    expect(await store.cardGroupIds(id), {group.id});
    expect((await store.card(id)).image, isNull);
    expect((await store.card(id)).example, 'Пример');
    await store.saveCard(
      WordCard(id: id, hungarian: saved.hungarian, russian: saved.russian),
    );
    expect(await store.cardGroupIds(id), isEmpty);
    expect((await store.groups()).length, 2);
  });

  test('only word or translations changes reset progress', () async {
    final id = await store.saveCard(
      const WordCard(hungarian: 'alma', russian: ['яблоко']),
    );
    final time = DateTime.utc(2026);
    await store.record(id, true, time);
    await store.saveCard(
      WordCard(
        id: id,
        hungarian: ' alma ',
        russian: ['яблоко'],
        example: 'Пример',
        image: png(),
      ),
      newGroupNames: ['Еда'],
    );
    expect((await store.card(id)).lastSuccessAt, time.millisecondsSinceEpoch);
    expect((await store.card(id)).lastResult, true);
    await store.saveCard(
      WordCard(id: id, hungarian: 'alma', russian: ['яблоко', 'яблочко']),
    );
    expect((await store.card(id)).lastSuccessAt, isNull);
    expect((await store.card(id)).lastResult, isNull);
    await store.record(id, true, time);
    await store.saveCard(
      WordCard(id: id, hungarian: 'almák', russian: ['яблоко', 'яблочко']),
    );
    expect((await store.card(id)).lastSuccessAt, isNull);
    expect((await store.card(id)).lastResult, isNull);
  });

  test('duplicates reject create and edit without changing card, progress or groups', () async {
    await store.saveCard(const WordCard(hungarian: 'ház', russian: ['дом']));
    final id = await store.saveCard(
      const WordCard(hungarian: 'alma', russian: ['яблоко']),
    );
    await store.record(id, true, DateTime.utc(2026));
    for (final cardId in [null, id]) {
      await expectLater(
        store.saveCard(
          WordCard(id: cardId, hungarian: ' ha\u0301z ', russian: ['другой']),
          newGroupNames: ['Не создавать'],
        ),
        throwsFormatException,
      );
    }
    expect((await store.card(id)).hungarian, 'alma');
    expect((await store.card(id)).lastResult, true);
    expect(await store.groups(), isEmpty);
    expect((await store.cards()).length, 2);
  });

  test('mandatory values, limit and missing entities are validated', () async {
    for (final draft in [
      const WordCard(hungarian: ' ', russian: ['дом']),
      const WordCard(hungarian: 'a', russian: []),
      const WordCard(hungarian: 'a', russian: ['дом', ' ']),
      WordCard(hungarian: 'a', russian: List.filled(6, 'дом')),
      const WordCard(id: 999, hungarian: 'a', russian: ['дом']),
    ]) {
      await expectLater(store.saveCard(draft), throwsFormatException);
    }
    const draft = WordCard(hungarian: 'a', russian: ['дом']);
    await expectLater(
      store.saveCard(draft, groupIds: {999}),
      throwsFormatException,
    );
    await expectLater(
      store.saveCard(draft, newGroupNames: [' ']),
      throwsFormatException,
    );
    await expectLater(store.card(999), throwsFormatException);
    expect(await store.cards(), isEmpty);
  });

  test('failure after update rolls back card, progress, new groups and memberships', () async {
    final id = await store.saveCard(
      WordCard(hungarian: 'alma', russian: ['яблоко'], image: png()),
      newGroupNames: ['Старая'],
    );
    final oldIds = await store.cardGroupIds(id);
    await store.record(id, true, DateTime.utc(2026));
    await store.db.execute(
      "CREATE TRIGGER fail_link BEFORE INSERT ON card_to_groups BEGIN SELECT RAISE(ABORT, 'forced'); END",
    );
    await expectLater(
      store.saveCard(
        WordCard(id: id, hungarian: 'новое', russian: ['новый']),
        newGroupNames: ['Новая'],
      ),
      throwsA(isA<DatabaseException>()),
    );
    final old = await store.card(id);
    expect(old.hungarian, 'alma');
    expect(old.image, png());
    expect(old.lastResult, true);
    expect(await store.cardGroupIds(id), oldIds);
    expect((await store.groups()).single.name, 'Старая');
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test(
    'image picker validation accepts PNG/JPEG and rejects damaged bytes',
    () {
      expect(validCardImage(png()), true);
      expect(
        validCardImage(
          Uint8List.fromList(img.encodeJpg(img.Image(width: 2, height: 2))),
        ),
        true,
      );
      expect(validCardImage(Uint8List.fromList([1, 2, 3])), false);
    },
  );
}
