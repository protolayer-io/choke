// Filters generated code out of an lcov report and prints the summary.
//
// Coverage policy: machine-generated sources are excluded from the coverage
// metric — they are not hand-maintained, and "covering" them only rewards
// calling generated getters. Excluded:
//   - lib/src/rust/**          (flutter_rust_bridge bindings)
//   - lib/l10n/generated/**    (gen-l10n output)
//
// Fails closed: an empty report, or a report that is missing any hand-written
// lib/ source (a truncated run, or a file no test ever imports), is an error —
// a partial universe must never masquerade as a project-wide percentage.
//
// Usage: dart run tool/filter_lcov.dart [coverage/lcov.info]
// Writes the filtered report next to the input as lcov.filtered.info and
// prints per-file, filtered-total and raw-total line coverage.
import 'dart:io';

const excludedPrefixes = [
  'lib/src/rust/',
  'lib/l10n/generated/',
];

bool _isExcluded(String path) => excludedPrefixes.any(path.startsWith);

void main(List<String> args) {
  final inputPath = args.isNotEmpty ? args[0] : 'coverage/lcov.info';
  final input = File(inputPath);
  if (!input.existsSync()) {
    stderr
        .writeln('No lcov report at $inputPath — run: flutter test --coverage');
    exit(2);
  }

  // Always a sibling of the input, never derived by string surgery on the
  // input name: a custom report path like coverage/custom.info must not be
  // overwritten with its own filtered contents.
  final outPath =
      '${input.parent.path}${Platform.pathSeparator}lcov.filtered.info';
  final out = StringBuffer();

  var keep = true;
  String? currentFile;
  var fileFound = 0;
  var fileHit = 0;
  var totalFound = 0;
  var totalHit = 0;
  var rawFound = 0;
  var rawHit = 0;
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
      keep = !_isExcluded(currentFile!);
    } else if (line.startsWith('DA:')) {
      final hits = int.parse(line.substring(3).split(',')[1]);
      rawFound++;
      if (hits > 0) rawHit++;
      if (keep) {
        fileFound++;
        if (hits > 0) fileHit++;
      }
    }
    if (keep) out.writeln(line);
    if (line == 'end_of_record' && keep) closeFile();
  }
  closeFile();

  // Fail closed: no lines means nothing ran, and 0/0 is not 100%.
  if (totalFound == 0) {
    stderr.writeln('The report contains no coverable hand-written lines — '
        'refusing to report a percentage over an empty universe.');
    exit(2);
  }

  // Fail closed: every hand-written lib/ source must appear in the report.
  // A missing file is either a truncated run or code no test ever imports —
  // both would silently inflate a "project-wide" percentage.
  final missing = <String>[];
  final libDir = Directory('lib');
  if (libDir.existsSync()) {
    for (final entity in libDir.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final rel = entity.path.replaceAll('\\', '/');
      if (_isExcluded(rel)) continue;
      if (!perFile.containsKey(rel)) missing.add(rel);
    }
  }
  if (missing.isNotEmpty) {
    stderr.writeln('Hand-written sources absent from the coverage report '
        '(truncated run, or never imported by any test):');
    for (final path in missing..sort()) {
      stderr.writeln('  $path');
    }
    exit(3);
  }

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
  stdout.writeln('\nTOTAL (generated code excluded): '
      '$totalHit/$totalFound = '
      '${(100 * totalHit / totalFound).toStringAsFixed(1)}%');
  stdout.writeln('TOTAL (raw, including generated): '
      '$rawHit/$rawFound = '
      '${(100 * rawHit / rawFound).toStringAsFixed(1)}%');
}
