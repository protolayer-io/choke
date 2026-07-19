// Filters generated code out of an lcov report and prints the summary.
//
// Coverage policy: machine-generated sources are excluded from the coverage
// metric — they are not hand-maintained, and "covering" them only rewards
// calling generated getters. Excluded:
//   - lib/src/rust/**          (flutter_rust_bridge bindings)
//   - lib/l10n/generated/**    (gen-l10n output)
//
// Usage: dart run tool/filter_lcov.dart [coverage/lcov.info]
// Writes the filtered report next to the input as lcov.filtered.info and
// prints per-file and total line coverage.
import 'dart:io';

const excludedPrefixes = [
  'lib/src/rust/',
  'lib/l10n/generated/',
];

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'coverage/lcov.info';
  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr
        .writeln('No lcov report at $inputPath — run: flutter test --coverage');
    exit(2);
  }

  final outPath =
      inputPath.replaceFirst(RegExp(r'lcov\.info$'), 'lcov.filtered.info');
  final out = StringBuffer();

  var keep = true;
  String? currentFile;
  var fileFound = 0;
  var fileHit = 0;
  var totalFound = 0;
  var totalHit = 0;
  final perFile = <String, (int, int)>{};

  void closeFile() {
    if (currentFile != null && keep) {
      perFile[currentFile!] = (fileHit, fileFound);
      totalFound += fileFound;
      totalHit += fileHit;
    }
    currentFile = null;
    fileFound = 0;
    fileHit = 0;
  }

  for (final line in input.readAsLinesSync()) {
    if (line.startsWith('SF:')) {
      closeFile();
      currentFile = line.substring(3);
      keep = !excludedPrefixes.any(currentFile!.startsWith);
    } else if (line.startsWith('DA:') && keep) {
      fileFound++;
      final hits = int.parse(line.substring(3).split(',')[1]);
      if (hits > 0) fileHit++;
    }
    if (keep) out.writeln(line);
    if (line == 'end_of_record' && keep) closeFile();
  }
  closeFile();

  File(outPath).writeAsStringSync(out.toString());

  final entries = perFile.entries.toList()
    ..sort((a, b) {
      final ua = a.value.$2 - a.value.$1;
      final ub = b.value.$2 - b.value.$1;
      return ub.compareTo(ua);
    });
  for (final e in entries) {
    final (hit, found) = e.value;
    final pct = found == 0 ? 100.0 : 100 * hit / found;
    stdout.writeln(
        '${(found - hit).toString().padLeft(5)} uncovered  ${pct.toStringAsFixed(1).padLeft(5)}%  ${e.key}');
  }
  final pct = totalFound == 0 ? 100.0 : 100 * totalHit / totalFound;
  stdout.writeln('\nTOTAL (generated code excluded): '
      '$totalHit/$totalFound = ${pct.toStringAsFixed(1)}%');
}
