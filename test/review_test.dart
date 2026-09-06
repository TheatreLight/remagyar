import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remagyar/import/zip_import.dart';
import 'package:remagyar/learning/review.dart';
import 'package:remagyar/models/word_card.dart';

import 'fixtures.dart';

void main() {
  test('review shuffle preserves selection, leaves source intact and fixes session order', () async {
    final source = List.generate(
      12,
      (i) => WordCard(id: i, hungarian: 'word$i', russian: ['$i']),
    );
    final originalIds = source.map((c) => c.id).toList();
    final orders = <String>{};
    for (var seed = 0; seed < 5; seed++) {
      final queue = shuffledReviewCards(source, random: Random(seed));
      expect(queue.map((c) => c.id), unorderedEquals(originalIds));
      expect(queue.map((c) => c.id).toSet().length, source.length);
      expect(source.map((c) => c.id), originalIds);
      orders.add(queue.map((c) => c.id).join(','));
      final session = ReviewSession(cards: queue, save: (_, _, _) async {});
      final expected = queue.map((c) => c.id).toList();
      queue.clear();
      final visited = <int?>[];
      while (!session.finished) {
        visited.add(session.current.id);
        await session.submit(true);
        session.next();
      }
      expect(visited, expected);
      session.dispose();
    }
    expect(orders.length, greaterThan(1));
    expect(shuffledReviewCards([], random: Random(0)), isEmpty);
    expect(shuffledReviewCards([source.first], random: Random(0)), [
      source.first,
    ]);
  });
  const card = WordCard(id: 1, hungarian: 'ház', russian: ['дом', 'здание']);
  test(
    'answers respect alternatives, spaces, case, NFC and exact diacritics',
    () {
      expect(isCorrect(card, Direction.huRu, '  ЗДАНИЕ  '), isTrue);
      expect(isCorrect(card, Direction.huRu, 'дом'), isTrue);
      expect(isCorrect(card, Direction.ruHu, ' HA\u0301Z '), isTrue);
      for (final wrong in ['haz', 'ház.', 'h áz', '']) {
        expect(isCorrect(card, Direction.ruHu, wrong), isFalse);
      }
      expect(normalizeAnswer('  два   слова\t '), 'два слова');
      expect(normalizeAnswer('ő'), isNot(normalizeAnswer('ö')));
      expect(normalizeAnswer('ű'), isNot(normalizeAnswer('ü')));
    },
  );
  test('choices have one correct answer and three unique wrong answers', () {
    final bank = parseZip(makeZip(words)).map((r) => r.card).toList();
    for (final direction in Direction.values) {
      for (var seed = 0; seed < 10; seed++) {
        final options = choicesFor(bank[1], bank, direction, Random(seed));
        expect(options.length, 4);
        expect(options.map(normalizeAnswer).toSet().length, 4);
        expect(
          options.where((o) => isCorrect(bank[1], direction, o)).length,
          1,
        );
      }
    }
    expect(choicesFor(card, [card], Direction.huRu, Random(0)), isEmpty);
  });
  test('overlapping Russian meanings never become reverse distractors', () {
    const same = WordCard(hungarian: 'épület', russian: ['ЗДАНИЕ']);
    const duplicate = WordCard(hungarian: 'other', russian: ['дом', 'ДОМ']);
    final bank = [
      card,
      same,
      duplicate,
      ...parseZip(makeZip(words)).map((r) => r.card),
    ];
    final reverse = choicesFor(card, bank, Direction.ruHu, Random(1));
    expect(reverse, isNot(contains('épület')));
    expect(reverse, isNot(contains('other')));
    final forward = choicesFor(card, bank, Direction.huRu, Random(1));
    expect(forward.where((s) => isCorrect(card, Direction.huRu, s)).length, 1);
  });
  test(
    'session saves once, holds queue and clock, ignores premature next',
    () async {
      final gate = Completer<void>();
      final now = DateTime.utc(2026, 9, 5);
      var calls = 0;
      final original = [card];
      final session = ReviewSession(
        cards: original,
        clock: () => now,
        save: (id, success, time) async {
          calls++;
          expect(id, 1);
          expect(success, true);
          expect(time, now);
          await gate.future;
        },
      );
      original.clear();
      session.next();
      expect(session.index, 0);
      final pending = session.submit(true);
      await session.submit(false);
      session.next();
      expect(calls, 1);
      expect(session.saving, true);
      gate.complete();
      await pending;
      await session.submit(false);
      expect(calls, 1);
      expect(session.result, true);
      session.next();
      expect(session.finished, true);
      await session.submit(true);
      session.next();
      expect(calls, 1);
      session.dispose();
    },
  );
  test('failure can retry; disposing during save is safe', () async {
    var fail = true;
    final session = ReviewSession(
      cards: [card],
      save: (_, _, _) async {
        if (fail) {
          throw StateError('disk');
        }
      },
    );
    await session.submit(false);
    expect(session.error, isNotNull);
    expect(session.result, isNull);
    fail = false;
    await session.submit(false);
    expect(session.result, false);
    expect(session.error, isNull);
    session.dispose();
    final gate = Completer<void>();
    final closed = ReviewSession(cards: [card], save: (_, _, _) => gate.future);
    final pending = closed.submit(true);
    closed.dispose();
    gate.complete();
    await pending;
  });
}
