import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/providers/match_providers.dart';

Match _match({String id = 'abcd', int f1Pt2 = 0}) {
  return Match(
    id: id,
    status: MatchStatus.waiting,
    duration: 300,
    f1Name: 'Pana',
    f2Name: 'Buchecha',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
    f1Pt2: f1Pt2,
  );
}

void main() {
  group('MatchListNotifier', () {
    late MatchListNotifier notifier;

    setUp(() {
      notifier = MatchListNotifier();
    });

    tearDown(() {
      notifier.dispose();
    });

    test('addMatch puts a new match on top of the list', () {
      // Arrange
      notifier.addMatch(_match(id: 'aaaa'));

      // Act — a newer match arrives
      notifier.addMatch(_match(id: 'bbbb'));

      // Assert — newest first, so the screen shows the match the referee
      // just created without scrolling
      expect(notifier.state.map((m) => m.id), ['bbbb', 'aaaa']);
    });

    test('addMatch refuses a duplicate ID', () {
      // Arrange — the same match can arrive twice (created locally, then
      // echoed back from a relay)
      notifier.addMatch(_match(id: 'aaaa'));

      // Act
      notifier.addMatch(_match(id: 'aaaa'));

      // Assert — one match, not two rows for the same bout
      expect(notifier.state, hasLength(1));
    });

    test('removeMatch drops only the match with that ID', () {
      // Arrange
      notifier.addMatch(_match(id: 'aaaa'));
      notifier.addMatch(_match(id: 'bbbb'));

      // Act
      notifier.removeMatch('aaaa');

      // Assert
      expect(notifier.state.single.id, 'bbbb');
    });

    test('updateMatch replaces the match with the same ID in place', () {
      // Arrange
      notifier.addMatch(_match(id: 'aaaa'));
      notifier.addMatch(_match(id: 'bbbb'));

      // Act — a score lands on match aaaa
      notifier.updateMatch(_match(id: 'aaaa', f1Pt2: 1));

      // Assert — same position, new data; the other match is untouched
      expect(notifier.state.map((m) => m.id), ['bbbb', 'aaaa']);
      expect(notifier.state.last.f1Pt2, 1);
      expect(notifier.state.first.f1Pt2, 0);
    });

    test('getMatch returns the match when it exists', () {
      // Arrange
      notifier.addMatch(_match(id: 'aaaa'));

      // Act + Assert
      expect(notifier.getMatch('aaaa')?.id, 'aaaa');
    });

    test('getMatch returns null for an unknown ID instead of throwing', () {
      // Arrange — an empty list is the common case on a fresh install

      // Act + Assert — a missing match is an answer, not an error
      expect(notifier.getMatch('ffff'), isNull);
    });
  });

  group('matchListProvider', () {
    test('starts empty and exposes the notifier', () {
      // Arrange
      final container = ProviderContainer();
      addTearDown(container.dispose);

      // Act
      final matches = container.read(matchListProvider);
      container.read(matchListProvider.notifier).addMatch(_match());

      // Assert
      expect(matches, isEmpty);
      expect(container.read(matchListProvider), hasLength(1));
    });
  });
}
