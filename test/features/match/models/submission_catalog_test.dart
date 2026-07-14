import 'package:flutter_test/flutter_test.dart';

import 'package:choke/features/match/models/submission_catalog.dart';
import 'package:choke/l10n/generated/app_localizations.dart';

/// The catalog exists to keep one technique one technique.
///
/// A referee in São Paulo taps *chave de braço* and a referee in Tokyo taps
/// 腕十字固め; both events say `armbar`, and a dashboard counting armbars across
/// a tournament counts one thing. Publishing the localized string instead would
/// fragment the data at the exact moment we started collecting it.
void main() {
  late Map<String, AppLocalizations> l10ns;

  setUpAll(() async {
    l10ns = {
      for (final locale in AppLocalizations.supportedLocales)
        locale.languageCode: await AppLocalizations.delegate.load(locale),
    };
  });

  group('every submission speaks every language', () {
    test('all four locales are actually covered', () {
      // Guards the premise of the test below: if a locale were dropped from
      // supportedLocales, that test would still pass, having checked nothing.
      expect(l10ns.keys, containsAll(<String>['en', 'es', 'pt', 'ja']));
    });

    test('no default falls back to its raw id in any locale', () {
      for (final entry in l10ns.entries) {
        for (final submission in defaultSubmissions) {
          final label = labelFor(entry.value, submission);

          // labelFor returns the id unchanged when it has no translation, so a
          // missing .arb key never throws — it quietly ships `rear_naked_choke`
          // to a Japanese referee. This is the assertion that catches that.
          expect(
            label,
            isNot(submission),
            reason: '$submission has no ${entry.key} translation',
          );
          expect(label.trim(), isNotEmpty);
        }
      }
    });

    test('no two submissions share a name within a locale', () {
      // Two chips reading the same thing is a coin flip for the referee, and
      // one of the two publishes the wrong id.
      for (final entry in l10ns.entries) {
        final labels =
            defaultSubmissions.map((s) => labelFor(entry.value, s)).toList();

        expect(
          labels.toSet().length,
          labels.length,
          reason: 'duplicate submission label in ${entry.key}',
        );
      }
    });
  });

  group('canonicalize', () {
    test('recognises a technique typed in the referee own language', () {
      // Arrange — a Spanish referee types a technique we already ship
      final es = l10ns['es']!;

      // Act
      final canonical = canonicalize(es, 'Mataleón');

      // Assert — the event says `rear_naked_choke`, not a second spelling of it
      expect(canonical, 'rear_naked_choke');
    });

    test('recognises the canonical id itself, whatever the case', () {
      expect(canonicalize(l10ns['en']!, 'ArmBar'), 'armbar');
    });

    test('leaves a technique we have never heard of alone', () {
      // A baratoplata is a real submission and not on our list. The referee is
      // never blocked, and the event says exactly what they wrote.
      expect(canonicalize(l10ns['en']!, 'baratoplata'), isNull);
    });

    test('is blank-safe', () {
      expect(canonicalize(l10ns['en']!, '   '), isNull);
    });
  });

  group('labelFor', () {
    test('shows a user own submission exactly as they wrote it', () {
      expect(labelFor(l10ns['ja']!, 'baratoplata'), 'baratoplata');
    });

    test('translates a canonical id for the reader', () {
      // The event says `armbar` in every language; only the display changes.
      expect(labelFor(l10ns['ja']!, 'armbar'), '腕十字固め');
      expect(labelFor(l10ns['pt']!, 'armbar'), 'Chave de braço');
    });
  });
}
