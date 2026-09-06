import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

const header = 'hungarian,russian,example,image\n';
const words =
    '${header}alma,яблоко,Ez egy alma.,\nház,дом|здание,,\nvíz,вода,,\nkenyér,хлеб,,\nnap,солнце,,\n';
Uint8List makeZip(
  String csv, {
  String csvName = 'words.csv',
  Map<String, List<int>> images = const {},
}) {
  final archive = Archive()..addFile(ArchiveFile.string(csvName, csv));
  for (final entry in images.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List png() => img.encodePng(img.Image(width: 8, height: 8));
Uint8List jpg() => img.encodeJpg(img.Image(width: 8, height: 8));
Uint8List invalidUtf8() {
  final a = Archive()..addFile(ArchiveFile('words.csv', 2, [0xC3, 0x28]));
  return Uint8List.fromList(ZipEncoder().encode(a));
}

Uint8List noCsv() => Uint8List.fromList(
  ZipEncoder().encode(
    Archive()..addFile(ArchiveFile.string('readme.txt', 'x')),
  ),
);
String csvQuote(String text) => '"${text.replaceAll('"', '""')}"';
List<int> raw(String value) => utf8.encode(value);
