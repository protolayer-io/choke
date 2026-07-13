import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/crypto/nostr_tools_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/services/nostr/relay/nostr_relay_backend.dart';

import 'fake_relay.dart';

/// The failure drills the transport switch is gated on.
///
/// These are the scenarios that produced the bug this whole thread began with:
/// a referee scoring a match while the relay someone was watching quietly
/// served a stale scoreboard. They were fixed in #78 — and Phase 7 swaps the
/// transport out from under that fix. So rather than trust a human to re-enact
/// them on a phone, they run here: against a real relay, on whichever backend
/// is about to be handed the keys.
///
/// They deliberately go through [NostrService] rather than the backend. The
/// convergence logic is what has to survive, and it only exists at that level.
void runConvergenceDrills(
  String name,
  NostrRelayBackend Function() create, {
  Duration settle = const Duration(milliseconds: 200),
}) {
  group('$name — convergence drills', () {
    late FakeRelay relayA;
    late FakeRelay relayB;
    late NostrService service;

    final crypto = NostrToolsCrypto();
    final privateKey = crypto.generatePrivateKey();
    final publicKey = crypto.getPublicKey(privateKey);

    NostrEvent score(int createdAt, String content) {
      return crypto.finishEvent(
        UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: createdAt,
          kind: 31415,
          tags: const [
            ['d', 'abcd']
          ],
          content: content,
        ),
        privateKey,
      );
    }

    setUp(() async {
      relayA = await FakeRelay.start();
      relayB = await FakeRelay.start();
      service = NostrService(
        KeyManager(),
        backend: create(),
        resendInterval: const Duration(milliseconds: 200),
      );
    });

    tearDown(() async {
      service.dispose();
      await relayA.stop();
      await relayB.stop();
    });

    /// Wait for [check] to hold, or give up. Polling rather than a fixed sleep:
    /// the two transports settle on different schedules, and a sleep long
    /// enough for the slower one would make the suite crawl.
    Future<void> eventually(
      bool Function() check, {
      Duration timeout = const Duration(seconds: 8),
    }) async {
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (check()) return;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      fail('condition never held within $timeout');
    }

    test('a relay that rejects the score is retried until it accepts',
        () async {
      // Arrange — a relay that is up, answering, and saying no. This is what
      // rate limiting looks like when a referee taps three advantages in two
      // seconds, and it is exactly what used to leave that relay stale forever.
      await service.addRelay(relayA.url);
      await Future<void>.delayed(settle);
      relayA.rejectReason = 'rate-limited: slow down';

      // Act — nobody accepted it, so the publish must not claim success
      await expectLater(
        service.publishEvent(score(1700000000, 'f1 leads')),
        throwsA(anything),
      );
      expect(relayA.received, isEmpty);

      // The relay stops rate-limiting
      relayA.rejectReason = null;

      // Assert — the sweep brings it up to date on its own, with no further
      // action from the referee
      await eventually(() => relayA.received.isNotEmpty);
      expect(relayA.received.single['content'], 'f1 leads');
    });

    test('a relay that was down gets the score when it comes back', () async {
      // Arrange — both relays are configured, as they are at app start. B is
      // the one someone is watching, and B is down when the referee scores.
      final portB = relayB.port;
      await relayB.stop();

      await service.addRelay(relayA.url);
      await service.addRelay(relayB.url);
      await Future<void>.delayed(settle);

      // Act — the score lands on A. For the referee this is a success, and it
      // should be: the app must never block on a relay that is not there.
      await service.publishEvent(score(1700000000, 'f1 leads'));
      await eventually(() => relayA.received.isNotEmpty);

      // B comes back on the same address
      relayB = await FakeRelay.start(port: portB);

      // Assert — B is brought up to date on its own. This is the whole of #78:
      // "one relay accepted" is not "done", and the relay that was away is
      // exactly the one whose scoreboard was going stale.
      await eventually(() => relayB.received.isNotEmpty,
          timeout: const Duration(seconds: 20));
      expect(relayB.received.single['content'], 'f1 leads');
    });

    test('a relay that was down receives only the latest score, not the history',
        () async {
      // Arrange — B is down while the referee runs up the score
      final portB = relayB.port;
      await relayB.stop();

      await service.addRelay(relayA.url);
      await service.addRelay(relayB.url);
      await Future<void>.delayed(settle);

      // Act — three scores in quick succession, all landing on A
      await service.publishEvent(score(1700000000, 'f1: 2'));
      await service.publishEvent(score(1700000001, 'f1: 5'));
      await service.publishEvent(score(1700000002, 'f1: 7'));
      await eventually(() => relayA.received.length == 3);

      // B comes back
      relayB = await FakeRelay.start(port: portB);

      // Assert — B gets the final score, once. These events are addressable:
      // an older one is not history, it is noise, and replaying all three would
      // make the relay briefly show a score that is no longer true.
      await eventually(() => relayB.received.isNotEmpty,
          timeout: const Duration(seconds: 20));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(relayB.received, hasLength(1));
      expect(relayB.received.single['content'], 'f1: 7');
    });

    test('with nothing reachable, the score survives until the relay returns',
        () async {
      // Arrange — airplane mode: the app knows its relay, and nothing answers
      final portA = relayA.port;
      await relayA.stop();
      await service.addRelay(relayA.url);
      await Future<void>.delayed(settle);

      // Act — the referee scores anyway. The publish fails, loudly: no relay
      // took it, and pretending otherwise is what got us here.
      await expectLater(
        service.publishEvent(score(1700000000, 'f1 leads')),
        throwsA(anything),
      );

      // The network comes back
      relayA = await FakeRelay.start(port: portA);

      // Assert — the score the referee gave is still pending, and lands without
      // them having to tap anything again
      await eventually(() => relayA.received.isNotEmpty,
          timeout: const Duration(seconds: 20));
      expect(relayA.received.single['content'], 'f1 leads');
    });
  });
}
