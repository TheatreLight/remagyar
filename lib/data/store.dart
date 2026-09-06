import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../models/word_card.dart';
import '../models/word_group.dart';

class CardStore {
  CardStore(this.db);
  final Database db;
  static const age = Duration(days: 5);
  static Future<CardStore> open({
    DatabaseFactory? factory,
    String? path,
  }) async {
    final f = factory ?? databaseFactory;
    final db = await f.openDatabase(
      path ?? p.join(await f.getDatabasesPath(), 'remagyar.db'),
      options: OpenDatabaseOptions(
        version: 2,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE cards (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          hungarian TEXT NOT NULL UNIQUE COLLATE BINARY,
          russian TEXT NOT NULL, example TEXT NOT NULL,
          image BLOB, last_result INTEGER, last_success_at INTEGER)''');
          await db.execute(
            'CREATE INDEX cards_success ON cards(last_success_at)',
          );
          await _createGroups(db);
        },
        onUpgrade: (db, oldVersion, _) async {
          if (oldVersion < 2) {
            await _createGroups(db);
          }
        },
      ),
    );
    return CardStore(db);
  }

  static Future<void> _createGroups(Database db) async {
    await db.execute(
      'CREATE TABLE groups (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, name_key TEXT NOT NULL UNIQUE)',
    );
    await db.execute('''CREATE TABLE card_to_groups (
      card_id INTEGER NOT NULL REFERENCES cards(id) ON DELETE CASCADE,
      group_id INTEGER NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
      PRIMARY KEY(card_id, group_id))''');
    await db.execute(
      'CREATE INDEX card_to_groups_group ON card_to_groups(group_id)',
    );
  }

  Future<List<WordGroup>> groups() async => (await db.query(
    'groups',
    orderBy: 'name_key, id',
  )).map((r) => WordGroup(r['id'] as int, r['name'] as String)).toList();

  Future<void> renameGroup(int id, String name) async {
    final cleaned = cleanGroupName(name);
    if (cleaned.isEmpty) {
      throw const FormatException('Введите название группы.');
    }
    await db.transaction((txn) async {
      final existing = await txn.query(
        'groups',
        columns: ['id'],
        where: 'name_key = ? AND id != ?',
        whereArgs: [groupNameKey(cleaned), id],
      );
      if (existing.isNotEmpty) {
        throw const FormatException('Группа с таким названием уже существует.');
      }
      final changed = await txn.update(
        'groups',
        {'name': cleaned, 'name_key': groupNameKey(cleaned)},
        where: 'id = ?',
        whereArgs: [id],
      );
      if (changed != 1) {
        throw const FormatException('Группа больше не существует.');
      }
    });
  }

  Future<void> deleteGroup(int id, {bool deleteWords = false}) =>
      db.transaction((txn) async {
        if (deleteWords) {
          await txn.rawDelete(
            '''DELETE FROM cards WHERE id IN
        (SELECT card_id FROM card_to_groups WHERE group_id = ?)
        AND NOT EXISTS (SELECT 1 FROM card_to_groups other
          WHERE other.card_id = cards.id AND other.group_id != ?)''',
            [id, id],
          );
        }
        await txn.delete('groups', where: 'id = ?', whereArgs: [id]);
      });

  WordCard _card(Map<String, Object?> row) => WordCard(
    id: row['id'] as int,
    hungarian: row['hungarian'] as String,
    russian: (jsonDecode(row['russian'] as String) as List).cast<String>(),
    example: row['example'] as String,
    image: row['image'] as Uint8List?,
    lastResult: row['last_result'] == null ? null : row['last_result'] == 1,
    lastSuccessAt: row['last_success_at'] as int?,
  );
  Future<List<WordCard>> cards({
    bool review = false,
    bool overdue = false,
    DateTime? now,
    GroupSelection? selection,
  }) async {
    final conditions = <String>[];
    final args = <Object?>[];
    if (overdue) {
      conditions.add('(last_success_at IS NULL OR last_success_at <= ?)');
      args.add(
        (now ?? DateTime.now()).toUtc().subtract(age).millisecondsSinceEpoch,
      );
    }
    if (selection != null && !selection.all) {
      final groupConditions = <String>[];
      if (selection.ids.isNotEmpty) {
        groupConditions.add(
          'id IN (SELECT card_id FROM card_to_groups WHERE group_id IN (${List.filled(selection.ids.length, '?').join(',')}))',
        );
        args.addAll(selection.ids);
      }
      if (selection.ungrouped) {
        groupConditions.add(
          'NOT EXISTS (SELECT 1 FROM card_to_groups WHERE card_id = cards.id)',
        );
      }
      conditions.add('(${groupConditions.join(' OR ')})');
    }
    final rows = await db.query(
      'cards',
      columns: [
        'id',
        'hungarian',
        'russian',
        'example',
        'last_result',
        'last_success_at',
      ],
      where: conditions.isEmpty ? null : conditions.join(' AND '),
      whereArgs: args.isEmpty ? null : args,
      orderBy: review ? 'last_success_at ASC, id ASC' : 'id ASC',
    );
    return rows.map(_card).toList();
  }

  Future<int> overdueCount({DateTime? now}) async => Sqflite.firstIntValue(
    await db.rawQuery(
      'SELECT COUNT(*) FROM cards WHERE last_success_at IS NULL OR last_success_at <= ?',
      [(now ?? DateTime.now()).toUtc().subtract(age).millisecondsSinceEpoch],
    ),
  )!;
  Future<Uint8List?> image(int id) async =>
      (await db.query(
            'cards',
            columns: ['image'],
            where: 'id = ?',
            whereArgs: [id],
          )).firstOrNull?['image']
          as Uint8List?;
  Future<void> delete(int id) async {
    await db.delete('cards', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteAllCards() async {
    await db.delete('cards');
  }

  Future<WordCard> card(int id) async {
    final rows = await db.query('cards', where: 'id = ?', whereArgs: [id]);
    if (rows.isEmpty) {
      throw const FormatException('Карточка больше не существует.');
    }
    return _card(rows.single);
  }

  Future<Set<int>> cardGroupIds(int id) async => (await db.query(
    'card_to_groups',
    columns: ['group_id'],
    where: 'card_id = ?',
    whereArgs: [id],
  )).map((row) => row['group_id'] as int).toSet();

  Future<int> saveCard(
    WordCard draft, {
    Set<int> groupIds = const {},
    List<String> newGroupNames = const [],
  }) async {
    final hu = unicode.nfc(draft.hungarian.trim());
    final ru = draft.russian.map((value) => unicode.nfc(value.trim())).toList();
    if (hu.isEmpty || ru.isEmpty || ru.any((value) => value.isEmpty)) {
      throw const FormatException(
        'Заполните венгерское слово и каждый перевод.',
      );
    }
    if (ru.length > 5) {
      throw const FormatException('Можно указать не более 5 переводов.');
    }
    final names = newGroupNames.map(cleanGroupName).toList();
    if (names.any((name) => name.isEmpty)) {
      throw const FormatException('Введите название группы.');
    }
    return db.transaction((txn) async {
      final duplicates = await txn.query(
        'cards',
        columns: ['id'],
        where: draft.id == null ? 'hungarian = ?' : 'hungarian = ? AND id != ?',
        whereArgs: [hu, if (draft.id != null) draft.id],
      );
      if (duplicates.isNotEmpty) {
        throw const FormatException(
          'Карточка с таким венгерским словом уже существует.',
        );
      }
      WordCard? previous;
      if (draft.id != null) {
        final rows = await txn.query(
          'cards',
          where: 'id = ?',
          whereArgs: [draft.id],
        );
        if (rows.isEmpty) {
          throw const FormatException('Карточка больше не существует.');
        }
        previous = _card(rows.single);
      }
      final selectedIds = groupIds.toSet();
      for (final id in selectedIds) {
        if ((await txn.query(
          'groups',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [id],
        )).isEmpty) {
          throw const FormatException('Выбранная группа больше не существует.');
        }
      }
      for (final name in names) {
        final found = await txn.query(
          'groups',
          columns: ['id'],
          where: 'name_key = ?',
          whereArgs: [groupNameKey(name)],
        );
        selectedIds.add(
          found.isEmpty
              ? await txn.insert('groups', {
                  'name': name,
                  'name_key': groupNameKey(name),
                })
              : found.single['id'] as int,
        );
      }
      final changedAnswer =
          previous == null ||
          previous.hungarian != hu ||
          !listEquals(previous.russian, ru);
      final values = <String, Object?>{
        'hungarian': hu,
        'russian': jsonEncode(ru),
        'example': draft.example.trim(),
        'image': draft.image,
        if (changedAnswer) ...{'last_result': null, 'last_success_at': null},
      };
      final int id;
      if (draft.id == null) {
        id = await txn.insert('cards', values);
      } else {
        id = draft.id!;
        await txn.update('cards', values, where: 'id = ?', whereArgs: [id]);
        await txn.delete(
          'card_to_groups',
          where: 'card_id = ?',
          whereArgs: [id],
        );
      }
      for (final groupId in selectedIds) {
        await txn.insert('card_to_groups', {
          'card_id': id,
          'group_id': groupId,
        });
      }
      return id;
    });
  }

  Future<void> record(int id, bool success, DateTime now) async {
    final changes = await db.update(
      'cards',
      {
        'last_result': success ? 1 : 0,
        if (success) 'last_success_at': now.toUtc().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (changes != 1) {
      throw StateError('Карточка больше не существует');
    }
  }

  Future<ImportReport> importRows(
    List<ImportRow> rows, {
    int? groupId,
    String? groupName,
  }) => db.transaction((txn) async {
    var added = 0;
    var linked = 0;
    var targetGroupId = groupId;
    final name = cleanGroupName(groupName ?? '');
    if (groupId != null && name.isNotEmpty) {
      throw const FormatException(
        'Выберите существующую группу или введите новую.',
      );
    }
    if (name.isNotEmpty) {
      final existing = await txn.query(
        'groups',
        columns: ['id'],
        where: 'name_key = ?',
        whereArgs: [groupNameKey(name)],
      );
      targetGroupId = existing.isEmpty
          ? await txn.insert('groups', {
              'name': name,
              'name_key': groupNameKey(name),
            })
          : existing.single['id'] as int;
    } else if (groupId != null) {
      if ((await txn.query(
        'groups',
        columns: ['id'],
        where: 'id = ?',
        whereArgs: [groupId],
      )).isEmpty) {
        throw const FormatException('Группа больше не существует.');
      }
    }
    final warnings = <String>[];
    for (final row in rows) {
      final card = row.card;
      final exists = await txn.query(
        'cards',
        columns: ['id'],
        where: 'hungarian = ?',
        whereArgs: [card.hungarian],
        limit: 1,
      );
      final int cardId;
      if (exists.isNotEmpty) {
        warnings.add(
          '${row.source.isEmpty ? '' : '${row.source}: '}Запись ${row.record}: «${card.hungarian}» уже есть — пропущено.',
        );
        cardId = exists.single['id'] as int;
      } else {
        cardId = await txn.insert('cards', {
          'hungarian': card.hungarian,
          'russian': jsonEncode(card.russian),
          'example': card.example,
          'image': card.image,
        });
        added++;
      }
      if (targetGroupId != null) {
        final link = await txn.query(
          'card_to_groups',
          columns: ['card_id'],
          where: 'card_id = ? AND group_id = ?',
          whereArgs: [cardId, targetGroupId],
        );
        if (link.isEmpty) {
          await txn.insert('card_to_groups', {
            'card_id': cardId,
            'group_id': targetGroupId,
          });
          linked++;
        }
      }
    }
    return ImportReport(added, warnings, linked: linked);
  });
  Future<void> close() => db.close();
}
