import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';

import '../../support/nostr_fakes.dart';

void main() {
  group('nextCreatedAt', () {
    test('is strictly increasing for the same match, even within one second',
        () {
      // Arrange — relays keep a single addressable event per match and drop
      // same-second updates, so rapid publishes must never share a timestamp
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: FakeRelayBackend(),
      );

      // Act — three "publishes" back to back, all within the same second
      final first = service.nextCreatedAt('abcd');
      final second = service.nextCreatedAt('abcd');
      final third = service.nextCreatedAt('abcd');

      // Assert
      expect(second, greaterThan(first));
      expect(third, greaterThan(second));
    });

    test('starts from the wall clock', () {
      // Arrange
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: FakeRelayBackend(),
      );
      final before = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Act
      final createdAt = service.nextCreatedAt('abcd');

      // Assert
      final after = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      expect(createdAt, greaterThanOrEqualTo(before));
      expect(createdAt, lessThanOrEqualTo(after + 1));
    });

    test('tracks each match independently', () {
      // Arrange — pushing one match's clock forward must not skew another's
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: FakeRelayBackend(),
      );
      for (var i = 0; i < 5; i++) {
        service.nextCreatedAt('aaaa');
      }
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Act
      final other = service.nextCreatedAt('bbbb');

      // Assert — the fresh match starts at the wall clock, not at aaaa's +5
      expect(other, lessThanOrEqualTo(now + 1));
    });
  });

  group('publishEvent', () {
    test('resolves on the first ack instead of waiting for the slowest relay',
        () async {
      // Arrange — one relay acks immediately, the other never answers. The
      // scoreboard's publish queue is serialized behind this future, so
      // waiting for the straggler would delay the next scoring action.
      final backend = _OneFastOneStuckBackend();
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: backend,
      );
      final event = NostrEvent(
        id: 'e1',
        pubkey: 'pk',
        createdAt: 1,
        kind: 31415,
        tags: const [],
        content: '{}',
        sig: 'sig',
      );

      // Act + Assert — must complete promptly; if it waits on the stuck
      // relay it times out and the regression is caught.
      await service
          .publishEvent(event)
          .timeout(const Duration(seconds: 5));
      expect(backend.fastAsked, isTrue);
      expect(backend.stuckAsked, isTrue);
    });

    test('a relay that never answers cannot hang the publish queue', () async {
      // Arrange — every relay stays silent, which is exactly what a socket
      // that died behind a NAT looks like. Before publishTimeout existed this
      // await hung forever, wedging the scoreboard's serialized publish queue
      // (reconnects could not unwedge it: _drainOutbox early-returns while a
      // send is in flight).
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: _AllStuckBackend(),
        publishTimeout: const Duration(milliseconds: 100),
      );
      final event = NostrEvent(
        id: 'e2',
        pubkey: 'pk',
        createdAt: 1,
        kind: 31415,
        tags: const [],
        content: '{}',
        sig: 'sig',
      );

      // Act + Assert — must fail promptly instead of hanging forever.
      await expectLater(
        service.publishEvent(event).timeout(const Duration(seconds: 5)),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('convergence after the first ack', () {
    test(
        'a rejected-then-accepting relay still gets the latest event even with '
        'a silent relay in the set', () async {
      // Arrange — A acks immediately (satisfies the caller, so publishEvent
      // returns), B stays silent forever, C rejects its first frame then
      // accepts. Convergence must not stall: B must not wedge the sequential
      // resend sweep, and C must end up holding the event.
      final backend = _AbcBackend();
      final service = NostrService(
        KeyManager(crypto: FakeNostrCrypto()),
        crypto: FakeNostrCrypto(),
        backend: backend,
        publishTimeout: const Duration(milliseconds: 60),
        resendInterval: const Duration(milliseconds: 60),
      );
      final event = NostrEvent(
        id: 'e-abc',
        pubkey: 'pk',
        createdAt: 1,
        kind: 31415,
        tags: const [
          ['d', 'match-1'],
        ],
        content: '{}',
        sig: 'sig',
      );

      // Act — returns on A's ack; the rest converges in the background.
      await service.publishEvent(event).timeout(const Duration(seconds: 5));

      // Assert — give the resend sweep time to retry C past its first rejection.
      // If B (silent) wedged the sweep, C would never be retried and this fails.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(
        backend.acceptedBy('wss://c'),
        contains('e-abc'),
        reason: 'C must eventually receive the latest event',
      );

      service.dispose();
    });
  });
}

/// Every relay accepts the connection but never delivers a verdict.
class _AllStuckBackend extends FakeRelayBackend {
  @override
  List<String> get connectedRelays => const ['wss://stuck.example'];

  @override
  Future<bool> publish(String relayUrl, NostrEvent event) =>
      Completer<bool>().future;
}

/// Two connected relays: `fast` acks instantly, `stuck` never answers.
class _OneFastOneStuckBackend extends FakeRelayBackend {
  bool fastAsked = false;
  bool stuckAsked = false;

  @override
  List<String> get connectedRelays =>
      const ['wss://fast.example', 'wss://stuck.example'];

  @override
  Future<bool> publish(String relayUrl, NostrEvent event) {
    if (relayUrl == 'wss://fast.example') {
      fastAsked = true;
      return Future.value(true);
    }
    stuckAsked = true;
    // Parked forever — a relay that connects but never sends its verdict.
    return Completer<bool>().future;
  }
}

/// A/B/C for the convergence drill: `a` acks immediately, `b` never answers,
/// `c` rejects the first frame for an event then accepts every later one.
/// Records which event ids each relay accepted.
class _AbcBackend extends FakeRelayBackend {
  static const _relays = ['wss://a', 'wss://b', 'wss://c'];
  final Map<String, List<String>> _accepted = {};
  final Set<String> _cSeen = {};

  List<String> acceptedBy(String url) => _accepted[url] ?? const [];

  @override
  List<String> get relayUrls => _relays;

  @override
  List<String> get connectedRelays => _relays;

  @override
  Future<bool> publish(String relayUrl, NostrEvent event) {
    if (relayUrl == 'wss://a') return _accept(relayUrl, event);
    if (relayUrl == 'wss://b') {
      // Silent forever — connected, never delivers a verdict.
      return Completer<bool>().future;
    }
    // C: reject the first attempt for this event, accept subsequent ones.
    if (_cSeen.add(event.id)) return Future<bool>.value(false);
    return _accept(relayUrl, event);
  }

  Future<bool> _accept(String url, NostrEvent event) {
    (_accepted[url] ??= <String>[]).add(event.id);
    return Future<bool>.value(true);
  }
}
