import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/providers/match_control_provider.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';

import '../../../support/nostr_fakes.dart';

/// Fake NostrService that skips relay publishing entirely.
///
/// [failuresRemaining] makes the next N publishes throw (relay down).
/// [gate] holds a publish in flight until completed (slow relay).
class _FakeNostrService extends NostrService {
  _FakeNostrService() : super(KeyManager(crypto: FakeNostrCrypto()),
            crypto: FakeNostrCrypto(), backend: FakeRelayBackend());

  int publishCount = 0;
  final List<String> publishedContents = [];
  int failuresRemaining = 0;
  Completer<void>? gate;

  /// Lets tests simulate a relay (re)connecting.
  final relayConnected = StreamController<String>.broadcast();

  @override
  Stream<String> get onRelayConnected => relayConnected.stream;

  Match get lastPublishedMatch =>
      Match.fromJsonString(publishedContents.last);

  @override
  Future<void> publishAddressableEvent({
    required String dTag,
    required String content,
    List<List<String>> additionalTags = const [],
  }) async {
    final g = gate;
    if (g != null) await g.future;
    if (failuresRemaining > 0) {
      failuresRemaining--;
      throw Exception('relay down');
    }
    publishCount++;
    publishedContents.add(content);
  }
}

Match _runningMatch() {
  return Match(
    id: 'abcd',
    status: MatchStatus.inProgress,
    startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    duration: 300,
    f1Name: 'Pana',
    f2Name: 'Buchecha',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
  );
}

