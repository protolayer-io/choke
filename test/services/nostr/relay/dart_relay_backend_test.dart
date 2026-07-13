import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/services/nostr/relay/dart_relay_backend.dart';


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


/// The transport, tested on its own now that it lives behind an interface.
///
/// These are the regressions from #78: a relay that stops answering is dead,
/// not slow, and a socket being replaced must not take its replacement down
/// with it.
void main() {
  group('RelayConnection zombie detection', () {
    // Every connect() gets a brand-new socket, as it does in production —
    // reusing one fake would let a reconnect silently listen to the old
    // (single-subscription) stream and never exercise the reconnect path.
    late List<_FakeWebSocketChannel> channels;
    late RelayConnection relay;

    _FakeWebSocketChannel current() => channels.last;

    setUp(() async {
      channels = [];
      relay = RelayConnection(
        'wss://relay.test',
        channelFactory: (_) {
          final channel = _FakeWebSocketChannel();
          channels.add(channel);
          return channel;
        },
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
      current().incoming.add(jsonEncode(['OK', 'e1', true, '']));

      // Assert
      expect(await publishing, isTrue);
      expect(relay.isConnected, isTrue);
      expect(current().sent, hasLength(1));
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
      final old = current();

      // Act
      await relay.reconnectNow();

      // Assert — a genuinely new socket, and the connection is live on it
      expect(channels, hasLength(2));
      expect(current(), isNot(same(old)));
      expect(relay.isConnected, isTrue);
    });

    test('a late close from the old socket does not kill the new connection',
        () async {
      // Arrange — the OS closes the backgrounded socket, but the close
      // notification only lands after the app already reconnected
      final old = current();
      await relay.reconnectNow();
      expect(relay.isConnected, isTrue);

      // Act — the stale socket finally reports it is done
      await old.incoming.close();
      await Future<void>.delayed(Duration.zero);

      // Assert — the fresh socket must survive its predecessor's funeral
      expect(relay.isConnected, isTrue);
    });

    test('reconnecting frees a publish that was in flight on the old socket',
        () async {
      // Arrange — a publish is waiting for an OK the dead socket can never
      // deliver when the app resumes and swaps the connection
      final event = _event('e1');
      final publishing = relay.publish(event);
      expect(relay.isAwaitingOk('e1'), isTrue);

      // Act
      await relay.reconnectNow();
      await expectLater(publishing, throwsA(isA<Exception>()));

      // Assert — the event is no longer considered in flight, so the
      // resend to the fresh socket is not suppressed as a duplicate
      expect(relay.isAwaitingOk('e1'), isFalse);
      expect(relay.isConnected, isTrue);
    });
  });

}
