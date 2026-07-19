import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/models/match_outcome.dart';

void main() {
  group('constructors', () {
    test('the general constructor carries every field as given', () {
      // Arrange + Act — the raw constructor exists for callers that already
      // hold all the pieces (deserialization, tests)
      const outcome = MatchOutcome(
        method: MatchMethod.dq,
        winner: MatchWinner.f1,
        dqReason: DqReason.technicalFoul,
        dqDetail: 'knee reap',
      );

      // Assert
      expect(outcome.method, MatchMethod.dq);
      expect(outcome.winner, MatchWinner.f1);
      expect(outcome.submission, isNull);
      expect(outcome.dqReason, DqReason.technicalFoul);
      expect(outcome.dqDetail, 'knee reap');
    });

    test('forfeitBy names the winner and nothing else', () {
      // Arrange + Act — the loser withdrew; there is no technique and no
      // disqualification to record
      const outcome = MatchOutcome.forfeitBy(MatchWinner.f2);

      // Assert
      expect(outcome.method, MatchMethod.forfeit);
      expect(outcome.winner, MatchWinner.f2);
      expect(outcome.submission, isNull);
      expect(outcome.dqReason, isNull);
      expect(outcome.dqDetail, isNull);
    });

    test('decision names the winner the referees chose', () {
      // Arrange + Act — level on points and advantages, referees decide
      const outcome = MatchOutcome.decision(MatchWinner.f1);

      // Assert
      expect(outcome.method, MatchMethod.decision);
      expect(outcome.winner, MatchWinner.f1);
      expect(outcome.submission, isNull);
      expect(outcome.dqReason, isNull);
    });
  });
}