void main() {
  late _FakeNostrService nostr;
  late MatchControlNotifier notifier;

  tearDown(() async {
    // Let queued publish futures settle before disposing
    await Future<void>.delayed(Duration.zero);
    notifier.dispose();
  });

  group('score (existing behavior)', () {
    test('scorePt2 increments fighter 1 takedown count', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.scorePt2(1);

      // Assert
      expect(notifier.state.match.f1Pt2, 1);
      expect(notifier.state.match.f1Score, 2);
    });
  });

  group('subtract', () {
    test('subtractPt2 decrements fighter 1 takedown count', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      notifier.scorePt2(1);

      // Act
      notifier.subtractPt2(1);

      // Assert
      expect(notifier.state.match.f1Pt2, 1);
      expect(notifier.state.match.f1Score, 2);
    });

    test('subtractPt3 and subtractPt4 decrement their counts', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt3(2);
      notifier.scorePt4(2);

      // Act
      notifier.subtractPt3(2);
      notifier.subtractPt4(2);

      // Assert
      expect(notifier.state.match.f2Pt3, 0);
      expect(notifier.state.match.f2Pt4, 0);
      expect(notifier.state.match.f2Score, 0);
    });

    test('subtractAdv and subtractPen decrement advantage/penalty', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scoreAdv(1);
      notifier.scorePen(1);

      // Act
      notifier.subtractAdv(1);
      notifier.subtractPen(1);

      // Assert
      expect(notifier.state.match.f1Adv, 0);
      expect(notifier.state.match.f1Pen, 0);
    });

    test('subtract at zero is a no-op and adds nothing to undo stack', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.subtractPt2(1);

      // Assert
      expect(notifier.state.match.f1Pt2, 0);
      expect(notifier.state.canUndo, isFalse);
    });

    test('subtract is ignored when match is not running', () {
      // Arrange
      nostr = _FakeNostrService();
      final waiting = _runningMatch().copyWith(
        status: MatchStatus.waiting,
        f1Pt2: 3,
      );
      notifier = MatchControlNotifier(waiting, nostr);

      // Act
      notifier.subtractPt2(1);

      // Assert
      expect(notifier.state.match.f1Pt2, 3);
    });

    test('undo after subtract restores the subtracted count', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      notifier.subtractPt2(1);

      // Act
      notifier.undo();

      // Assert
      expect(notifier.state.match.f1Pt2, 1);
    });

    test('undo after add still removes the added count', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt4(2);

      // Act
      notifier.undo();

      // Assert
      expect(notifier.state.match.f2Pt4, 0);
    });

    test('subtract publishes the updated state', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      await Future<void>.delayed(Duration.zero);
      final publishesBefore = nostr.publishCount;

      // Act
      notifier.subtractPt2(1);
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(nostr.publishCount, greaterThan(publishesBefore));
    });
  });

  group('time expiry', () {
    test('match finishes when the timer reaches zero', () async {
      // Arrange — a running match with one second left on the clock
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      notifier = MatchControlNotifier(almostOver, nostr);
      expect(notifier.state.match.status, MatchStatus.inProgress);

      // Act — let the clock run out
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert
      expect(notifier.state.remainingSeconds, 0);
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.isRunning, isFalse);
    });

    test('reopening a match whose time already elapsed finishes it', () {
      // Arrange — started 10 minutes ago with a 5 minute duration
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expired = _runningMatch().copyWith(
        duration: 300,
        startAt: now - 600,
      );

      // Act
      notifier = MatchControlNotifier(expired, nostr);

      // Assert
      expect(notifier.state.remainingSeconds, 0);
      expect(notifier.state.match.status, MatchStatus.finished);
    });

    test('expiring the clock publishes the finished match', () async {
      // Arrange
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expired = _runningMatch().copyWith(
        duration: 300,
        startAt: now - 600,
      );

      // Act
      notifier = MatchControlNotifier(expired, nostr);
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(nostr.publishCount, greaterThan(0));
    });

    test('a match finished by the clock keeps its score', () async {
      // Arrange
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      notifier = MatchControlNotifier(almostOver, nostr);
      notifier.scorePt4(1);

      // Act
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.match.f1Score, 4);
    });
  });

  group('pause and resume', () {
    test('pausing freezes the clock', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.pauseMatch();
      final frozen = notifier.state.remainingSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert
      expect(notifier.state.isPaused, isTrue);
      expect(notifier.state.remainingSeconds, frozen);
    });

    test('a paused match is still in progress', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.pauseMatch();

      // Assert
      expect(notifier.state.match.status, MatchStatus.inProgress);
    });

    test('resuming does not charge the paused seconds to the clock', () async {
      // Arrange — pause, then let real time pass as fighters reset on the mat
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.pauseMatch();
      final frozen = notifier.state.remainingSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Act
      notifier.resumeMatch();

      // Assert
      expect(notifier.state.isPaused, isFalse);
      expect(notifier.state.remainingSeconds, frozen);
    });

    test('the clock ticks down again after resuming', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.pauseMatch();
      final frozen = notifier.state.remainingSeconds;

      // Act
      notifier.resumeMatch();
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert
      expect(notifier.state.remainingSeconds, lessThan(frozen));
    });

    test('a paused match does not finish itself', () async {
      // Arrange — one second left, then paused before it can expire
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      notifier = MatchControlNotifier(almostOver, nostr);

      // Act
      notifier.pauseMatch();
      await Future<void>.delayed(const Duration(milliseconds: 2000));

      // Assert
      expect(notifier.state.match.status, MatchStatus.inProgress);
    });

    test('reopening a paused match keeps it paused with its clock intact', () {
      // Arrange — paused with 200s left; wall-clock time kept running while
      // the app was closed, but a paused clock does not drain.
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final paused = _runningMatch().copyWith(
        duration: 300,
        startAt: now - 700,
        pausedAt: now - 600,
      );

      // Act
      notifier = MatchControlNotifier(paused, nostr);

      // Assert
      expect(notifier.state.isPaused, isTrue);
      expect(notifier.state.remainingSeconds, 200);
      expect(notifier.state.match.status, MatchStatus.inProgress);
    });

    test('pausing freezes the clock at what it reads now, not at the last tick',
        () async {
      // Arrange — a match already 10 seconds in
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      notifier = MatchControlNotifier(
        _runningMatch().copyWith(duration: 300, startAt: now - 10),
        nostr,
      );

      // Act
      notifier.pauseMatch();

      // Assert — the frozen clock agrees with the timestamp that was stored,
      // so a stalled timer cannot put seconds back on it.
      final m = notifier.state.match;
      expect(
        notifier.state.remainingSeconds,
        m.duration - (m.pausedAt! - m.startAt!),
      );
    });

    test('pausing publishes the paused state', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      await Future<void>.delayed(Duration.zero);
      final publishesBefore = nostr.publishCount;

      // Act
      notifier.pauseMatch();
      await Future<void>.delayed(Duration.zero);

      // Assert
      expect(nostr.publishCount, greaterThan(publishesBefore));
    });

    test('pause is ignored when the match has not started', () {
      // Arrange
      nostr = _FakeNostrService();
      final waiting = _runningMatch().copyWith(status: MatchStatus.waiting);
      notifier = MatchControlNotifier(waiting, nostr);

      // Act
      notifier.pauseMatch();

      // Assert
      expect(notifier.state.isPaused, isFalse);
    });

    test('scoring still works while paused', () {
      // Arrange — the referee awards points during a stoppage
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.pauseMatch();
      notifier.scorePt2(1);

      // Assert
      expect(notifier.state.match.f1Score, 2);
    });

    test('finishing a paused match clears the pause', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.pauseMatch();

      // Act
      notifier.finishMatch();

      // Assert
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.isPaused, isFalse);
    });
  });

  group('publish reliability', () {
    test('a failed publish is retried until the relay has the latest state',
        () async {
      // Arrange — the relay rejects the first attempt
      nostr = _FakeNostrService()..failuresRemaining = 1;
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.scorePt2(1);
      await Future<void>.delayed(Duration.zero);
      expect(nostr.publishCount, 0, reason: 'first attempt must have failed');

      // Assert — the retry lands on its own, no user action needed
      await Future<void>.delayed(const Duration(milliseconds: 2400));
      expect(nostr.publishCount, greaterThan(0));
      expect(nostr.lastPublishedMatch.f1Score, 2);
    });

    test('actions during an in-flight publish are sent right after it',
        () async {
      // Arrange — a slow relay holds the first publish in flight
      nostr = _FakeNostrService()..gate = Completer();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      await Future<void>.delayed(Duration.zero);

      // Act — two more scores land while the first publish hangs
      notifier.scorePt2(1);
      notifier.scorePt3(1);
      nostr.gate!.complete();
      nostr.gate = null;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — the final published event carries the full 2+2+3
      expect(nostr.lastPublishedMatch.f1Score, 7);
    });

    test('finishing during an in-flight publish still lands as finished',
        () async {
      // Arrange
      nostr = _FakeNostrService()..gate = Completer();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      await Future<void>.delayed(Duration.zero);

      // Act
      notifier.finishMatch();
      nostr.gate!.complete();
      nostr.gate = null;
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — the relay must never be left believing in-progress
      expect(nostr.lastPublishedMatch.status, MatchStatus.finished);
    });

    test('a finish whose publish fails is retried until it lands', () async {
      // Arrange
      nostr = _FakeNostrService()..failuresRemaining = 1;
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.finishMatch();
      await Future<void>.delayed(Duration.zero);
      expect(nostr.publishedContents, isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 2400));

      // Assert
      expect(nostr.lastPublishedMatch.status, MatchStatus.finished);
    });

    test('a new action supersedes a scheduled retry with the newer state',
        () async {
      // Arrange — first publish fails, a retry gets scheduled
      nostr = _FakeNostrService()..failuresRemaining = 1;
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(1);
      await Future<void>.delayed(Duration.zero);

      // Act — before the retry fires, another score arrives
      notifier.scorePt3(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — publishes immediately with the combined state
      expect(nostr.lastPublishedMatch.f1Score, 5);
    });

    test('a pending state is published the moment a relay reconnects',
        () async {
      // Arrange — the relay is unreachable: the advantage fails to publish
      // and sits in the outbox behind a backoff timer
      nostr = _FakeNostrService()..failuresRemaining = 1;
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scoreAdv(1);
      await Future<void>.delayed(Duration.zero);
      expect(nostr.publishCount, 0, reason: 'publish must have failed');

      // Act — the relay comes back before the backoff runs out
      nostr.relayConnected.add('wss://relay.test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — the advantage lands right away, not seconds later
      expect(nostr.publishCount, greaterThan(0));
      expect(nostr.lastPublishedMatch.f1Adv, 1);
    });

    test('a reconnect with nothing pending publishes nothing', () async {
      // Arrange — everything already confirmed
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scoreAdv(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final publishesBefore = nostr.publishCount;

      // Act
      nostr.relayConnected.add('wss://relay.test');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert
      expect(nostr.publishCount, publishesBefore);
    });
  });
}
