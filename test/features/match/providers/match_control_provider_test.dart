import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/models/match_outcome.dart';
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
    test('the clock finishes a match one fighter is winning', () async {
      // Arrange — one second left, and Pana is ahead
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        f1Pt2: 1,
      );
      notifier = MatchControlNotifier(almostOver, nostr);

      // Act — let the clock run out
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert — the scoreboard decides it, and says so
      expect(notifier.state.remainingSeconds, 0);
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.match.winner, MatchWinner.f1);
      expect(notifier.state.match.method, MatchMethod.points);
      expect(notifier.state.match.endedAt, isNotNull);
      expect(notifier.state.awaitsOutcome, isFalse);
    });

    test('the clock does not finish a level match — it asks', () async {
      // Arrange — one second left, nobody has scored
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      );
      notifier = MatchControlNotifier(almostOver, nostr);

      // Act
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert — a level scoreboard is a question, not an answer. The match
      // stays open until a referee says how it ended; inventing a winner here
      // is exactly the lie this feature exists to remove.
      expect(notifier.state.remainingSeconds, 0);
      expect(notifier.state.awaitsOutcome, isTrue);
      expect(notifier.state.match.status, MatchStatus.inProgress);
      expect(notifier.state.match.winner, isNull);
    });

    test('the clock does not finish a match on points when someone has four '
        'penalties', () async {
      // Arrange — Pana is comfortably ahead, but has four penalties of his own
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        f1Pt4: 2,
        f1Pen: 4,
      );
      notifier = MatchControlNotifier(almostOver, nostr);

      // Act
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert — closing this on points would swallow the disqualification
      // whole: it would name a winner and say nothing about why the other
      // fighter is not one. Only a referee may call a DQ.
      expect(notifier.state.awaitsOutcome, isTrue);
      expect(notifier.state.match.status, MatchStatus.inProgress);
      expect(
        notifier.state.suggestedOutcome!.method,
        MatchMethod.dq,
        reason: 'and the sheet offers exactly that',
      );
      expect(notifier.state.suggestedOutcome!.winner, MatchWinner.f2);
    });

    test('reopening a match whose time elapsed asks how it ended', () {
      // Arrange — started 10 minutes ago with a 5 minute duration, level
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expired = _runningMatch().copyWith(
        duration: 300,
        startAt: now - 600,
      );

      // Act
      notifier = MatchControlNotifier(expired, nostr);

      // Assert — the clock is spent, but nobody has decided it
      expect(notifier.state.remainingSeconds, 0);
      expect(notifier.state.awaitsOutcome, isTrue);
    });

    test('reopening a match whose time elapsed with a leader finishes it', () {
      // Arrange
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expired = _runningMatch().copyWith(
        duration: 300,
        startAt: now - 600,
        f2Pt3: 1,
      );

      // Act
      notifier = MatchControlNotifier(expired, nostr);

      // Assert
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.match.winner, MatchWinner.f2);
    });

    test('expiring the clock publishes, decided or not', () async {
      // Arrange — level, so it is not finished; the stopped clock is still
      // state the relay must have
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
      expect(notifier.state.match.winner, MatchWinner.f1);
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
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f1));

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
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f1));
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
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f1));
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

  group('finishing with an outcome', () {
    test('a submission beats the scoreboard', () async {
      // Arrange — the bug this whole feature exists for: Pana leads 4–0…
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt4(1);
      expect(notifier.state.match.f1Score, 4);

      // Act — …and Buchecha armbars him
      notifier.finishWith(
        const MatchOutcome.submissionBy(MatchWinner.f2, submission: 'armbar'),
      );
      await Future<void>.delayed(Duration.zero);

      // Assert — the event names the fighter who actually won, and still keeps
      // the scoreboard that says he was losing
      final published = nostr.lastPublishedMatch;
      expect(published.winner, MatchWinner.f2);
      expect(published.method, MatchMethod.submission);
      expect(published.submission, 'armbar');
      expect(published.f1Score, 4, reason: 'the raw record is still the record');
      expect(published.status, MatchStatus.finished);
      expect(published.endedAt, isNotNull);
    });

    test('a disqualification records its reason', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.finishWith(
        const MatchOutcome.disqualifying(
          MatchWinner.f1,
          DqReason.technicalFoul,
          dqDetail: 'knee reap',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      // Assert
      final published = nostr.lastPublishedMatch;
      expect(published.method, MatchMethod.dq);
      expect(published.dqReason, DqReason.technicalFoul);
      expect(published.dqDetail, 'knee reap');
      expect(published.winner, MatchWinner.f1);
    });

    test('a draw has no winner', () async {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.finishWith(const MatchOutcome.draw());
      await Future<void>.delayed(Duration.zero);

      // Assert
      final published = nostr.lastPublishedMatch;
      expect(published.method, MatchMethod.draw);
      expect(published.winner, isNull);
    });

    test('an already finished match cannot be finished again', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f1));

      // Act — a second tap on a sheet that was already answered
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f2));

      // Assert — the first result stands
      expect(notifier.state.match.winner, MatchWinner.f1);
    });
  });

  group('what the sheet offers', () {
    test('the fighter who is ahead, on points', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt3(2);

      // Assert
      final suggested = notifier.state.suggestedOutcome!;
      expect(suggested.winner, MatchWinner.f2);
      expect(suggested.method, MatchMethod.points);
    });

    test('nothing at all when the fighters are level', () {
      // Arrange — the referees have to decide, and the app must not guess
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Assert
      expect(notifier.state.suggestedOutcome, isNull);
    });

    test('a penalty can move the suggestion to the other fighter', () {
      // Arrange — Buchecha leads 2–0
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      notifier.scorePt2(2);
      expect(notifier.state.suggestedOutcome!.winner, MatchWinner.f2);

      // Act — and picks up three penalties, conceding two points and an
      // advantage
      notifier.scorePen(2);
      notifier.scorePen(2);
      notifier.scorePen(2);

      // Assert — 2–2 on points, and Pana's conceded advantage decides it
      final suggested = notifier.state.suggestedOutcome!;
      expect(suggested.winner, MatchWinner.f1);
      expect(suggested.method, MatchMethod.advantages);
    });

    test('a disqualification once a fighter has four penalties', () {
      // Arrange
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      for (var i = 0; i < 4; i++) {
        notifier.scorePen(1);
      }

      // Assert — offered, never imposed: the match is still running, and the
      // referee still has to end it
      expect(notifier.state.match.status, MatchStatus.inProgress);
      final suggested = notifier.state.suggestedOutcome!;
      expect(suggested.method, MatchMethod.dq);
      expect(suggested.dqReason, DqReason.accumulatedPenalties);
      expect(suggested.winner, MatchWinner.f2);
    });

    test('a mis-tapped fourth penalty is taken back by holding', () {
      // Arrange — this is why the fourth penalty does not end the match: a fat
      // thumb must not be able to disqualify a fighter irrecoverably
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      for (var i = 0; i < 4; i++) {
        notifier.scorePen(1);
      }
      expect(notifier.state.match.hasDisqualifyingPenalties, isTrue);

      // Act — hold the penalty button
      notifier.subtractPen(1);

      // Assert — the match never stopped, so the undo still works
      expect(notifier.state.match.hasDisqualifyingPenalties, isFalse);
      expect(notifier.state.match.status, MatchStatus.inProgress);
      expect(notifier.state.suggestedOutcome!.method, isNot(MatchMethod.dq));
    });
  });

  group('the clock and the calendar', () {
    test('a match the clock ended is stamped with the expiry, not the reopen',
        () async {
      // Arrange — a match whose five minutes ran out *yesterday*, opened again
      // today. It ended when regulation time ran out; nobody was there.
      nostr = _FakeNostrService();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final startAt = now - 86400;
      final yesterday = _runningMatch().copyWith(
        duration: 300,
        startAt: startAt,
        f1Pt2: 1,
      );

      // Act
      notifier = MatchControlNotifier(yesterday, nostr);
      await Future<void>.delayed(Duration.zero);

      // Assert — stamping "now" would put the end of the match a day after it
      // actually ended, and every consumer would believe it
      expect(notifier.state.match.status, MatchStatus.finished);
      expect(notifier.state.match.endedAt, startAt + 300);
    });

    test('a referee ending a match in front of them stamps now', () {
      // Arrange
      nostr = _FakeNostrService();
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      notifier = MatchControlNotifier(_runningMatch(), nostr);

      // Act
      notifier.finishWith(const MatchOutcome.submissionBy(MatchWinner.f1));

      // Assert
      expect(notifier.state.match.endedAt, greaterThanOrEqualTo(before));
    });
  });

  group('when both fighters are disqualified', () {
    test('the app offers no winner at all', () {
      // Arrange — reachable precisely because a fourth penalty leaves the match
      // running: both fighters can get there.
      nostr = _FakeNostrService();
      notifier = MatchControlNotifier(_runningMatch(), nostr);
      for (var i = 0; i < 4; i++) {
        notifier.scorePen(1);
        notifier.scorePen(2);
      }

      // Assert — the scoreboard names no single offender, and picking one
      // anyway would hand the referee a one-tap result that is arbitrary. That
      // is the worst kind, because it looks decided.
      expect(notifier.state.match.hasDisqualifyingPenalties, isTrue);
      expect(notifier.state.suggestedOutcome, isNull);
    });

    test('the clock will not finish it either', () async {
      // Arrange
      nostr = _FakeNostrService();
      final almostOver = _runningMatch().copyWith(
        duration: 1,
        startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
        f1Pen: 4,
        f2Pen: 4,
      );
      notifier = MatchControlNotifier(almostOver, nostr);

      // Act
      await Future<void>.delayed(const Duration(milliseconds: 1600));

      // Assert
      expect(notifier.state.awaitsOutcome, isTrue);
      expect(notifier.state.match.status, MatchStatus.inProgress);
    });
  });
}
