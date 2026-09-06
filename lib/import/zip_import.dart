import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;
import 'package:unorm_dart/unorm_dart.dart' as unicode;

import '../models/word_card.dart';

/// Strict CSV: malformed quoting must abort the entire import.
List<List<String>> parseCsv(String input) {
  final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
  final rows = <List<String>>[];
  var row = <String>[];
  var field = StringBuffer();
  var quoted = false;
  var closed = false;
  void finishField() {
    row.add(field.toString());
    field = StringBuffer();
    closed = false;
  }

  void finishRow() {
    finishField();
    rows.add(row);
    row = [];
  }

  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        field.write(c);
      }
    } else if (c == ',') {
      finishField();
    } else if (c == '\r' || c == '\n') {
      finishRow();
      if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
        i++;
      }
    } else if (closed || (c == '"' && field.isNotEmpty)) {
      throw FormatException('Запись ${rows.length + 1}: неверные кавычки CSV.');
    } else if (c == '"') {
      quoted = true;
    } else {
      field.write(c);
    }
  }
  if (quoted) {
    throw FormatException('Запись ${rows.length + 1}: незакрытые кавычки CSV.');
  }
  if (field.isNotEmpty || row.isNotEmpty || closed) {
    finishRow();
  }
  return rows;
}

List<ImportRow> parseZip(Uint8List bytes) {
  try {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes, verify: true);
    } catch (_) {
      throw const FormatException('Не удалось прочитать ZIP: архив повреждён.');
    }
    final files = <String, ArchiveFile>{};
    for (final file in archive.files.where((f) => f.isFile)) {
      if (files.containsKey(file.name)) {
        throw FormatException('Повтор пути в ZIP: ${file.name}');
      }
      files[file.name] = file;
    }
    final csvFiles = files.values
        .where(
          (file) =>
              !file.name.contains('/') &&
              !file.name.contains('\\') &&
              file.name.toLowerCase().endsWith('.csv'),
        )
        .toList();
    if (csvFiles.isEmpty) {
      throw const FormatException('В корне ZIP отсутствует CSV-файл.');
    }
    final result = <ImportRow>[];
    for (final csvFile in csvFiles) {
      final String text;
      try {
        text = utf8.decode(csvFile.content);
      } on FormatException {
        throw FormatException(
          '${csvFile.name}: требуется корректная кодировка UTF-8.',
        );
      }
      final List<List<String>> rows;
      try {
        rows = parseCsv(text);
      } on FormatException catch (error) {
        throw FormatException('${csvFile.name}: ${error.message}');
      }
      final headerIndex = rows.indexWhere((r) => r.any((s) => s.isNotEmpty));
      if (headerIndex < 0) {
        throw FormatException('${csvFile.name}: отсутствуют заголовки.');
      }
      final header = rows[headerIndex];
      const names = ['hungarian', 'russian', 'example', 'image'];
      if (header.length != 4 ||
          header.toSet().length != 4 ||
          !names.every(header.contains)) {
        throw FormatException(
          '${csvFile.name}: нужны заголовки hungarian,russian,example,image.',
        );
      }
      for (var i = headerIndex + 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.every((s) => s.isEmpty)) {
          continue;
        }
        Never fail(String reason) =>
            throw FormatException('${csvFile.name}: Запись ${i + 1}: $reason');
        if (row.length != 4) {
          fail('ожидается 4 поля.');
        }
        String value(String name) => row[header.indexOf(name)].trim();
        final hu = unicode.nfc(value('hungarian'));
        final ru = value('russian')
            .split('|')
            .map((s) => unicode.nfc(s.trim()))
            .toList();
        if (hu.isEmpty || ru.any((s) => s.isEmpty)) {
          fail('слово и каждый перевод должны быть заполнены.');
        }
        Uint8List? image;
        final path = value('image');
        if (path.isNotEmpty) {
          final parts = path.split('/');
          if (!path.startsWith('images/') ||
              parts.any((s) => s.isEmpty || s == '.' || s == '..') ||
              path.contains('\\') ||
              path.contains(':') ||
              !RegExp(r'\.(png|jpe?g)$', caseSensitive: false).hasMatch(path)) {
            fail('недопустимый путь изображения: $path');
          }
          final file = files[path];
          if (file == null) {
            fail('изображение не найдено: $path');
          }
          image = file.content;
          try {
            final decoded = path.toLowerCase().endsWith('.png')
                ? img.decodePng(image)
                : img.decodeJpg(image);
            if (decoded == null) {
              fail('повреждено изображение: $path');
            }
          } catch (_) {
            fail('повреждено изображение: $path');
          }
        }
        result.add(
          ImportRow(
            i + 1,
            WordCard(
              hungarian: hu,
              russian: ru,
              example: value('example'),
              image: image,
            ),
            source: csvFile.name,
          ),
        );
      }
    }
    return result;
  } on FormatException {
    rethrow;
  } catch (_) {
    throw const FormatException(
      'Не удалось прочитать ZIP: архив повреждён или имеет неподдерживаемый формат.',
    );
  }
}
