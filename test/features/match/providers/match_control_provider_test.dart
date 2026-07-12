import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/providers/match_control_provider.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';

/// Fake NostrService that skips relay publishing entirely
class _FakeNostrService extends NostrService {
  _FakeNostrService() : super(KeyManager());

  int publishCount = 0;

  @override
  Future<void> publishAddressableEvent({
    required String dTag,
    required String content,
    List<List<String>> additionalTags = const [],
  }) async {
    publishCount++;
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
}
