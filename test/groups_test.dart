import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/import/zip_import.dart';
import 'package:remagyar/models/word_group.dart';

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
  final rows = parseZip(makeZip(words));

  test('import links duplicates without changing card or progress; names reuse normalized group', () async {
    await store.importRows(rows, groupName: ' ЕДА ');
    final food = (await store.groups()).single;
    final card = (await store.cards()).first;
    await store.record(card.id!, true, DateTime.utc(2026));
    final repeat = await store.importRows(rows, groupName: 'еда');
    expect((await store.groups()).length, 1);
    expect(repeat.added, 0);
    expect(repeat.linked, 0);
    final shopping = await store.importRows([rows.first], groupName: 'Покупки');
    expect(shopping.added, 0);
    expect(shopping.linked, 1);
    expect(
      (await store.cards()).first.lastSuccessAt,
      DateTime.utc(2026).millisecondsSinceEpoch,
    );
    await store.importRows(rows);
    expect(
      (await store.cards(selection: GroupSelection(ids: {food.id}))).length,
      5,
    );
    expect(
      await store.cards(selection: GroupSelection(ungrouped: true)),
      isEmpty,
    );
  });

  test('group unions deduplicate cards; ungrouped and global counters remain independent', () async {
    await store.importRows([rows[0], rows[1]], groupName: 'A');
    await store.importRows([rows[1], rows[2]], groupName: 'B');
    await store.importRows([rows[3]]);
    final groups = await store.groups();
    final union = GroupSelection(ids: groups.map((g) => g.id).toSet());
    expect((await store.cards(selection: union)).map((c) => c.hungarian), [
      'alma',
      'ház',
      'víz',
    ]);
    expect(
      (await store.cards(selection: GroupSelection(ungrouped: true)))
          .single
          .hungarian,
      'kenyér',
    );
    expect(
      (await store.cards(
        selection: GroupSelection(ids: union.ids, ungrouped: true),
      )).length,
      4,
    );
    expect((await store.cards(selection: GroupSelection())).length, 4);
    expect(await store.overdueCount(), 4);
    final card = (await store.cards()).first;
    await store.record(card.id!, true, DateTime.now());
    expect((await store.cards(selection: union, overdue: true)).length, 2);
    expect(await store.overdueCount(), 3);
  });

  test('rename is unique, empty names fail and deleting group alone preserves all cards', () async {
    await store.importRows([rows[0]], groupName: 'A');
    await store.importRows([rows[1]], groupName: 'B');
    final groups = await store.groups();
    await store.renameGroup(groups[0].id, '  Новое  ');
    expect((await store.groups()).any((g) => g.name == 'Новое'), true);
    await expectLater(
      store.renameGroup(groups[1].id, 'НОВОЕ'),
      throwsFormatException,
    );
    await expectLater(
      store.renameGroup(groups[1].id, ' '),
      throwsFormatException,
    );
    await expectLater(store.renameGroup(-1, 'unknown'), throwsFormatException);
    await store.deleteGroup(groups[0].id);
    expect((await store.cards()).length, 2);
    expect(
      (await store.cards(selection: GroupSelection(ungrouped: true)))
          .single
          .hungarian,
      'alma',
    );
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
  });

  test('delete with words removes exclusive cards and retains shared cards with progress', () async {
    await store.importRows([rows[0], rows[1]], groupName: 'A');
    await store.importRows([rows[1], rows[2]], groupName: 'B');
    await store.importRows([rows[3]]);
    final groups = await store.groups();
    final shared = (await store.cards())[1];
    await store.record(shared.id!, true, DateTime.utc(2026));
    await store.deleteGroup(groups[0].id, deleteWords: true);
    expect((await store.cards()).map((c) => c.hungarian), [
      'ház',
      'víz',
      'kenyér',
    ]);
    expect(
      (await store.cards()).first.lastSuccessAt,
      DateTime.utc(2026).millisecondsSinceEpoch,
    );
    expect(
      (await store.cards(selection: GroupSelection(ids: {groups[1].id})))
          .length,
      2,
    );
    await store.delete(shared.id!);
    expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
    expect(
      (await store.cards(selection: GroupSelection(ids: {groups[1].id})))
          .single
          .hungarian,
      'víz',
    );
  });

  test('failed import rolls back new group, links and cards', () async {
    await store.importRows([rows.first]);
    await store.db.execute(
      "CREATE TRIGGER fail_group_import BEFORE INSERT ON cards WHEN NEW.hungarian = 'ház' BEGIN SELECT RAISE(ABORT, 'forced'); END",
    );
    await expectLater(
      store.importRows(rows, groupName: 'Rollback'),
      throwsA(isA<DatabaseException>()),
    );
    expect(await store.groups(), isEmpty);
    expect((await store.cards()).length, 1);
    expect(await store.db.query('card_to_groups'), isEmpty);
    await expectLater(
      store.importRows(rows, groupId: -1),
      throwsFormatException,
    );
    await expectLater(
      store.importRows(rows, groupId: -1, groupName: 'X'),
      throwsFormatException,
    );
  });

  test(
    'v1 migration keeps IDs, image and timestamp, creates ungrouped cards',
    () async {
      final dir = await Directory.systemTemp.createTemp('remagyar-migration-');
      final path = '${dir.path}/v1.db';
      final old = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE cards (id INTEGER PRIMARY KEY AUTOINCREMENT, hungarian TEXT NOT NULL UNIQUE COLLATE BINARY, russian TEXT NOT NULL, example TEXT NOT NULL, image BLOB, last_result INTEGER, last_success_at INTEGER)',
            );
            await db.execute(
              'CREATE INDEX cards_success ON cards(last_success_at)',
            );
          },
        ),
      );
      await old.insert('cards', {
        'id': 7,
        'hungarian': 'alma',
        'russian': '["яблоко"]',
        'example': '',
        'image': png(),
        'last_result': 1,
        'last_success_at': 12345,
      });
      await old.close();
      final migrated = await CardStore.open(
        factory: databaseFactoryFfi,
        path: path,
      );
      try {
        final card = (await migrated.cards(
          selection: GroupSelection(ungrouped: true),
        )).single;
        expect(card.id, 7);
        expect(card.lastSuccessAt, 12345);
        expect(await migrated.image(7), png());
        expect(await migrated.groups(), isEmpty);
        await migrated.importRows([rows.first], groupName: 'Новая');
        expect((await migrated.cards()).single.id, 7);
        expect(await migrated.db.getVersion(), 2);
      } finally {
        await migrated.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
