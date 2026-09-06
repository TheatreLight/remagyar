import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../models/word_card.dart';

List<WordCard> shuffledReviewCards(List<WordCard> cards, {Random? random}) =>
    List<WordCard>.of(cards)..shuffle(random);

String normalizeAnswer(String value) =>
    unicode.nfc(value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' '));
bool isCorrect(WordCard card, Direction direction, String answer) {
  final normalized = normalizeAnswer(answer);
  return normalized.isNotEmpty &&
      card.answers(direction).any((a) => normalizeAnswer(a) == normalized);
}

List<String> choicesFor(
  WordCard card,
  List<WordCard> bank,
  Direction direction,
  Random random,
) {
  final valid = card.answers(direction).map(normalizeAnswer).toSet();
  final currentRussian = card.russian.map(normalizeAnswer).toSet();
  final candidates = <String, String>{};
  for (final other in bank) {
    if (other.id == card.id && other.hungarian == card.hungarian) {
      continue;
    }
    if (direction == Direction.ruHu &&
        other.russian.map(normalizeAnswer).any(currentRussian.contains)) {
      continue;
    }
    for (final answer in other.answers(direction)) {
      final key = normalizeAnswer(answer);
      if (!valid.contains(key)) {
        candidates.putIfAbsent(key, () => answer);
      }
    }
  }
  if (candidates.length < 3) {
    return [];
  }
  final wrong = candidates.values.toList()..shuffle(random);
  final correct = card.answers(direction);
  return [correct[random.nextInt(correct.length)], ...wrong.take(3)]
    ..shuffle(random);
}

class ReviewSession extends ChangeNotifier {
  ReviewSession({
    required List<WordCard> cards,
    required this.save,
    DateTime Function()? clock,
  }) : cards = List.unmodifiable(cards),
       clock = clock ?? DateTime.now;
  final List<WordCard> cards;
  final Future<void> Function(int, bool, DateTime) save;
  final DateTime Function() clock;
  int index = 0;
  bool saving = false;
  bool? result;
  String? error;
  bool _disposed = false;
  bool get finished => index >= cards.length;
  WordCard get current => cards[index];
  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  Future<void> submit(bool success) async {
    if (finished || saving || result != null) {
      return;
    }
    saving = true;
    error = null;
    _notify();
    try {
      await save(current.id!, success, clock());
      result = success;
    } catch (_) {
      error = 'Не удалось сохранить ответ. Попробуйте ещё раз.';
    } finally {
      saving = false;
      _notify();
    }
  }

  void next() {
    if (result == null || saving || finished) {
      return;
    }
    index++;
    result = null;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
