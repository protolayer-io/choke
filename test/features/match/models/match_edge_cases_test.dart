import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/services/nostr/nostr_service.dart';

Match _match({
  String id = 'abcd',
  MatchStatus status = MatchStatus.waiting,
  int? startAt,
  int duration = 300,
  int f1Adv = 0,
  int f1Pen = 0,
}) {
  return Match(
    id: id,
    status: status,
    startAt: startAt,
    duration: duration,
    f1Name: 'Pana',
    f2Name: 'Buchecha',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
    f1Adv: f1Adv,
    f1Pen: f1Pen,
  );
}

void main() {
  group('MatchWinner.fromJson', () {
    test('throws on an unknown winner value', () {
      // Arrange — an event authored by a buggy or malicious client
      // Act + Assert — refusing beats silently crowning nobody
      expect(
        () => MatchWinner.fromJson('f3'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('MatchMethod.overridesScoreboard', () {
    test('submission, dq and forfeit beat the scoreboard', () {
      // These three are the whole reason the outcome model exists: the
      // fighter who was ahead on points can still lose.
      expect(MatchMethod.submission.overridesScoreboard, isTrue);
      expect(MatchMethod.dq.overridesScoreboard, isTrue);
      expect(MatchMethod.forfeit.overridesScoreboard, isTrue);
    });

    test('scoreboard methods do not override the scoreboard', () {
      // Points, advantages, decision and draw *are* the scoreboard (or the
      // referees resolving a level one) — nothing to override.
      expect(MatchMethod.points.overridesScoreboard, isFalse);
      expect(MatchMethod.advantages.overridesScoreboard, isFalse);
      expect(MatchMethod.decision.overridesScoreboard, isFalse);
      expect(MatchMethod.draw.overridesScoreboard, isFalse);
    });
  });

  group('DqReason JSON round-trip', () {
    test('every reason survives toJson/fromJson unchanged', () {
      // Arrange + Act + Assert — the wire format is snake_case and must
      // stay stable: events already published carry these strings forever
      for (final reason in DqReason.values) {
        expect(DqReason.fromJson(reason.toJson()), reason);
      }
      expect(DqReason.disciplinaryFoul.toJson(), 'disciplinary_foul');
    });

    test('throws on an unknown dq_reason', () {
      expect(
        () => DqReason.fromJson('slam'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('validation edge cases', () {
    test('rejects an invalid f2Color even when f1Color is valid', () {
      // Both fighters get the same guarantee — a bad second color must not
      // slip through because the first one validated.
      expect(
        () => Match(
          id: 'abcd',
          status: MatchStatus.waiting,
          duration: 300,
          f1Name: 'Pana',
          f2Name: 'Buchecha',
          f1Color: '#1BA34E',
          f2Color: 'gold',
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a negative endedAt', () {
      // A negative unix timestamp is a corrupt event, not a very old match.
      expect(
        () => _match(startAt: 100).copyWith(
          status: MatchStatus.finished,
          winner: MatchWinner.f1,
          method: MatchMethod.points,
          endedAt: -5,
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('rejects a negative pausedAt', () {
      expect(
        () => _match(status: MatchStatus.inProgress, startAt: 100)
            .copyWith(pausedAt: -1),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('score display', () {
    test('a plain score shows just the number', () {
      // Arrange
      final match = _match();

      // Act + Assert
      expect(match.getF1ScoreDisplay(), '0');
      expect(match.getF2ScoreDisplay(), '0');
    });

    test('advantages and penalties are appended when present', () {
      // Arrange — fighter 1 has an advantage and a penalty on the card
      final match = _match(f1Adv: 1, f1Pen: 2).copyWith(f1Pt2: 1);

      // Act + Assert — the notation reads like a referee's card, not a
      // debug dump; zero counts stay silent so a clean card stays clean
      expect(match.getF1ScoreDisplay(), '2 | 1 adv | 2 pen');
      expect(match.getF2ScoreDisplay(), '0');
    });
  });

  group('toNostrEvent', () {
    test('a started match carries an expiration derived from its clock', () {
      // Arrange
      final match = _match(status: MatchStatus.inProgress, startAt: 1000);

      // Act
      final event = match.toNostrEvent(pubkey: 'a' * 64);

      // Assert — kind 31415, addressable by the match ID, and expiring when
      // regulation time runs out so relays can drop stale boards
      expect(event.kind, 31415);
      expect(event.pubkey, 'a' * 64);
      expect(event.tags, anyElement(orderedEquals(['d', 'abcd'])));
      expect(event.tags, anyElement(orderedEquals(['expiration', '1300'])));
      expect(event.content, match.toJsonString());
      expect(event.id, isEmpty, reason: 'must be signed externally');
      expect(event.sig, isEmpty, reason: 'must be signed externally');
    });

    test('an unstarted match has no expiration to declare', () {
      // Arrange — a waiting match has no startAt, so no honest expiry exists
      final match = _match();

      // Act
      final event = match.toNostrEvent(pubkey: 'b' * 64);

      // Assert
      expect(event.tags.where((t) => t.first == 'expiration'), isEmpty);
      expect(event.tags, anyElement(orderedEquals(['d', 'abcd'])));
    });
  });

  group('fromNostrEvent rejection', () {
    NostrEvent event({int kind = 31415, String? dTag, String? content}) {
      final match = _match();
      return NostrEvent(
        id: 'e1',
        pubkey: 'pk',
        createdAt: 1000,
        kind: kind,
        tags: [
          if (dTag != null) ['d', dTag],
        ],
        content: content ?? match.toJsonString(),
        sig: '',
      );
    }

    test('refuses an event of the wrong kind', () {
      // A kind-1 note whose content happens to parse as a match is still
      // not a match event.
      expect(
        () => Match.fromNostrEvent(event(kind: 1, dTag: 'abcd')),
        throwsA(isA<FormatException>()),
      );
    });

    test('refuses a d tag that contradicts the content', () {
      // The d tag is what relays replace by; content is what clients read.
      // If they disagree, one board would silently overwrite another match.
      expect(
        () => Match.fromNostrEvent(event(dTag: 'ffff')),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
