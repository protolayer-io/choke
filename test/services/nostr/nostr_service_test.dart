import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';

/// In-memory WebSocket standing in for a relay: the test scripts what the
/// "relay" sends back through [incoming] and inspects what the client wrote
/// through [sent].
class _FakeWebSocketChannel implements WebSocketChannel {
  final incoming = StreamController<dynamic>();
  final sent = <String>[];
  late final _FakeWebSocketSink _sink = _FakeWebSocketSink(this);

  @override
  Stream<dynamic> get stream => incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeWebSocketSink implements WebSocketSink {
  final _FakeWebSocketChannel _channel;
  _FakeWebSocketSink(this._channel);

  @override
  void add(dynamic message) => _channel.sent.add(message as String);

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

NostrEvent _event(String id) {
  return NostrEvent(
    id: id,
    pubkey: 'f' * 64,
    createdAt: 1,
    kind: 31415,
    tags: const [
      ['d', 'abcd']
    ],
    content: '{}',
    sig: 'f' * 128,
  );
}

void main() {
  group('nextCreatedAt', () {
    test('is strictly increasing for the same match, even within one second',
        () {
      // Arrange — relays keep a single addressable event per match and drop
      // same-second updates, so rapid publishes must never share a timestamp
      final service = NostrService(KeyManager());

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
      final service = NostrService(KeyManager());
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
      final service = NostrService(KeyManager());
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

  group('RelayConnection zombie detection', () {
    late _FakeWebSocketChannel channel;
    late RelayConnection relay;

    setUp(() async {
      channel = _FakeWebSocketChannel();
      relay = RelayConnection(
        'wss://relay.test',
        channelFactory: (_) => channel,
        okTimeout: const Duration(milliseconds: 100),
      );
      await relay.connect();
    });

    tearDown(() => relay.dispose());

    test('publish succeeds and stays connected when the relay sends OK',
        () async {
      // Arrange
      final event = _event('e1');

      // Act — the relay confirms the event
      final publishing = relay.publish(event);
      channel.incoming.add(jsonEncode(['OK', 'e1', true, '']));

      // Assert
      expect(await publishing, isTrue);
      expect(relay.isConnected, isTrue);
      expect(channel.sent, hasLength(1));
    });

    test('publish drops the connection when the relay never answers',
        () async {
      // Arrange — the socket died without a close frame (phone slept,
      // network switched): writes go nowhere and no OK ever arrives
      final event = _event('e1');

      // Act
      await expectLater(
        relay.publish(event),
        throwsA(isA<TimeoutException>()),
      );

      // Assert — the connection must be recycled, not trusted again: a
      // zombie socket that stays "connected" swallows every later publish
      expect(relay.isConnected, isFalse);
    });

    test('reconnectNow tears down the socket and connects a fresh one',
        () async {
      // Arrange — the current socket may be a zombie after app resume
      expect(relay.isConnected, isTrue);

      // Act
      await relay.reconnectNow();

      // Assert
      expect(relay.isConnected, isTrue);
    });
  });

  group('per-relay convergence', () {
    test('a relay that missed an event receives it after reconnecting',
        () async {
      // Arrange — two relays; B's socket is dead and never answers, so the
      // event only lands on A. "One relay accepted" must not mean "done":
      // whoever watches relay B still deserves the latest match state.
      final chanA1 = _FakeWebSocketChannel();
      final chanA2 = _FakeWebSocketChannel();
      final chanB1 = _FakeWebSocketChannel();
      final chanB2 = _FakeWebSocketChannel();
      final channels = {
        'a.test': [chanA1, chanA2],
        'b.test': [chanB1, chanB2],
      };
      final service = NostrService(
        KeyManager(),
        channelFactory: (uri) => channels[uri.host]!.removeAt(0),
        okTimeout: const Duration(milliseconds: 100),
        resendInterval: const Duration(milliseconds: 100),
      );
      await service.addRelay('wss://a.test');
      await service.addRelay('wss://b.test');

      // Act — A confirms, B stays silent (publish still succeeds via A)
      final publishing = service.publishEvent(_event('e1'));
      chanA1.incoming.add(jsonEncode(['OK', 'e1', true, '']));
      await publishing;
      expect(chanB2.sent, isEmpty);

      // B comes back with a fresh socket
      await service.reconnectAll();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — the missed event reaches B without any new user action
      expect(chanB2.sent.where((m) => m.contains('"e1"')), isNotEmpty);
      chanB2.incoming.add(jsonEncode(['OK', 'e1', true, '']));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      service.dispose();
    });

    test('a relay that rejects an event gets it resent until accepted',
        () async {
      // Arrange — B is connected but refuses the event (e.g. rate limiting
      // rapid-fire scoring), while A accepts it
      final chanA = _FakeWebSocketChannel();
      final chanB = _FakeWebSocketChannel();
      final channels = {
        'a.test': [chanA],
        'b.test': [chanB],
      };
      final service = NostrService(
        KeyManager(),
        channelFactory: (uri) => channels[uri.host]!.removeAt(0),
        okTimeout: const Duration(milliseconds: 200),
        resendInterval: const Duration(milliseconds: 100),
      );
      await service.addRelay('wss://a.test');
      await service.addRelay('wss://b.test');

      // Act — first attempt: A accepts, B rejects
      final publishing = service.publishEvent(_event('e1'));
      chanA.incoming.add(jsonEncode(['OK', 'e1', true, '']));
      chanB.incoming.add(
          jsonEncode(['OK', 'e1', false, 'rate-limited: slow down']));
      await publishing;
      expect(chanB.sent, hasLength(1));

      // The resend sweep retries B on its own; this time B accepts
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(chanB.sent, hasLength(2),
          reason: 'rejected relay must be retried');
      chanB.incoming.add(jsonEncode(['OK', 'e1', true, '']));

      // Assert — once accepted everywhere, no more resends
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(chanB.sent, hasLength(2));
      service.dispose();
    });

    test('only the newest state is resent when updates supersede each other',
        () async {
      // Arrange — B misses two updates in a row; on recovery it must get
      // only the latest one (addressable events: old states are noise)
      final chanA = _FakeWebSocketChannel();
      final chanB = _FakeWebSocketChannel();
      final channels = {
        'a.test': [chanA],
        'b.test': [chanB],
      };
      final service = NostrService(
        KeyManager(),
        channelFactory: (uri) => channels[uri.host]!.removeAt(0),
        okTimeout: const Duration(milliseconds: 100),
        resendInterval: const Duration(milliseconds: 100),
      );
      await service.addRelay('wss://a.test');
      await service.addRelay('wss://b.test');

      // Act — two publishes; A accepts both, B rejects both
      final first = service.publishEvent(_event('e1'));
      chanA.incoming.add(jsonEncode(['OK', 'e1', true, '']));
      chanB.incoming.add(jsonEncode(['OK', 'e1', false, 'rate-limited']));
      await first;
      final second = service.publishEvent(_event('e2'));
      chanA.incoming.add(jsonEncode(['OK', 'e2', true, '']));
      chanB.incoming.add(jsonEncode(['OK', 'e2', false, 'rate-limited']));
      await second;
      final sentBefore = chanB.sent.length;

      // The sweep retries B; it accepts now
      await Future<void>.delayed(const Duration(milliseconds: 150));
      final resent = chanB.sent.sublist(sentBefore);
      chanB.incoming.add(jsonEncode(['OK', 'e2', true, '']));
      await Future<void>.delayed(const Duration(milliseconds: 50));

      // Assert — only e2 (the latest state) went out again
      expect(resent, hasLength(1));
      expect(resent.single, contains('"e2"'));
      service.dispose();
    });
  });
}
