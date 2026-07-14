import 'package:choke/l10n/generated/app_localizations.dart';

import '../models/match.dart';
import '../models/submission_catalog.dart';

/// How a finished match is described to a human: *"Buchecha · Submission
/// (armbar)"*.
///
/// The reason this exists rather than a score comparison: a scoreboard cannot
/// name the winner of a match that ended in a submission. Bob leads 4–0, Carlos
/// armbars him, and every number on the card still says Bob. The result has to
/// be read from the result.
///
/// Returns null when the match has no outcome — because it is still running, or
/// because it was published before outcomes existed. A legacy match is not
/// re-refereed: it shows the scoreboard it showed at the time.
///
/// See docs/specs/match-outcome.md.
String? describeOutcome(AppLocalizations l10n, Match match) {
  final method = match.method;
  if (method == null) return null;

  final label = methodLabel(l10n, method, submission: match.submission);

  final winner = match.winner;
  if (winner == null) return label; // a draw has no winner, by construction

  final name = winner == MatchWinner.f1 ? match.f1Name : match.f2Name;
  return '$name · $label';
}

/// The method on its own — naming the submission when the referee recorded one.
///
/// The submission arrives as a canonical id (`armbar`) and is shown by its name
/// in the reader's language. One the user invented comes back through
/// [labelFor] unchanged, which is right: it is what they wrote down.
String methodLabel(
  AppLocalizations l10n,
  MatchMethod method, {
  String? submission,
}) {
  if (method == MatchMethod.submission &&
      submission != null &&
      submission.isNotEmpty) {
    return l10n.outcomeSubmissionOf(labelFor(l10n, submission));
  }

  return switch (method) {
    MatchMethod.submission => l10n.outcomeSubmission,
    MatchMethod.points => l10n.outcomePoints,
    MatchMethod.advantages => l10n.outcomeAdvantages,
    MatchMethod.decision => l10n.outcomeDecision,
    MatchMethod.dq => l10n.outcomeDq,
    MatchMethod.forfeit => l10n.outcomeForfeit,
    MatchMethod.draw => l10n.outcomeDraw,
  };
}
