import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remagyar/import/zip_import.dart';

import 'fixtures.dart';

void main() {
  test('ZIP accepts arbitrary root CSV names and preserves image paths', () {
    for (final name in ['words.csv', 'lesson-01.csv', 'Мои слова.CSV']) {
      final rows = parseZip(
        makeZip(
          '${header}alma,яблоко,,images/a.png',
          csvName: name,
          images: {'images/a.png': png()},
        ),
      );
      expect(rows.single.card.hungarian, 'alma');
      expect(rows.single.card.image, png());
    }
  });
  test('ZIP rejects missing root CSV files', () {
    for (final name in [
      'folder/lesson.csv',
      r'folder\lesson.csv',
      'lesson.csv.bak',
    ]) {
      expect(
        () => parseZip(makeZip(words, csvName: name)),
        throwsFormatException,
      );
    }
    expect(() => parseZip(noCsv()), throwsFormatException);
  });
  test('ZIP reads every root CSV in archive order', () {
    final rows = parseZip(
      makeZip(
        '${header}alma,яблоко,,',
        csvName: 'first.csv',
        images: {
          'second.CSV': raw('${header}ház,дом,,images/a.png'),
          'images/a.png': png(),
        },
      ),
    );
    expect(rows.map((r) => r.card.hungarian), ['alma', 'ház']);
    expect(rows.map((r) => r.source), ['first.csv', 'second.CSV']);
    expect(rows.last.card.image, png());
  });
  test('a malformed later CSV rejects the entire archive with its name', () {
    for (final bad in ['${header}bad,', '$header"unfinished']) {
      expect(
        () => parseZip(makeZip(words, images: {'broken.csv': raw(bad)})),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('broken.csv:'),
          ),
        ),
      );
    }
  });
  test('CSV errors identify the actual file name', () {
    for (final contents in ['', 'wrong,columns\n']) {
      expect(
        () => parseZip(makeZip(contents, csvName: 'lesson.csv')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            startsWith('lesson.csv:'),
          ),
        ),
      );
    }
  });
  test(
    'CSV handles BOM, delimiters, escaped quotes, multiline and final fields',
    () {
      expect(parseCsv('\uFEFFa,b\r\n"c,d","e""f\ng"\r\n'), [
        ['a', 'b'],
        ['c,d', 'e"f\ng'],
      ]);
      expect(parseCsv('a,b\rc,d'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
      expect(parseCsv('a,'), [
        ['a', ''],
      ]);
      expect(parseCsv('""'), [
        [''],
      ]);
      expect(parseCsv(''), isEmpty);
      for (final input in ['"unfinished', 'a"b,c', '"a"oops,b']) {
        expect(() => parseCsv(input), throwsFormatException);
      }
    },
  );
  test(
    'ZIP imports normalized words, alternate translations and optional media',
    () {
      final rows = parseZip(
        makeZip(
          '\uFEFFrussian,image,hungarian,example\nяблоко,images/a.png, alma ,"Пример, с запятой"\nдом | здание,images/b.jpg,ha\u0301z,"Первая\nВторая"\n\n',
          images: {'images/a.png': png(), 'images/b.jpg': jpg()},
        ),
      );
      expect(rows.length, 2);
      expect(rows.first.card.hungarian, 'alma');
      expect(rows.first.card.image, png());
      expect(rows.last.card.hungarian, 'ház');
      expect(rows.last.card.russian, ['дом', 'здание']);
      expect(rows.last.card.example, 'Первая\nВторая');
      expect(parseZip(makeZip(words)).first.card.image, isNull);
      expect(parseZip(makeZip(header)), isEmpty);
    },
  );
  test('all malformed records reject the complete archive', () {
    for (final csv in [
      '',
      'wrong,columns\n',
      'hungarian,russian,example,example\n',
      '${header}a,b,c\n',
      '$header,b,,\n',
      '${header}a,дом|,,\n',
      '${header}a,|дом,,\n',
      '${header}a,,e,\n',
      '${header}a,b,,\na,bad|,,',
    ]) {
      expect(() => parseZip(makeZip(csv)), throwsFormatException, reason: csv);
    }
    expect(() => parseZip(noCsv()), throwsFormatException);
    expect(() => parseZip(invalidUtf8()), throwsFormatException);
    expect(
      () => parseZip(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    final bytes = makeZip(words);
    expect(
      () => parseZip(bytes.sublist(0, bytes.length ~/ 2)),
      throwsFormatException,
    );
  });
  test('missing, corrupt and unsafe images fail including duplicate rows', () {
    for (final path in [
      'images/missing.png',
      '../a.png',
      '/a.png',
      'images/../a.png',
      'images//a.png',
      'images/./a.png',
      'images/a.gif',
      'https://a.png',
      r'images\a.png',
      'images/a:1.png',
    ]) {
      expect(
        () => parseZip(makeZip('${header}a,b,,$path')),
        throwsFormatException,
        reason: path,
      );
    }
    for (final ext in ['png', 'jpg']) {
      expect(
        () => parseZip(
          makeZip(
            '${header}a,b,,\na,b,,images/a.$ext',
            images: {
              'images/a.$ext': [0, 1, 2],
            },
          ),
        ),
        throwsFormatException,
      );
    }
  });
}
