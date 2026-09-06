import 'dart:typed_data';

import 'package:unorm_dart/unorm_dart.dart' as unicode;

bool matchesCardSearch(WordCard card, String query) {
  String normalized(String value) => unicode.nfc(value).toLowerCase();
  final part = normalized(query.trim());
  return normalized(card.hungarian).contains(part) ||
      card.russian.any((translation) => normalized(translation).contains(part));
}

enum Direction { huRu, ruHu }

class WordCard {
  const WordCard({
    this.id,
    required this.hungarian,
    required this.russian,
    this.example = '',
    this.image,
    this.lastResult,
    this.lastSuccessAt,
  });
  final int? id;
  final String hungarian;
  final List<String> russian;
  final String example;
  final Uint8List? image;
  final bool? lastResult;
  final int? lastSuccessAt;
  String prompt(Direction direction) =>
      direction == Direction.huRu ? hungarian : russian.join(' / ');
  List<String> answers(Direction direction) =>
      direction == Direction.huRu ? russian : [hungarian];
}

class ImportRow {
  const ImportRow(this.record, this.card, {this.source = ''});
  final int record;
  final WordCard card;
  final String source;
}

class ImportReport {
  const ImportReport(this.added, this.warnings, {this.linked = 0});
  final int added;
  final List<String> warnings;
  final int linked;
}
