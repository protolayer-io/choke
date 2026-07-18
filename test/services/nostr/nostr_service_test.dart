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
  });
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
