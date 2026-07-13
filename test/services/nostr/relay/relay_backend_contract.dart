import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/crypto/rust_nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/services/nostr/relay/nostr_relay_backend.dart';

import 'fake_relay.dart';

/// The behavior every [NostrRelayBackend] must exhibit, written once against
/// the interface and run against a **real relay** on a real socket.
///
/// This is what lets Phase 7 flip the transport without holding its breath. The
/// two backends share no code — one is Dart over `web_socket_channel`, the
/// other Rust over `nostr-sdk` — so the only thing that can prove them
/// interchangeable is subjecting both to the same relay and the same questions.
///
/// The questions are the ones the app's reliability actually rests on:
///
/// - does `publish` tell the truth about what *this* relay said, accept and
///   reject alike? Convergence (I3) is built entirely on that distinction; a
///   backend that reported "sent" as "accepted" would resurrect #78.
/// - does a relay that is up show up as connected, and does one that leaves
///   stop being counted?
/// - do subscribed events arrive, whole?
void runRelayBackendContract(
  String name,
  NostrRelayBackend Function() create, {
  /// The Rust pool is process-wide and needs a beat to settle; the Dart one is
  /// immediate. A knob, rather than sleeps sprinkled through the tests.
  Duration settle = const Duration(milliseconds: 200),
}) {
  group('$name — NostrRelayBackend contract', () {
    late FakeRelay relay;
    late NostrRelayBackend backend;

    // Events are genuinely signed, not stubbed: `nostr-sdk` verifies incoming
    // events and silently drops the ones that do not check out, so a fixture
    // full of 'cccc…' signatures would have looked exactly like a broken event
    // stream. The keys are minted in setUp, not here — RustLib is initialized
    // in setUpAll, and a key made before that would call into a library that
    // does not exist yet.
    const crypto = RustNostrCrypto();
    late String privateKey;
    late String publicKey;

    setUp(() async {
      privateKey = crypto.generatePrivateKey();
      publicKey = crypto.getPublicKey(privateKey);
      relay = await FakeRelay.start();
      backend = create();
    });

    tearDown(() async {
      backend.dispose();
      await relay.stop();
    });

    Future<void> connect() async {
      await backend.addRelay(relay.url);
      await Future<void>.delayed(settle);
    }

    NostrEvent event({int createdAt = 1700000000, String content = 'choke'}) {
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

    group('connecting', () {
      test('a relay that was added is reported as connected', () async {
        // Act
        await connect();

        // Assert
        expect(backend.relayUrls, contains(relay.url));
        expect(backend.connectedRelays, contains(relay.url));
      });

      test('a relay that was never added is not known', () {
        // Assert
        expect(backend.relayUrls, isEmpty);
        expect(backend.connectedRelays, isEmpty);
      });

      test('connecting announces the relay on onRelayConnected', () async {
        // Arrange — this is the app's cue to push state the relay missed
        final announced = <String>[];
        backend.onRelayConnected.listen(announced.add);

        // Act
        await connect();

        // Assert
        expect(announced, contains(relay.url));
      });

      test('a removed relay stops being counted', () async {
        // Arrange
        await connect();

        // Act
        backend.removeRelay(relay.url);
        await Future<void>.delayed(settle);

        // Assert — convergence is measured against relayUrls, so a relay left
        // behind here would make every match wait forever on a ghost
        expect(backend.relayUrls, isNot(contains(relay.url)));
        expect(backend.connectedRelays, isNot(contains(relay.url)));
      });
    });

    group('publishing', () {
      test('reports true when the relay accepts', () async {
        // Arrange
        await connect();

        // Act
        final accepted = await backend.publish(relay.url, event());

        // Assert
        expect(accepted, isTrue);
        expect(relay.received, hasLength(1));
      });

      test('reports false when the relay rejects', () async {
        // Arrange — a relay that is up, answering, and saying no. This is the
        // case that broke production: it must never read as success.
        await connect();
        relay.rejectReason = 'rate-limited: slow down';

        // Act
        final accepted = await backend.publish(relay.url, event());

        // Assert
        expect(accepted, isFalse);
        expect(relay.received, isEmpty);
      });

      test('sends the event the caller gave it, unchanged', () async {
        // Arrange
        await connect();
        final sent = event(content: '{"f1_name":"José 🥋","f2_pt2":3}');

        // Act
        await backend.publish(relay.url, sent);

        // Assert — the id is a hash of these fields; a transport that mangled
        // any of them would be publishing events no relay would accept
        final received = relay.received.single;
        expect(received['id'], sent.id);
        expect(received['content'], sent.content);
        expect(received['created_at'], sent.createdAt);
        expect(received['kind'], sent.kind);
        expect(received['tags'], sent.tags);
        expect(received['sig'], sent.sig);
      });

      test('an event is not in flight once its publish has returned', () async {
        // Arrange — the caller checks this before resending, so a stale entry
        // would stop a straggling relay from ever being brought up to date
        await connect();
        final published = event();

        // Act
        await backend.publish(relay.url, published);

        // Assert
        expect(backend.isAwaitingOk(relay.url, published.id), isFalse);
      });
    });

    group('subscribing', () {
      test('events the relay sends arrive on the event stream', () async {
        // Arrange
        await connect();
        final received = <NostrEvent>[];
        backend.events.listen(received.add);

        backend.subscribe('sub', Filter(kinds: [31415]));
        await Future<void>.delayed(settle);

        // Act — someone else scores a match, and the relay pushes it out
        relay.broadcast(
          'sub',
          event(createdAt: 1700000001, content: 'from a relay').toJson(),
        );
        await Future<void>.delayed(settle);

        // Assert
        expect(received.map((e) => e.content), contains('from a relay'));
      });

      test('an event arrives with every field intact', () async {
        // Arrange
        await connect();
        final received = <NostrEvent>[];
        backend.events.listen(received.add);
        backend.subscribe('sub', Filter(kinds: [31415]));
        await Future<void>.delayed(settle);

        final sent = event(createdAt: 1700000002, content: 'Gonçalves 🥋');

        // Act
        relay.broadcast('sub', sent.toJson());
        await Future<void>.delayed(settle);

        // Assert — a score arriving with its tags or timestamp mangled is a
        // match the app renders wrong
        final arrived = received.firstWhere((e) => e.id == sent.id);
        expect(arrived.content, sent.content);
        expect(arrived.createdAt, sent.createdAt);
        expect(arrived.kind, sent.kind);
        expect(arrived.tags, sent.tags);
        expect(arrived.pubkey, sent.pubkey);
      });
    });
  });
}
