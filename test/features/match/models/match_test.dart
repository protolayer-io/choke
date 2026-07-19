import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';

void main() {
  _outcomeTests();

  group('Match', () {
    // Valid test data
    final validMatchData = {
      'id': 'a3f7',
      'status': 'waiting',
      'duration': 300,
      'f1_name': 'Roger Gracie',
      'f2_name': 'Buchecha',
      'f1_color': '#FFFFFF',
      'f2_color': '#000000',
      'f1_pt2': 0,
      'f2_pt2': 0,
      'f1_pt3': 0,
      'f2_pt3': 0,
      'f1_pt4': 0,
      'f2_pt4': 0,
      'f1_adv': 0,
      'f2_adv': 0,
      'f1_pen': 0,
      'f2_pen': 0,
    };

    group('construction', () {
      test('creates valid match with all fields', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.waiting,
          startAt: 1699900000,
          duration: 300,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
          f2Pt2: 0,
          f1Pt3: 1,
          f2Pt3: 0,
          f1Pt4: 0,
          f2Pt4: 1,
          f1Adv: 2,
          f2Adv: 1,
          f1Pen: 0,
          f2Pen: 1,
        );

        expect(match.id, equals('a3f7'));
        expect(match.status, equals(MatchStatus.waiting));
        expect(match.startAt, equals(1699900000));
        expect(match.duration, equals(300));
        expect(match.f1Name, equals('Roger Gracie'));
        expect(match.f2Name, equals('Buchecha'));
        expect(match.f1Color, equals('#FFFFFF'));
        expect(match.f2Color, equals('#000000'));
        expect(match.f1Pt2, equals(1));
        expect(match.f2Pt4, equals(1));
        expect(match.f1Adv, equals(2));
        expect(match.f2Pen, equals(1));
      });

      test('creates valid match with default counters', () {
        final match = Match(
          id: 'b5e2',
          status: MatchStatus.inProgress,
          duration: 600,
          f1Name: 'Athlete A',
          f2Name: 'Athlete B',
          f1Color: '#FF5733',
          f2Color: '#33FF57',
        );

        expect(match.f1Pt2, equals(0));
        expect(match.f2Pt2, equals(0));
        expect(match.f1Pt3, equals(0));
        expect(match.f2Pt3, equals(0));
        expect(match.f1Pt4, equals(0));
        expect(match.f2Pt4, equals(0));
        expect(match.f1Adv, equals(0));
        expect(match.f2Adv, equals(0));
        expect(match.f1Pen, equals(0));
        expect(match.f2Pen, equals(0));
      });

      test('Match.create generates valid ID', () {
        final match = Match.create(
          f1Name: 'Fighter 1',
          f2Name: 'Fighter 2',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          duration: 300,
        );

        expect(match.id.length, equals(4));
        expect(RegExp(r'^[0-9a-f]{4}$').hasMatch(match.id), isTrue);
        expect(match.status, equals(MatchStatus.waiting));
      });
    });

    group('validation', () {
      test('rejects match ID too short', () {
        expect(
          () => Match(
            id: 'abc',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('exactly 4 characters'),
            ),
          ),
        );
      });

      test('rejects match ID too long', () {
        expect(
          () => Match(
            id: 'abcde',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('exactly 4 characters'),
            ),
          ),
        );
      });

      test('rejects invalid hex match ID', () {
        expect(
          () => Match(
            id: 'xyz1',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('valid hex'),
            ),
          ),
        );
      });

      test('accepts uppercase hex match ID', () {
        expect(
          () => Match(
            id: 'A3F7',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          returnsNormally,
        );
      });

      test('rejects negative duration', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: -1,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('non-negative'),
            ),
          ),
        );
      });

      test('accepts zero duration', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: 0,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          returnsNormally,
        );
      });

      test('rejects negative counters', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
            f1Pt2: -1,
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('rejects invalid color format', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: 'FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('valid hex color'),
            ),
          ),
        );
      });

      test('rejects color with wrong length', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFF',
            f2Color: '#000000',
          ),
          throwsA(isA<FormatException>()),
        );
      });

      test('accepts valid hex colors', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#AaBbCc',
            f2Color: '#123456',
          ),
          returnsNormally,
        );
      });

      test('rejects negative startAt', () {
        expect(
          () => Match(
            id: 'a3f7',
            status: MatchStatus.waiting,
            startAt: -1,
            duration: 300,
            f1Name: 'A',
            f2Name: 'B',
            f1Color: '#FFFFFF',
            f2Color: '#000000',
          ),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('score calculation', () {
      test('calculates empty match score as 0-0', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        expect(match.f1Score, equals(0));
        expect(match.f2Score, equals(0));
      });

      test('calculates takedown points (pt2)', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 3,
          f2Pt2: 1,
        );

        expect(match.f1Score, equals(6)); // 3 * 2
        expect(match.f2Score, equals(2)); // 1 * 2
      });

      test('calculates guard pass points (pt3)', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt3: 2,
          f2Pt3: 1,
        );

        expect(match.f1Score, equals(6)); // 2 * 3
        expect(match.f2Score, equals(3)); // 1 * 3
      });

      test('calculates mount/back points (pt4)', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt4: 1,
          f2Pt4: 2,
        );

        expect(match.f1Score, equals(4)); // 1 * 4
        expect(match.f2Score, equals(8)); // 2 * 4
      });

      test('calculates combined score correctly', () {
        // Example from SPEC.md: f1_pt2=1, rest=0 → f1 wins 2-0
        final match = Match(
          id: 'abcd',
          status: MatchStatus.inProgress,
          duration: 600,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#aabbcc',
          f2Color: '#ccddee',
          f1Pt2: 1,
          f1Pt3: 0,
          f1Pt4: 0,
          f2Pt2: 0,
          f2Pt3: 0,
          f2Pt4: 0,
        );

        expect(match.f1Score, equals(2));
        expect(match.f2Score, equals(0));
      });

      test('advantages do not affect score total', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
          f1Adv: 5,
          f2Adv: 3,
        );

        expect(match.f1Score, equals(2));
        expect(match.f2Score, equals(0));
      });

      test('penalties do not affect score total', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt3: 1,
          f1Pen: 2,
          f2Pen: 1,
        );

        expect(match.f1Score, equals(3));
        expect(match.f2Score, equals(0));
      });
    });

    group('pause', () {
      test('round-trips paused_at through JSON', () {
        final match = Match(
          id: 'abcd',
          status: MatchStatus.inProgress,
          startAt: 123456789,
          pausedAt: 123456889,
          duration: 300,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#aabbcc',
          f2Color: '#ccddee',
        );

        final restored = Match.fromJsonString(match.toJsonString());

        expect(match.toJson()['paused_at'], equals(123456889));
        expect(restored.pausedAt, equals(123456889));
      });

      test('omits paused_at from JSON when the match is not paused', () {
        final match = Match(
          id: 'abcd',
          status: MatchStatus.inProgress,
          startAt: 123456789,
          duration: 300,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#aabbcc',
          f2Color: '#ccddee',
        );

        expect(match.toJson().containsKey('paused_at'), isFalse);
        expect(match.pausedAt, isNull);
      });

      test('copyWith clears pausedAt when passed null', () {
        final paused = Match(
          id: 'abcd',
          status: MatchStatus.inProgress,
          startAt: 123456789,
          pausedAt: 123456889,
          duration: 300,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#aabbcc',
          f2Color: '#ccddee',
        );

        expect(paused.copyWith(pausedAt: null).pausedAt, isNull);
        expect(paused.copyWith(f1Pt2: 1).pausedAt, equals(123456889));
      });

      test('rejects a pausedAt that precedes startAt', () {
        expect(
          () => Match(
            id: 'abcd',
            status: MatchStatus.inProgress,
            startAt: 123456789,
            pausedAt: 123456700,
            duration: 300,
            f1Name: 'Roger Gracie',
            f2Name: 'Buchecha',
            f1Color: '#aabbcc',
            f2Color: '#ccddee',
          ),
          throwsFormatException,
        );
      });
    });

    group('JSON serialization', () {
      test('serializes to JSON correctly', () {
        final match = Match(
          id: 'abcd',
          status: MatchStatus.inProgress,
          startAt: 123456789,
          duration: 600,
          f1Name: 'Roger Gracie',
          f2Name: 'Buchecha',
          f1Color: '#aabbcc',
          f2Color: '#ccddee',
          f1Pt2: 1,
          f2Pt2: 0,
          f1Pt3: 0,
          f2Pt3: 0,
          f1Pt4: 0,
          f2Pt4: 0,
          f1Adv: 0,
          f2Adv: 0,
          f1Pen: 1,
          f2Pen: 1,
        );

        final json = match.toJson();

        expect(json['id'], equals('abcd'));
        expect(json['status'], equals('in-progress'));
        expect(json['start_at'], equals(123456789));
        expect(json['duration'], equals(600));
        expect(json['f1_name'], equals('Roger Gracie'));
        expect(json['f2_name'], equals('Buchecha'));
        expect(json['f1_color'], equals('#aabbcc'));
        expect(json['f2_color'], equals('#ccddee'));
        expect(json['f1_pt2'], equals(1));
        expect(json['f2_pt2'], equals(0));
        expect(json['f1_pen'], equals(1));
        expect(json['f2_pen'], equals(1));
      });

      test('omits null start_at from JSON', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.waiting,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        final json = match.toJson();

        expect(json.containsKey('start_at'), isFalse);
      });

      test('deserializes from JSON correctly', () {
        final match = Match.fromJson(validMatchData);

        expect(match.id, equals('a3f7'));
        expect(match.status, equals(MatchStatus.waiting));
        expect(match.duration, equals(300));
        expect(match.f1Name, equals('Roger Gracie'));
        expect(match.f2Name, equals('Buchecha'));
      });

      test('deserializes with default values for missing counters', () {
        final json = {
          'id': 'a3f7',
          'status': 'in-progress',
          'duration': 300,
          'f1_name': 'A',
          'f2_name': 'B',
          'f1_color': '#FFFFFF',
          'f2_color': '#000000',
        };

        final match = Match.fromJson(json);

        expect(match.f1Pt2, equals(0));
        expect(match.f2Adv, equals(0));
      });

      test('round-trip JSON serialization preserves data', () {
        final original = Match(
          id: 'ab12',
          status: MatchStatus.finished,
          startAt: 1234567890,
          duration: 480,
          f1Name: 'Grappler 1',
          f2Name: 'Grappler 2',
          f1Color: '#123456',
          f2Color: '#ABCDEF',
          f1Pt2: 2,
          f2Pt2: 1,
          f1Pt3: 1,
          f2Pt3: 0,
          f1Pt4: 0,
          f2Pt4: 1,
          f1Adv: 3,
          f2Adv: 2,
          f1Pen: 0,
          f2Pen: 1,
        );

        final json = original.toJson();
        final restored = Match.fromJson(json);

        expect(restored.id, equals(original.id));
        expect(restored.status, equals(original.status));
        expect(restored.startAt, equals(original.startAt));
        expect(restored.duration, equals(original.duration));
        expect(restored.f1Name, equals(original.f1Name));
        expect(restored.f2Name, equals(original.f2Name));
        expect(restored.f1Color, equals(original.f1Color));
        expect(restored.f2Color, equals(original.f2Color));
        expect(restored.f1Pt2, equals(original.f1Pt2));
        expect(restored.f2Pt4, equals(original.f2Pt4));
        expect(restored.f1Adv, equals(original.f1Adv));
        expect(restored.f2Pen, equals(original.f2Pen));
      });

      test('serializes to JSON string', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.waiting,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        final jsonString = match.toJsonString();

        expect(jsonString, contains('"id":"a3f7"'));
        expect(jsonString, contains('"status":"waiting"'));
      });

      test('deserializes from JSON string', () {
        final jsonString =
            '{"id":"b4c1","status":"inProgress","duration":300,"f1_name":"X","f2_name":"Y","f1_color":"#FFF","f2_color":"#000"}';

        expect(
          () => Match.fromJsonString(jsonString),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('MatchStatus enum', () {
      test('serializes to JSON string', () {
        expect(MatchStatus.waiting.toJson(), equals('waiting'));
        expect(MatchStatus.inProgress.toJson(), equals('in-progress'));
        expect(MatchStatus.finished.toJson(), equals('finished'));
        expect(MatchStatus.canceled.toJson(), equals('canceled'));
      });

      test('deserializes from JSON string', () {
        expect(MatchStatus.fromJson('waiting'), equals(MatchStatus.waiting));
        expect(
          MatchStatus.fromJson('in-progress'),
          equals(MatchStatus.inProgress),
        );
        expect(MatchStatus.fromJson('finished'), equals(MatchStatus.finished));
        expect(MatchStatus.fromJson('canceled'), equals(MatchStatus.canceled));
      });

      test('throws on unknown status', () {
        expect(
          () => MatchStatus.fromJson('unknown'),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'message',
              contains('Unknown MatchStatus'),
            ),
          ),
        );
      });
    });

    group('copyWith', () {
      test('copies match with updated fields', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.waiting,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        final updated = match.copyWith(
          status: MatchStatus.inProgress,
          f1Pt2: match.f1Pt2 + 1,
        );

        expect(updated.id, equals('a3f7')); // unchanged
        expect(updated.f1Name, equals('A')); // unchanged
        expect(updated.status, equals(MatchStatus.inProgress)); // changed
        expect(updated.f1Pt2, equals(1)); // changed
        expect(updated.f2Pt2, equals(0)); // unchanged default
      });

      test('returns identical match when no changes', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        final copy = match.copyWith();

        expect(copy.id, equals(match.id));
        expect(copy.status, equals(match.status));
        expect(copy.f1Pt2, equals(match.f1Pt2));
      });
    });

    group('toString', () {
      test('returns descriptive string', () {
        final match = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'Roger',
          f2Name: 'Buchecha',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
        );

        final str = match.toString();

        expect(str, contains('a3f7'));
        expect(str, contains('inProgress'));
        expect(str, contains('Roger'));
        expect(str, contains('Buchecha'));
        expect(str, contains('2')); // f1Score
      });
    });

    group('equality', () {
      test('equal matches are equivalent', () {
        final match1 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
        );

        final match2 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
        );

        expect(match1, equals(match2));
        expect(match1.hashCode, equals(match2.hashCode));
      });

      test('different scores are not equal', () {
        final match1 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 1,
        );

        final match2 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'A',
          f2Name: 'B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
          f1Pt2: 2,
        );

        expect(match1, isNot(equals(match2)));
      });

      test('names do not affect equality', () {
        final match1 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'Athlete A',
          f2Name: 'Athlete B',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        final match2 = Match(
          id: 'a3f7',
          status: MatchStatus.inProgress,
          duration: 300,
          f1Name: 'Different Name',
          f2Name: 'Other Name',
          f1Color: '#FFFFFF',
          f2Color: '#000000',
        );

        expect(match1, equals(match2));
      });
    });
  });
}

