import 'dart:async';

import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/services/nostr/relay/nostr_relay_backend.dart';

/// Stand-ins for tests that construct a [NostrService] but never publish
/// through it — screen tests, provider tests, the timestamp tests.
///
/// They exist because `NostrService` now *requires* its crypto and its
/// transport. That is deliberate: the defaults it used to carry pointed at the
/// legacy implementations, and once those were deleted a default could only
/// have been a lie. A test that does not care says so, here, out loud.
class FakeNostrCrypto implements NostrCrypto {
  @override
  String generatePrivateKey() => 'f' * 64;

  @override
  String getPublicKey(String privateKeyHex) => 'e' * 64;

  @override
  String npubEncode(String publicKeyHex) => 'npub1fake';

  @override
  String nsecEncode(String privateKeyHex) => 'nsec1fake';

  @override
  String? nsecDecode(String nsec) => nsec == 'nsec1fake' ? 'f' * 64 : null;

  @override
  NostrEvent finishEvent(UnsignedNostrEvent event, String privateKeyHex) {
    return NostrEvent(
      id: 'a' * 64,
      pubkey: event.pubkey,
      createdAt: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: 'b' * 128,
    );
  }

  @override
  bool verifyEvent(NostrEvent event) => true;
}

/// A transport that is wired up and connected to nothing.
class FakeRelayBackend implements NostrRelayBackend {
  final _events = StreamController<NostrEvent>.broadcast();
  final _connected = StreamController<String>.broadcast();

  @override
  Stream<NostrEvent> get events => _events.stream;

  @override
  Stream<String> get onRelayConnected => _connected.stream;

  @override
  List<String> get relayUrls => const [];

  @override
  List<String> get connectedRelays => const [];

  @override
  Future<void> addRelay(String url) async {}

  @override
  void removeRelay(String url) {}

  @override
  Future<void> reconnectAll() async {}

  @override
  void subscribe(String subscriptionId, Filter filter) {}

  @override
  void unsubscribe(String subscriptionId) {}

  @override
  Future<bool> publish(String relayUrl, NostrEvent event) async => true;

  @override
  bool isAwaitingOk(String relayUrl, String eventId) => false;

  @override
  void disconnect() {}

  @override
  void dispose() {
    _events.close();
    _connected.close();
  }
}
