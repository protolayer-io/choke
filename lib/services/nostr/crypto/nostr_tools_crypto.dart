import 'package:flutter/foundation.dart';
import 'package:nostr_tools/nostr_tools.dart' as nostr;

import '../nostr_service.dart' show NostrEvent;
import 'nostr_crypto.dart';

/// [NostrCrypto] backed by the `nostr_tools` Dart package.
///
/// This is the only place in the app allowed to import `nostr_tools`. It is
/// the incumbent implementation, kept for one release cycle after the Rust
/// backend takes over — as an instant rollback — and deleted in Phase 8.
/// See docs/specs/nostr-sdk-migration.md.
class NostrToolsCrypto implements NostrCrypto {
  final nostr.KeyApi _keyApi;
  final nostr.EventApi _eventApi;
  final nostr.Nip19 _nip19;

  NostrToolsCrypto()
      : _keyApi = nostr.KeyApi(),
        _eventApi = nostr.EventApi(),
        _nip19 = nostr.Nip19();

  @override
  String generatePrivateKey() => _keyApi.generatePrivateKey();

  @override
  String getPublicKey(String privateKeyHex) =>
      _keyApi.getPublicKey(privateKeyHex);

  @override
  String npubEncode(String publicKeyHex) => _nip19.npubEncode(publicKeyHex);

  @override
  String nsecEncode(String privateKeyHex) => _nip19.nsecEncode(privateKeyHex);

  @override
  String? nsecDecode(String nsec) {
    try {
      final decoded = _nip19.decode(nsec);
      // An npub decodes cleanly too — taking its data as a private key would
      // be a catastrophic confusion, so the type has to match.
      if (decoded['type'] != 'nsec') return null;
      return decoded['data'] as String?;
    } catch (e) {
      debugPrint('NostrToolsCrypto: nsec decode error: $e');
      return null;
    }
  }

  @override
  NostrEvent finishEvent(UnsignedNostrEvent event, String privateKeyHex) {
    final unsigned = nostr.Event(
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      created_at: event.createdAt,
      pubkey: event.pubkey,
    );

    // finishEvent computes both the id and the Schnorr signature.
    final signed = _eventApi.finishEvent(unsigned, privateKeyHex);
    return _fromToolsEvent(signed);
  }

  @override
  bool verifyEvent(NostrEvent event) {
    final toolsEvent = _toToolsEvent(event);

    // `nostr_tools` only checks the signature against the id, never that the
    // id actually describes the event — so on its own it calls an event whose
    // content was rewritten after signing valid. Per NIP-01 the id *is* the
    // hash of the event, so recompute it: an event whose id does not match
    // its own contents is forged, whatever its signature says. The Rust
    // implementation checks both, and the two must agree.
    if (_eventApi.getEventHash(toolsEvent) != event.id) return false;

    return _eventApi.verifySignature(toolsEvent);
  }

  // Translating to and from `nostr_tools`' own event type is this class's
  // private business — it is what keeps the type out of the rest of the app.

  nostr.Event _toToolsEvent(NostrEvent event) {
    return nostr.Event(
      id: event.id,
      pubkey: event.pubkey,
      created_at: event.createdAt,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: event.sig,
    );
  }

  NostrEvent _fromToolsEvent(nostr.Event event) {
    return NostrEvent(
      id: event.id,
      pubkey: event.pubkey,
      createdAt: event.created_at,
      kind: event.kind,
      tags: event.tags,
      content: event.content,
      sig: event.sig,
    );
  }
}
