import 'dart:io';

import 'package:sqflite/sqflite.dart' show Sqflite;

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:remagyar/data/store.dart';
import 'package:remagyar/import/zip_import.dart';

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
  tearDown(() async {
    await store.close();
  });
  test(
    'delete all removes cards and links, preserves groups; failure is atomic',
    () async {
      await store.importRows(
        parseZip(
          makeZip(
            '${header}alma,яблоко,,images/a.png\nház,дом,,',
            images: {'images/a.png': png()},
          ),
        ),
        groupName: 'Группа',
      );
      final first = (await store.cards()).first;
      await store.record(first.id!, true, DateTime.utc(2026));
      await store.db.execute(
        "CREATE TRIGGER fail_delete BEFORE DELETE ON cards WHEN OLD.hungarian = 'ház' BEGIN SELECT RAISE(ABORT, 'forced'); END",
      );
      await expectLater(
        store.deleteAllCards(),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.cards()).length, 2);
      expect((await store.db.query('card_to_groups')).length, 2);
      expect(await store.image(first.id!), png());
      expect((await store.cards()).first.lastSuccessAt, isNotNull);
      await store.db.execute('DROP TRIGGER fail_delete');
      await store.deleteAllCards();
      expect(await store.cards(), isEmpty);
      expect(await store.image(first.id!), isNull);
      expect(await store.overdueCount(), 0);
      expect(await store.db.query('card_to_groups'), isEmpty);
      expect((await store.groups()).single.name, 'Группа');
      expect(await store.db.rawQuery('PRAGMA foreign_key_check'), isEmpty);
      await store.deleteAllCards();
    },
  );
  test('multiple CSVs share duplicate checks and one transaction', () async {
    final rows = parseZip(
      makeZip(
        '${header}alma,яблоко,,',
        csvName: 'first.csv',
        images: {'second.csv': raw('${header}alma,иной,,\nház,дом,,')},
      ),
    );
    final report = await store.importRows(rows);
    expect(report.added, 2);
    expect(report.warnings.single, startsWith('second.csv: Запись 2:'));
    expect((await store.cards()).first.russian, ['яблоко']);

    await store.db.execute(
      "CREATE TRIGGER multi_fail BEFORE INSERT ON cards WHEN NEW.hungarian = 'stop' BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
    );
    final failing = parseZip(
      makeZip(
        '${header}new,новый,,images/a.png',
        images: {
          'images/a.png': png(),
          'later.csv': raw('${header}stop,стоп,,'),
        },
      ),
    );
    await expectLater(
      store.importRows(failing),
      throwsA(isA<DatabaseException>()),
    );
    expect((await store.cards()).map((c) => c.hungarian), ['alma', 'ház']);
    expect(
      Sqflite.firstIntValue(
        await store.db.rawQuery('SELECT COUNT(image) FROM cards'),
      ),
      0,
    );
  });
  test('duplicates preserve previous fields, image and progress; deletion resets', () async {
    final rows = parseZip(
      makeZip(
        '${header}alma,яблоко,,images/a.png\nalma,иной,,\nAlma,другой,,\nha\u0301z,дом,,\nház,здание,,',
        images: {'images/a.png': png()},
      ),
    );
    final report = await store.importRows(rows);
    expect(report.added, 3);
    expect(report.warnings.length, 2);
    final first = (await store.cards()).first;
    final now = DateTime.utc(2026, 9, 5);
    await store.record(first.id!, true, now);
    final again = await store.importRows(rows);
    expect(again.added, 0);
    expect(again.warnings.length, 5);
    final kept = (await store.cards()).first;
    expect(kept.lastSuccessAt, now.millisecondsSinceEpoch);
    expect(kept.russian, ['яблоко']);
    expect(await store.image(first.id!), png());
    await store.delete(first.id!);
    expect(await store.image(first.id!), isNull);
    await store.importRows([rows.first]);
    expect((await store.cards()).last.lastSuccessAt, isNull);
    await expectLater(store.record(-1, true, now), throwsStateError);
  });
  test(
    'real SQLite rolls back earlier inserts and BLOB on later write failure',
    () async {
      await store.importRows(parseZip(makeZip('${header}old,старый,,')));
      await store.db.execute(
        "CREATE TRIGGER fail_insert BEFORE INSERT ON cards WHEN NEW.hungarian = 'stop' BEGIN SELECT RAISE(ABORT, 'forced failure'); END",
      );
      final rows = parseZip(
        makeZip(
          '${header}new,новый,,images/a.png\nstop,стоп,,',
          images: {'images/a.png': png()},
        ),
      );
      await expectLater(
        store.importRows(rows),
        throwsA(isA<DatabaseException>()),
      );
      expect((await store.cards()).map((c) => c.hungarian), ['old']);
      expect(
        Sqflite.firstIntValue(
          await store.db.rawQuery('SELECT COUNT(image) FROM cards'),
        ),
        0,
      );
      expect(
        () => parseZip(makeZip('${header}valid,да,,\nbroken,')),
        throwsFormatException,
      );
      expect((await store.cards()).length, 1);
    },
  );
  test(
    'five-day boundary, sorting and failure preserve successful timestamp',
    () async {
      await store.importRows(parseZip(makeZip(words)));
      final bank = await store.cards();
      final now = DateTime.utc(2026, 9, 5);
      final boundary = now.subtract(CardStore.age);
      await store.record(bank[0].id!, true, boundary);
      await store.record(
        bank[1].id!,
        true,
        boundary.add(const Duration(milliseconds: 1)),
      );
      await store.record(
        bank[2].id!,
        true,
        boundary.subtract(const Duration(milliseconds: 1)),
      );
      await store.record(bank[0].id!, false, now);
      expect(
        (await store.cards()).first.lastSuccessAt,
        boundary.millisecondsSinceEpoch,
      );
      expect((await store.cards()).first.lastResult, false);
      expect(await store.overdueCount(now: now), 4);
      expect(
        (await store.cards(
          review: true,
          overdue: true,
          now: now,
        )).map((c) => c.hungarian),
        ['kenyér', 'nap', 'víz', 'alma'],
      );
      await store.record(bank[0].id!, true, now);
      expect(await store.overdueCount(now: now), 3);
    },
  );
  test(
    'file database retains image and results after close and reopen',
    () async {
      final dir = await Directory.systemTemp.createTemp('remagyar-test-');
      final path = '${dir.path}/words.db';
      var disk = await CardStore.open(factory: databaseFactoryFfi, path: path);
      try {
        await disk.importRows(
          parseZip(
            makeZip(
              '${header}alma,яблоко,,images/a.png',
              images: {'images/a.png': png()},
            ),
          ),
        );
        final id = (await disk.cards()).single.id!;
        await disk.record(id, true, DateTime.utc(2026));
        await disk.close();
        disk = await CardStore.open(factory: databaseFactoryFfi, path: path);
        expect((await disk.cards()).single.lastResult, true);
        expect(await disk.image(id), png());
      } finally {
        await disk.close();
        await dir.delete(recursive: true);
      }
    },
  );
}
