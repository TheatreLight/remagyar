import 'dart:io';

void main() {
  String file = '';
  var covered = 0;
  var lines = 0;
  var allCovered = 0;
  var allLines = 0;
  var failed = false;
  for (final line in File('coverage/lcov.info').readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      file = line.substring(3).replaceAll('\\', '/');
      covered = 0;
      lines = 0;
    } else if (line.startsWith('DA:')) {
      lines++;
      if (int.parse(line.split(',')[1]) > 0) {
        covered++;
      }
    } else if (line == 'end_of_record') {
      final percent = lines == 0 ? 100.0 : 100 * covered / lines;
      stdout.writeln('$file: $covered/$lines (${percent.toStringAsFixed(1)}%)');
      allCovered += covered;
      allLines += lines;
      if ((file.contains('/import/') || file.contains('/learning/')) &&
          percent < 90) {
        failed = true;
      }
    }
  }
  if (allLines == 0) {
    throw StateError('Empty coverage report');
  }
  stdout.writeln(
    'Total: $allCovered/$allLines (${(100 * allCovered / allLines).toStringAsFixed(1)}%)',
  );
  if (failed) {
    stderr.writeln('Core logic coverage is below 90%.');
    exitCode = 1;
  }
}
