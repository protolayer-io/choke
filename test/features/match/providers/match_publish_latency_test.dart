import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/providers/match_control_provider.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';

import '../../../support/nostr_fakes.dart';

/// What the referee's taps are supposed to do: reach the relay the moment the
/// button is pressed.
///
/// These go through the real [NostrService] rather than a stub of it, because
/// the delay these guard against lives *between* the notifier and the relay:
/// the outbox sends one state at a time, so however long a publish takes to
/// resolve is how long the next tap waits. A publish that resolves only when
/// the slowest relay answers puts every later score behind it — a penalty
/// landing on the remote scoreboard seconds after it was awarded.
class _FixedKeyManager extends KeyManager {
  _FixedKeyManager() : super(crypto: FakeNostrCrypto());

  @override
  Future<String?> getPublicKeyHex() async => 'e' * 64;

  @override
  Future<String?> getPrivateKeyHex() async => 'f' * 64;
}

/// Signs each event with its own id, so publishes can be told apart.
class _CountingCrypto extends FakeNostrCrypto {
  int _n = 0;

  @override
  NostrEvent finishEvent(UnsignedNostrEvent event, String privateKeyHex) {
    _n++;
    return NostrEvent(
      id: '$_n'.padLeft(64, '0'),
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: 'b' * 128,
    );
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

/// Wait for [check] to hold, or give up. Polling rather than a fixed sleep, so
/// a passing run costs milliseconds instead of the whole timeout.
Future<void> eventually(
  bool Function() check, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!check() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

void main() {
  const fast = 'wss://fast';
  const silent = 'wss://silent';

  late RecordingRelayBackend backend;
  late NostrService service;
  late MatchControlNotifier notifier;
  late Completer<bool> silentVerdict;

  /// Every event the fast relay was handed, in order.
  late List<NostrEvent> sentToFast;

  setUp(() {
    sentToFast = [];
    backend = RecordingRelayBackend()
      ..configuredRelays = [fast, silent]
      ..connected = [fast, silent];

    // The relay everyone is watching answers at once. The other takes the
    // event and never says anything — a relay under load, or one that does not
    // acknowledge this kind. nostr-sdk gives it a full 10 seconds before it
    // calls the publish failed, and that wait is the whole problem.
    silentVerdict = Completer<bool>();
    backend.onPublish = (url, event) {
      if (url != fast) return silentVerdict.future;
      sentToFast.add(event);
      return Future<bool>.value(true);
    };

    service = NostrService(
      _FixedKeyManager(),
      crypto: _CountingCrypto(),
      backend: backend,
      // Long enough that the background sweep never fires mid-test: what is
      // under test is the publish on the tap, not the retry that follows it.
      resendInterval: const Duration(minutes: 5),
    );
    notifier = MatchControlNotifier(_runningMatch(), service);
  });

  tearDown(() async {
    if (!silentVerdict.isCompleted) silentVerdict.complete(false);
    notifier.dispose();
    service.dispose();
    await Future<void>.delayed(Duration.zero);
  });

  group('every tap goes out when it is tapped', () {
    test('a penalty reaches the relay on the press', () async {
      // Act
      final stopwatch = Stopwatch()..start();
      notifier.scorePen(1);
      await eventually(() => sentToFast.isNotEmpty);
      stopwatch.stop();

      // Assert — the threshold is loose on purpose: what fails here is a
      // design that batches or defers the tap, not a few ms of event loop
      expect(sentToFast, hasLength(1));
      expect(Match.fromJsonString(sentToFast.single.content).f1Pen, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    });

    test('a second penalty is not held behind a silent relay', () async {
      // Arrange — the first tap's publish is still outstanding at the silent
      // relay when the second tap lands
      notifier.scorePen(1);
      await eventually(() => sentToFast.isNotEmpty);
      expect(silentVerdict.isCompleted, isFalse,
          reason: 'the silent relay must still be outstanding');

      // Act — the referee awards a second penalty a moment later
      final stopwatch = Stopwatch()..start();
      notifier.scorePen(2);
      await eventually(() => sentToFast.length >= 2);
      stopwatch.stop();

      // Assert — the second score went out on its own tap
      expect(sentToFast, hasLength(2));
      expect(Match.fromJsonString(sentToFast.last.content).f2Pen, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    });

    test('a burst of taps still leaves the relay holding the final score',
        () async {
      // Act — five penalties faster than any relay answers
      final stopwatch = Stopwatch()..start();
      for (var i = 0; i < 5; i++) {
        notifier.scorePen(1);
      }

      // Assert — coalescing the states in between is fine, the event is
      // addressable and only the newest matters. What must arrive, quickly, is
      // the final score.
      await eventually(() =>
          sentToFast.isNotEmpty &&
          Match.fromJsonString(sentToFast.last.content).f1Pen == 5);
      stopwatch.stop();

      expect(Match.fromJsonString(sentToFast.last.content).f1Pen, 5);
      expect(notifier.state.match.f1Pen, 5);
      // The whole burst clears in the same budget a single tap gets: nothing
      // here may wait on the silent relay.
      expect(stopwatch.elapsed, lessThan(const Duration(milliseconds: 500)));
    });
  });
}
