import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/widgets/outcome_label.dart';
import 'package:choke/l10n/generated/app_localizations.dart';

Match _finished({
  MatchWinner? winner,
  required MatchMethod method,
  String? submission,
  DqReason? dqReason,
}) {
  return Match(
    id: 'abcd',
    status: MatchStatus.finished,
    startAt: 1000,
    duration: 300,
    f1Name: 'Pana',
    f2Name: 'Buchecha',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
    winner: winner,
    method: method,
    submission: submission,
    dqReason: dqReason,
    endedAt: 1200,
  );
}

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  group('methodLabel', () {
    test('every scoreboard-silent method has a human name', () {
      // A reader must never see a raw enum name: these labels are what a
      // finished match says about itself in the footer and the home feed.
      expect(methodLabel(l10n, MatchMethod.advantages), l10n.outcomeAdvantages);
      expect(methodLabel(l10n, MatchMethod.decision), l10n.outcomeDecision);
      expect(methodLabel(l10n, MatchMethod.dq), l10n.outcomeDq);
      expect(methodLabel(l10n, MatchMethod.forfeit), l10n.outcomeForfeit);
      expect(methodLabel(l10n, MatchMethod.draw), l10n.outcomeDraw);
    });

    test('a submission with no technique named falls back to the plain label',
        () {
      // The referee skipped naming the technique — the fact of the
      // submission still reads correctly.
      expect(methodLabel(l10n, MatchMethod.submission), l10n.outcomeSubmission);
      expect(
        methodLabel(l10n, MatchMethod.submission, submission: ''),
        l10n.outcomeSubmission,
        reason: 'an empty string is not a technique',
      );
    });
  });

  group('describeOutcome', () {
    test('a draw reads as the method alone — no winner to name', () {
      // Arrange — a draw is a method with no winner, by construction
      final match = _finished(method: MatchMethod.draw);

      // Act + Assert
      expect(describeOutcome(l10n, match), l10n.outcomeDraw);
    });

    test('a decision names the fighter the referees chose', () {
      // Arrange
      final match =
          _finished(winner: MatchWinner.f1, method: MatchMethod.decision);

      // Act + Assert — the name comes from the winner field, never from
      // comparing scores: a scoreboard cannot decide a level match
      expect(describeOutcome(l10n, match), 'Pana · ${l10n.outcomeDecision}');
    });

    test('a disqualification names the fighter who was NOT disqualified', () {
      // Arrange — Buchecha wins because Pana was disqualified
      final match = _finished(
        winner: MatchWinner.f2,
        method: MatchMethod.dq,
        dqReason: DqReason.technicalFoul,
      );

      // Act + Assert
      expect(describeOutcome(l10n, match), 'Buchecha · ${l10n.outcomeDq}');
    });
  });
}
