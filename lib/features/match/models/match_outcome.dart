import 'match.dart';

/// How a match ended, as chosen by the referee.
///
/// The one thing a `finished` match must not be able to do is stay silent about
/// this — a match that ends on a submission and says only "finished" publishes
/// a scoreboard naming the wrong fighter. So the outcome travels as one value,
/// and the provider cannot finish a match without being handed one.
///
/// See docs/specs/match-outcome.md.
class MatchOutcome {
  /// Absent only for [MatchMethod.draw] — a draw is a method with no winner.
  final MatchWinner? winner;

  final MatchMethod method;

  /// Free text, and always optional: a referee must never be blocked from
  /// ending a match because the app has never heard of a *baratoplata*.
  final String? submission;

  /// Required when [method] is [MatchMethod.dq].
  final DqReason? dqReason;

  final String? dqDetail;

  const MatchOutcome({
    required this.method,
    this.winner,
    this.submission,
    this.dqReason,
    this.dqDetail,
  });

  /// A win by submission.
  const MatchOutcome.submissionBy(MatchWinner this.winner, {this.submission})
      : method = MatchMethod.submission,
        dqReason = null,
        dqDetail = null;

  /// A win on the scoreboard — points, or advantages when points were level.
  const MatchOutcome.onScoreboard(MatchWinner this.winner, this.method)
      : submission = null,
        dqReason = null,
        dqDetail = null;

  /// The loser was disqualified.
  const MatchOutcome.disqualifying(
    MatchWinner this.winner,
    DqReason this.dqReason, {
    this.dqDetail,
  })  : method = MatchMethod.dq,
        submission = null;

  /// The loser withdrew, no-showed, or could not continue.
  const MatchOutcome.forfeitBy(MatchWinner this.winner)
      : method = MatchMethod.forfeit,
        submission = null,
        dqReason = null,
        dqDetail = null;

  /// Level on points and advantages, and the referees named a winner.
  const MatchOutcome.decision(MatchWinner this.winner)
      : method = MatchMethod.decision,
        submission = null,
        dqReason = null,
        dqDetail = null;

  /// Level on points and advantages, and the referees called it even.
  const MatchOutcome.draw()
      : winner = null,
        method = MatchMethod.draw,
        submission = null,
        dqReason = null,
        dqDetail = null;

  /// The outcome the scoreboard already implies, or null when it implies none.
  ///
  /// Null is the honest answer, and the referee has to be asked:
  ///
  /// - the fighters are level, so there is no winner in the data
  ///   ([MatchMethod.decision] or [MatchMethod.draw] is theirs to choose).
  ///
  /// A fighter on four penalties is *not* null: the disqualification is on the
  /// scoreboard in plain sight, so it comes back pre-selected. Offered, never
  /// imposed — the referee still has to end the match.
  ///
  /// Unless *both* of them are on four. That is reachable, precisely because a
  /// fourth penalty leaves the match running, and the scoreboard then names no
  /// single offender. Picking one anyway would hand a referee a one-tap result
  /// that is arbitrary — the worst kind, because it looks decided.
  static MatchOutcome? suggestedFor(Match match) {
    final f1Disqualified = match.f1Pen >= 4;
    final f2Disqualified = match.f2Pen >= 4;

    if (f1Disqualified && f2Disqualified) return null;

    if (f1Disqualified || f2Disqualified) {
      final winner = f1Disqualified ? MatchWinner.f2 : MatchWinner.f1;
      return MatchOutcome.disqualifying(winner, DqReason.accumulatedPenalties);
    }

    final winner = match.scoreboardWinner;
    final method = match.scoreboardMethod;
    if (winner == null || method == null) return null;

    return MatchOutcome.onScoreboard(winner, method);
  }
}