// ─── Outcomes, penalties, and who actually won ─────────────────────────────
//
// See docs/specs/match-outcome.md. The bug that started this: Bob leads 4–0,
// Carlos submits him, and the app publishes a scoreboard naming Bob.

Match _match({
  MatchStatus status = MatchStatus.inProgress,
  int f1Pt2 = 0,
  int f2Pt2 = 0,
  int f1Adv = 0,
  int f2Adv = 0,
  int f1Pen = 0,
  int f2Pen = 0,
  MatchWinner? winner,
  MatchMethod? method,
  String? submission,
  DqReason? dqReason,
  String? dqDetail,
  int? endedAt,
}) {
  return Match(
    id: 'abcd',
    status: status,
    startAt: 1700000000,
    duration: 300,
    f1Name: 'Bob',
    f2Name: 'Carlos',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
    f1Pt2: f1Pt2,
    f2Pt2: f2Pt2,
    f1Adv: f1Adv,
    f2Adv: f2Adv,
    f1Pen: f1Pen,
    f2Pen: f2Pen,
    winner: winner,
    method: method,
    submission: submission,
    dqReason: dqReason,
    dqDetail: dqDetail,
    endedAt: endedAt,
  );
}

void _outcomeTests() {
  group('the penalty ladder', () {
    test('a first penalty concedes nothing', () {
      // Arrange & Act — a warning, and nothing more
      final match = _match(f2Pen: 1);

      // Assert
      expect(match.f1EffectivePoints, 0);
      expect(match.f1EffectiveAdvantages, 0);
    });

    test('a second penalty concedes an advantage to the opponent', () {
      // Act
      final match = _match(f2Pen: 2);

      // Assert
      expect(match.f1EffectiveAdvantages, 1);
      expect(match.f1EffectivePoints, 0, reason: 'points come at the third');
    });

    test('a third penalty concedes two points to the opponent', () {
      // Act
      final match = _match(f2Pen: 3);

      // Assert — this is the rung that changes who wins
      expect(match.f1EffectivePoints, 2);
      expect(match.f1EffectiveAdvantages, 1, reason: 'the second still stands');
    });

    test('a fourth penalty adds nothing to the arithmetic', () {
      // Arrange — it is a disqualification, and only a referee may call one
      final third = _match(f2Pen: 3);

      // Act
      final fourth = _match(f2Pen: 4);

      // Assert
      expect(fourth.f1EffectivePoints, third.f1EffectivePoints);
      expect(fourth.f1EffectiveAdvantages, third.f1EffectiveAdvantages);
    });

    test('the penalty points are added, not folded into the raw counters', () {
      // Arrange — Carlos's third penalty gives Bob two points
      final match = _match(f1Pt2: 1, f2Pen: 3);

      // Assert — Bob is credited with the points, but the record still says he
      // scored one takedown. Folding them in would claim a takedown that never
      // happened, and nothing would remember where the points came from.
      expect(match.f1EffectivePoints, 4);
      expect(match.f1Score, 2);
      expect(match.f1Pt2, 1);
    });

    test('both fighters can be penalised independently', () {
      // Act
      final match = _match(f1Pen: 3, f2Pen: 2);

      // Assert
      expect(match.f2EffectivePoints, 2, reason: "Bob's third penalty");
      expect(match.f2EffectiveAdvantages, 1);
      expect(match.f1EffectivePoints, 0, reason: 'Carlos only has two');
      expect(match.f1EffectiveAdvantages, 1);
    });

    test('four penalties are recognised, but not acted on', () {
      // Assert — the app offers the disqualification; it never imposes it
      expect(_match(f2Pen: 4).hasDisqualifyingPenalties, isTrue);
      expect(_match(f1Pen: 4).hasDisqualifyingPenalties, isTrue);
      expect(_match(f1Pen: 3, f2Pen: 3).hasDisqualifyingPenalties, isFalse);
    });
  });

  group('who the scoreboard says won', () {
    test('more points wins', () {
      // Act
      final match = _match(f1Pt2: 2);

      // Assert
      expect(match.scoreboardWinner, MatchWinner.f1);
      expect(match.scoreboardMethod, MatchMethod.points);
    });

    test('level on points, more advantages wins', () {
      // Act
      final match = _match(f1Pt2: 1, f2Pt2: 1, f2Adv: 1);

      // Assert
      expect(match.scoreboardWinner, MatchWinner.f2);
      expect(match.scoreboardMethod, MatchMethod.advantages);
    });

    test('level on both refuses to name a winner', () {
      // Arrange — the referees decide: a decision, or a draw
      final match = _match(f1Pt2: 1, f2Pt2: 1, f1Adv: 1, f2Adv: 1);

      // Assert — null is the honest answer, not a failure. Inventing a winner
      // here is exactly the lie this model exists to prevent.
      expect(match.scoreboardWinner, isNull);
      expect(match.scoreboardMethod, isNull);
    });

    test('a penalty can hand the match to the fighter who was behind', () {
      // Arrange — Bob leads 2–0 on the raw scoreboard…
      final match = _match(f1Pt2: 1, f2Pt2: 2, f2Pen: 0);
      expect(match.scoreboardWinner, MatchWinner.f2);

      // Act — …and now Carlos, who was winning 4–2, takes a third penalty
      final penalised = _match(f1Pt2: 1, f2Pt2: 2, f2Pen: 3);

      // Assert — 2 + 2 = 4 apiece on points, and Bob's conceded advantage
      // decides it. The penalty ladder is not cosmetic.
      expect(penalised.f1EffectivePoints, 4);
      expect(penalised.f2EffectivePoints, 4);
      expect(penalised.scoreboardWinner, MatchWinner.f1);
      expect(penalised.scoreboardMethod, MatchMethod.advantages);
    });

    test('penalties are never a tiebreak of their own', () {
      // Arrange — level on effective points and advantages, but Carlos has one
      // penalty (which concedes nothing).
      final match = _match(f2Pen: 1);

      // Assert — it stays level. Using the raw count as a further tiebreak
      // would count the same penalty twice: a fighter whose third penalty had
      // already handed two points away would then lose *again* for the count.
      expect(match.scoreboardWinner, isNull);
    });
  });

  group('legacy events are not re-refereed', () {
    test('a finished match with no method keeps its old arithmetic', () {
      // Arrange — an event published before outcomes existed: Bob won 2–0 while
      // Carlos carried three penalties, and the app that refereed it applied no
      // consequences at all.
      final legacy = _match(
        status: MatchStatus.finished,
        f1Pt2: 1,
        f2Pt2: 2,
        f2Pen: 3,
      );

      // Assert — reading it with the new ladder would make it 4–4, send it to
      // advantages, and flip the winner. Rewriting a result nobody re-refereed
      // is not our call.
      expect(legacy.isLegacyResult, isTrue);
      expect(legacy.f1EffectivePoints, 2);
      expect(legacy.f2EffectivePoints, 4);
      expect(legacy.scoreboardWinner, MatchWinner.f2);
    });

    test('a match this app finished is never legacy, even before phase 2', () {
      // Arrange — finishing stamps ended_at even when it cannot yet name a
      // method (a level scoreboard is the referees' to call). Keying the legacy
      // rule off `method` would make the app contradict itself: this 0–0 match
      // against three penalties reads 2–0 while it runs…
      final live = _match(f2Pen: 3);
      expect(live.f1EffectivePoints, 2);

      // Act — …and the referee presses Finish
      final finished = live.copyWith(
        status: MatchStatus.finished,
        endedAt: 1700000180,
      );

      // Assert — …and it still reads 2–0. The penalty points the referee
      // watched land do not vanish the instant they stop the clock.
      expect(finished.isLegacyResult, isFalse);
      expect(finished.f1EffectivePoints, 2);
    });

    test('a canceled match is legacy too', () {
      expect(
        _match(status: MatchStatus.canceled, f2Pen: 3).isLegacyResult,
        isTrue,
      );
    });

    test('a match in progress is never legacy, whatever it carries', () {
      // Arrange — this is the case the field-presence rule alone gets wrong: a
      // live match has no method or ended_at *yet*, but it is being refereed
      // right now, by this app, under these rules. The referee has to see the
      // penalty they just gave turn into the opponent's points.
      final live = _match(f2Pen: 3);

      // Assert
      expect(live.isLegacyResult, isFalse);
      expect(live.f1EffectivePoints, 2);
    });

    test('a finished match that states its method uses the new ladder', () {
      // Act
      final modern = _match(
        status: MatchStatus.finished,
        f1Pt2: 1,
        f2Pen: 3,
        winner: MatchWinner.f1,
        method: MatchMethod.points,
        endedAt: 1700000180,
      );

      // Assert
      expect(modern.isLegacyResult, isFalse);
      expect(modern.f1EffectivePoints, 4);
    });
  });

  group('an outcome must be internally consistent', () {
    test('a draw has no winner', () {
      // Assert — a consumer handed both would have to guess which half to
      // believe
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.draw,
          winner: MatchWinner.f1,
          endedAt: 1700000180,
        ),
        throwsFormatException,
      );
    });

    test('every other method needs a winner', () {
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.submission,
          endedAt: 1700000180,
        ),
        throwsFormatException,
      );
    });

    test('a disqualification needs a reason', () {
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.dq,
          winner: MatchWinner.f1,
          endedAt: 1700000180,
        ),
        throwsFormatException,
      );
    });

    test('a reason without a disqualification is meaningless', () {
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.points,
          winner: MatchWinner.f1,
          dqReason: DqReason.technicalFoul,
          endedAt: 1700000180,
        ),
        throwsFormatException,
      );
    });

    test('an outcome needs an ending time', () {
      // Arrange — start_at + duration is when the clock *would* have run out,
      // which is exactly what a submission prevents
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.submission,
          winner: MatchWinner.f2,
        ),
        throwsFormatException,
      );
    });

    test('a winner without a method is refused', () {
      // Arrange — it says who won and not what they won by, which is half an
      // answer: a consumer cannot tell a submission from a points decision
      expect(
        () => _match(
          status: MatchStatus.finished,
          winner: MatchWinner.f1,
          endedAt: 1700000180,
        ),
        throwsFormatException,
      );
    });

    test('a match cannot have ended before it began', () {
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.submission,
          winner: MatchWinner.f2,
          endedAt: 1699999999, // startAt is 1700000000
        ),
        throwsFormatException,
      );
    });

    test('a draw is valid with no winner', () {
      expect(
        () => _match(
          status: MatchStatus.finished,
          method: MatchMethod.draw,
          endedAt: 1700000180,
        ),
        returnsNormally,
      );
    });
  });

  group('the outcome survives the wire', () {
    test('Carlos beat Bob by armbar, and the JSON says so', () {
      // Arrange — the bug, fixed: Bob leads 4–0 and still loses
      final match = _match(
        status: MatchStatus.finished,
        f1Pt2: 2,
        winner: MatchWinner.f2,
        method: MatchMethod.submission,
        submission: 'armbar',
        endedAt: 1700000180,
      );

      // Act
      final json = jsonDecode(match.toJsonString()) as Map<String, dynamic>;

      // Assert
      expect(json['winner'], 'f2');
      expect(json['method'], 'submission');
      expect(json['submission'], 'armbar');
      expect(json['ended_at'], 1700000180);
      expect(json['f1_pt2'], 2, reason: 'the raw record is still the record');
    });

    test('a disqualification round-trips whole', () {
      // Arrange
      final match = _match(
        status: MatchStatus.finished,
        winner: MatchWinner.f1,
        method: MatchMethod.dq,
        dqReason: DqReason.technicalFoul,
        dqDetail: 'knee reap',
        endedAt: 1700000180,
      );

      // Act
      final parsed = Match.fromJsonString(match.toJsonString());

      // Assert
      expect(parsed.method, MatchMethod.dq);
      expect(parsed.dqReason, DqReason.technicalFoul);
      expect(parsed.dqDetail, 'knee reap');
      expect(parsed.winner, MatchWinner.f1);
      expect(parsed.endedAt, 1700000180);
    });

    test('an unfinished match carries no outcome at all', () {
      // Assert — the keys are absent, not null: an old client reading them
      // must see nothing, not a null it has to interpret
      final json = jsonDecode(_match().toJsonString()) as Map<String, dynamic>;
      expect(json.containsKey('winner'), isFalse);
      expect(json.containsKey('method'), isFalse);
      expect(json.containsKey('ended_at'), isFalse);
    });

    test('an event from before outcomes existed still parses', () {
      // Arrange — exactly what an old app published
      const legacy = '{"id":"abcd","status":"finished","start_at":1700000000,'
          '"duration":300,"f1_name":"Bob","f2_name":"Carlos",'
          '"f1_color":"#1BA34E","f2_color":"#F5B800",'
          '"f1_pt2":2,"f2_pt2":0,"f1_pt3":0,"f2_pt3":0,"f1_pt4":0,"f2_pt4":0,'
          '"f1_adv":0,"f2_adv":0,"f1_pen":0,"f2_pen":3}';

      // Act
      final match = Match.fromJsonString(legacy);

      // Assert — it parses, it knows it is legacy, and it is left alone
      expect(match.method, isNull);
      expect(match.winner, isNull);
      expect(match.isLegacyResult, isTrue);
      expect(match.f1EffectivePoints, 4,
          reason: 'raw score, no penalty points');
    });

    test('an unknown method is a hard error, not a silent null', () {
      // Arrange — a future client publishing something we do not understand.
      // Guessing would mean rendering a match whose result we cannot read.
      const unknown = '{"id":"abcd","status":"finished","duration":300,'
          '"f1_name":"Bob","f2_name":"Carlos",'
          '"f1_color":"#1BA34E","f2_color":"#F5B800","method":"telepathy"}';

      // Act & Assert
      expect(() => Match.fromJsonString(unknown), throwsFormatException);
    });
  });

  group('copyWith', () {
    test('records an outcome on a match that had none', () {
      // Act
      final finished = _match().copyWith(
        status: MatchStatus.finished,
        winner: MatchWinner.f2,
        method: MatchMethod.submission,
        submission: 'triangle',
        endedAt: 1700000180,
      );

      // Assert
      expect(finished.winner, MatchWinner.f2);
      expect(finished.method, MatchMethod.submission);
      expect(finished.submission, 'triangle');
    });

    test('clears an outcome when passed null explicitly', () {
      // Arrange — amending a result (phase 3) has to be able to take one back
      final finished = _match(
        status: MatchStatus.finished,
        winner: MatchWinner.f2,
        method: MatchMethod.submission,
        endedAt: 1700000180,
      );

      // Act
      final reopened = finished.copyWith(
        status: MatchStatus.inProgress,
        winner: null,
        method: null,
        endedAt: null,
      );

      // Assert
      expect(reopened.winner, isNull);
      expect(reopened.method, isNull);
    });

    test('a match that gains an outcome is not equal to the one it was', () {
      // Arrange — the scores are identical and the winner is the *other*
      // fighter. Equality that ignored the outcome would let a stale card sit
      // on the home feed showing Bob winning a match Carlos submitted him in.
      final live = _match(f1Pt2: 2);

      // Act
      final finished = live.copyWith(
        status: MatchStatus.finished,
        winner: MatchWinner.f2,
        method: MatchMethod.submission,
        endedAt: 1700000180,
      );

      // Assert
      expect(finished, isNot(live));
    });
  });
}
