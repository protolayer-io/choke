import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../key_management/key_manager.dart';
import 'crypto/nostr_crypto.dart';
import 'relay/nostr_relay_backend.dart';

/// A signed Nostr event.
///
/// Deliberately free of any crypto library's types: translating to and from
/// those is [NostrCrypto]'s business, which is what lets the backend change
/// without the rest of the app noticing.
class NostrEvent {
  final String id;
  final String pubkey;
  final int createdAt;
  final int kind;
  final List<List<String>> tags;
  final String content;
  final String sig;

  NostrEvent({
    required this.id,
    required this.pubkey,
    required this.createdAt,
    required this.kind,
    required this.tags,
    required this.content,
    required this.sig,
  });

  factory NostrEvent.fromJson(Map<String, dynamic> json) {
    return NostrEvent(
      id: json['id'] as String,
      pubkey: json['pubkey'] as String,
      createdAt: json['created_at'] as int,
      kind: json['kind'] as int,
      tags: (json['tags'] as List<dynamic>)
          .map((t) => (t as List<dynamic>).map((e) => e as String).toList())
          .toList(),
      content: json['content'] as String,
      sig: json['sig'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'pubkey': pubkey,
      'created_at': createdAt,
      'kind': kind,
      'tags': tags,
      'content': content,
      'sig': sig,
    };
  }
}

/// Publishing matches to Nostr, reliably.
///
/// The transport lives behind [NostrRelayBackend]. What stays here is
/// everything that makes publishing *trustworthy*, and it stays here on
/// purpose — each piece was bought with a real bug:
///
/// - **Convergence** (I3): a publish succeeds as soon as one relay accepts, so
///   the referee is never left waiting. But relays that were down, silent, or
///   that rejected the event keep being resent the latest state until every
///   configured relay has it. "One relay accepted" used to be treated as
///   "done", which left the relay someone was actually watching showing a
///   stale scoreboard (#78).
/// - **Monotonic `created_at`** (I1): relays keep one event per
///   (kind, pubkey, d-tag) and, per NIP-01, a replacement needs a strictly
///   newer timestamp — on a tie the *old* event wins. Two scores in the same
///   second would otherwise leave the relay holding the earlier one.
/// - **Supersession**: only the newest state per match is ever resent. These
///   events are addressable; an older one is not history, it is noise.
///
/// None of that belongs to a transport, which is why swapping the transport
/// (Phase 6) cannot quietly undo it. See docs/specs/nostr-sdk-migration.md.
class NostrService {
  static const int _maxCachedEvents = 1000; // Max addressable events to cache

  static const List<String> _defaultRelays = [
    'wss://relay.mostro.network',
    'wss://nos.lol',
  ];

  final KeyManager _keyManager;
  final NostrRelayBackend _backend;

  /// Signs and verifies the events this service publishes. Injected so the
  /// crypto backend can be swapped without touching the relay layer.
  final NostrCrypto _crypto;

  final _eventController = StreamController<NostrEvent>.broadcast();
  final Map<String, NostrEvent> _addressableEvents = {};
  final Map<String, int> _lastCreatedAt = {};

  StreamSubscription<NostrEvent>? _backendEvents;
  StreamSubscription<String>? _backendConnections;

  /// Latest signed event per d-tag that some relay has not accepted yet, and
  /// the relay urls that already did. "One relay accepted" is enough for the
  /// caller, but every configured relay must converge to the latest state —
  /// stragglers are resent on reconnect and by [_resendTimer].
  final Map<String, NostrEvent> _pendingLatest = {};
  final Map<String, Set<String>> _pendingAcks = {};
  Timer? _resendTimer;

  /// Set by [dispose] before any resource is released. The publish attempts
  /// spawned by [publishEvent] are unawaited and may still be running when the
  /// caller goes away; this stops their completion from scheduling a resend
  /// timer or touching a torn-down backend.
  bool _disposed = false;

  /// (relayUrl, eventId) pairs this service is currently publishing. A resend
  /// consults this instead of the backend's [NostrRelayBackend.isAwaitingOk] to
  /// avoid racing an in-flight frame — the crucial difference being that this
  /// clears the moment our own [publishTimeout] fires, so a relay that went
  /// silent becomes eligible for a resend again rather than a timed-out send
  /// suppressing every future retry.
  final Set<String> _inFlightPublishes = {};

  static String _inFlightKey(String url, String eventId) => '$url $eventId';

  /// How often relays that are connected but still missing the latest event
  /// (because they rejected it) are retried.
  final Duration resendInterval;

  /// How long a single relay gets to deliver its verdict before the attempt
  /// counts as failed. A socket can die silently (NAT drop while the mat is
  /// quiet) and never answer; without a cap that await hangs, and the
  /// scoreboard's serialized publish queue wedges behind it.
  final Duration publishTimeout;

  NostrService(
    this._keyManager, {
    required NostrCrypto crypto,
    required NostrRelayBackend backend,
    this.resendInterval = const Duration(seconds: 5),
    this.publishTimeout = const Duration(seconds: 5),
  })  : _crypto = crypto,
        _backend = backend {
    _backendEvents = _backend.events.listen(_handleIncomingEvent);
    _backendConnections = _backend.onRelayConnected.listen((url) {
      // A relay that just came back may have missed events while it was away —
      // bring it up to date now, rather than on the referee's next score.
      _resendPendingTo(url);
    });
  }

  /// Every event from every relay that survived filtering: expired ones
  /// (NIP-40) and ones superseded by a newer state for the same match are
  /// dropped before they get here.
  Stream<NostrEvent> get eventStream => _eventController.stream;

  /// Fires with the relay URL each time a relay (re)connects. Publishers
  /// holding unconfirmed state listen to this to retry immediately instead
  /// of waiting out a backoff against a relay that just came back.
  Stream<String> get onRelayConnected => _backend.onRelayConnected;

  /// Connect to configured relays on app start
  Future<void> initialize({List<String>? relayUrls}) async {
    for (final url in relayUrls ?? _defaultRelays) {
      await addRelay(url);
    }
  }

  /// Add a custom relay
  Future<void> addRelay(String url) => _backend.addRelay(url);

  /// Remove a relay
  void removeRelay(String url) => _backend.removeRelay(url);

  /// Recycle every relay connection with a fresh socket.
  ///
  /// Meant for app resume: the OS kills sockets in the background without a
  /// close frame, so connections can look open while dropping every event.
  Future<void> reconnectAll() => _backend.reconnectAll();

  /// Subscribe to kind 31415 events for the current user
  Future<void> subscribeToUserEvents() async {
    final publicKey = await _keyManager.getPublicKeyHex();
    if (publicKey == null) {
      throw Exception('No public key available');
    }

    _backend.subscribe(
      'user_events',
      Filter(kinds: [31415], authors: [publicKey]),
    );
  }

  /// Subscribe to kind 31415 events from a specific author
  void subscribeToAuthor(String authorPubkey, {String? subscriptionId}) {
    _backend.subscribe(
      subscriptionId ?? 'author_$authorPubkey',
      Filter(kinds: [31415], authors: [authorPubkey]),
    );
  }

  /// Unsubscribe from a subscription
  void unsubscribe(String subscriptionId) =>
      _backend.unsubscribe(subscriptionId);

  /// Handle incoming events with addressable event logic
  void _handleIncomingEvent(NostrEvent event) {
    // Check for NIP-40 expiration
    final expirationTag = event.tags.firstWhere(
      (tag) => tag.isNotEmpty && tag[0] == 'expiration',
      orElse: () => [],
    );
    if (expirationTag.isNotEmpty && expirationTag.length > 1) {
      final expiration = int.tryParse(expirationTag[1]);
      if (expiration != null &&
          expiration < DateTime.now().millisecondsSinceEpoch ~/ 1000) {
        debugPrint('NostrService: Ignoring expired event ${event.id}');
        return;
      }
    }

    // Addressable event replacement logic (kind, pubkey, d-tag)
    if (event.kind == 31415) {
      final dTag = event.tags.firstWhere(
        (tag) => tag.isNotEmpty && tag[0] == 'd',
        orElse: () => [],
      );
      if (dTag.isNotEmpty && dTag.length > 1) {
        final addressKey = '${event.kind}:${event.pubkey}:${dTag[1]}';

        // Check if we have a newer version
        final existing = _addressableEvents[addressKey];
        if (existing != null && existing.createdAt >= event.createdAt) {
          debugPrint('NostrService: Ignoring older event $addressKey');
          return;
        }

        _addressableEvents[addressKey] = event;

        // Evict oldest entries if cache exceeds limit
        if (_addressableEvents.length > _maxCachedEvents) {
          final oldestKey = _addressableEvents.keys.first;
          _addressableEvents.remove(oldestKey);
          debugPrint('NostrService: Evicted oldest event from cache');
        }
      }
    }

    _eventController.add(event);
  }

  /// Publish a signed event to all connected relays, waiting for each relay's
  /// verdict.
  ///
  /// Succeeds when at least one relay accepts, but keeps working after
  /// returning: relays that were down, timed out, or rejected the event are
  /// resent the latest state per d-tag until every configured relay has it.
  Future<void> publishEvent(NostrEvent event) async {
    final dTag = _dTagOf(event);
    if (dTag != null) {
      // This event supersedes whatever was pending for the match: relays that
      // missed older states only ever need the newest one.
      _pendingLatest[dTag] = event;
      _pendingAcks[dTag] = <String>{};
    }

    final connected = _backend.connectedRelays;

    debugPrint(
        'NostrService: publishing event ${event.id} (kind ${event.kind}, content ${event.content.length} chars) to ${connected.length} relays');

    if (connected.isEmpty) {
      // The pending state stays registered: the reconnect listener delivers it
      // as soon as any relay comes back.
      throw Exception('No connected relays');
    }

    // Await the FIRST acceptance, not the slowest relay: one ack is enough to
    // succeed (per this method's contract), and the scoreboard's publish queue
    // is serialized behind this future — gating it on every relay's verdict
    // holds up the next scoring action for as long as the slowest relay takes.
    // Stragglers keep working in the background: their acks still land in
    // _markAccepted, and the resend sweep covers whatever they missed.
    final firstAck = Completer<void>();
    var pending = connected.length;
    var successCount = 0;

    for (final url in connected) {
      final inFlightKey = _inFlightKey(url, event.id);
      _inFlightPublishes.add(inFlightKey);
      unawaited(() async {
        var accepted = false;
        try {
          accepted = await _backend.publish(url, event).timeout(publishTimeout);
          debugPrint('NostrService: [$url] accepted=$accepted');
        } on TimeoutException {
          // Never heard from it — dead socket or a relay that went silent.
          // Counts as a failure; the resend sweep converges it later.
          debugPrint(
              'NostrService: [$url] no verdict within '
              '${publishTimeout.inSeconds}s');
        } catch (e) {
          debugPrint('NostrService: [$url] publish error: $e');
        } finally {
          _inFlightPublishes.remove(inFlightKey);
        }
        if (accepted && !_disposed) _markAccepted(dTag, event, url);
        if (accepted) {
          successCount++;
          if (!firstAck.isCompleted) firstAck.complete();
        }
        pending--;
        if (pending == 0) {
          debugPrint(
              'NostrService: published to $successCount/${connected.length} relays');
          _scheduleResendSweep();
          if (!firstAck.isCompleted) {
            firstAck.completeError(Exception('Event rejected by all relays'));
          }
        }
      }());
    }

    await firstAck.future;
  }

  static String? _dTagOf(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'd') return tag[1];
    }
    return null;
  }

  /// Record that [url] accepted [event]; forget the d-tag once every configured
  /// relay has the latest state.
  void _markAccepted(String? dTag, NostrEvent event, String url) {
    if (dTag == null) return;
    // A newer state may have superseded this event mid-flight; an ack for the
    // old one says nothing about the state the relays must converge to.
    if (!identical(_pendingLatest[dTag], event)) return;
    final acked = _pendingAcks[dTag];
    if (acked == null) return;
    acked.add(url);
    if (_backend.relayUrls.every(acked.contains)) {
      _pendingLatest.remove(dTag);
      _pendingAcks.remove(dTag);
    }
  }

  /// Send every pending latest event this relay has not accepted yet.
  Future<void> _resendPendingTo(String url) async {
    if (_disposed) return;
    for (final dTag in _pendingLatest.keys.toList()) {
      final event = _pendingLatest[dTag];
      if (event == null) continue;
      final acked = _pendingAcks[dTag];
      if (acked == null || acked.contains(url)) continue;
      // A publish of this exact event to this relay is already in flight from
      // us — don't race it with a duplicate frame. This clears when our
      // publishTimeout fires, so unlike the backend's isAwaitingOk a relay that
      // fell silent is retried on the next sweep instead of being suppressed.
      final inFlightKey = _inFlightKey(url, event.id);
      if (_inFlightPublishes.contains(inFlightKey)) continue;
      _inFlightPublishes.add(inFlightKey);
      try {
        // Same cap as the initial publish: relays are resent sequentially, so
        // one connected-but-silent socket would otherwise wedge the sweep and
        // starve every relay after it (the exact bug the first-ack path relies
        // on this sweep to cover).
        final accepted =
            await _backend.publish(url, event).timeout(publishTimeout);
        debugPrint(
            'NostrService: resent ${event.id} to $url, accepted=$accepted');
        if (accepted && !_disposed) _markAccepted(dTag, event, url);
      } on TimeoutException {
        debugPrint('NostrService: resend to $url timed out');
      } catch (e) {
        debugPrint('NostrService: resend to $url failed: $e');
      } finally {
        _inFlightPublishes.remove(inFlightKey);
      }
    }
    _scheduleResendSweep();
  }

  /// While any relay is missing the latest state, keep a slow retry loop alive
  /// for relays that are connected but rejected it (rate limits and the like).
  /// Disconnected relays are handled by the reconnect listener instead.
  void _scheduleResendSweep() {
    if (_disposed || _pendingLatest.isEmpty) return;
    _resendTimer ??= Timer(resendInterval, () async {
      _resendTimer = null;
      if (_disposed) return;
      for (final url in _backend.connectedRelays) {
        await _resendPendingTo(url);
      }
      _scheduleResendSweep();
    });
  }

  /// Create and publish a kind 31415 addressable event
  Future<void> publishAddressableEvent({
    required String dTag,
    required String content,
    List<List<String>> additionalTags = const [],
  }) async {
    final privateKey = await _keyManager.getPrivateKeyHex();
    final publicKey = await _keyManager.getPublicKeyHex();

    if (privateKey == null || publicKey == null) {
      throw Exception('Keys not available');
    }

    final tags = [
      ['d', dTag],
      ...additionalTags,
    ];

    final createdAt = nextCreatedAt(dTag);

    // Sign the event: this computes both its id and its signature.
    final event = _crypto.finishEvent(
      UnsignedNostrEvent(
        kind: 31415,
        tags: tags,
        content: content,
        createdAt: createdAt,
        pubkey: publicKey,
      ),
      privateKey,
    );
    debugPrint('NostrService: event id: ${event.id}');

    // Self-check before it goes out: a relay would reject a bad event anyway,
    // and a silently malformed one is worse than a loud failure here.
    if (!_crypto.verifyEvent(event)) {
      throw Exception('Event signature verification failed');
    }

    await publishEvent(event);
  }

  /// Timestamp for the next addressable event of [dTag], strictly greater
  /// than any this session has used for it.
  ///
  /// Relays keep a single event per (kind, pubkey, d) and, per NIP-01, a
  /// replacement must have a strictly newer created_at — on a tie the old
  /// event wins. Two publishes within the same wall-clock second would
  /// otherwise leave the relay holding the stale state, which is how a
  /// final score or a "finished" status used to go missing remotely.
  @visibleForTesting
  int nextCreatedAt(String dTag) {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final last = _lastCreatedAt[dTag];
    final createdAt = (last != null && now <= last) ? last + 1 : now;
    _lastCreatedAt[dTag] = createdAt;
    return createdAt;
  }

  /// Get the latest addressable event for a given key
  NostrEvent? getAddressableEvent(String kind, String pubkey, String dTag) {
    final key = '$kind:$pubkey:$dTag';
    return _addressableEvents[key];
  }

  /// Get list of connected relays
  List<String> get connectedRelays => _backend.connectedRelays;

  /// Disconnect all relays
  void disconnect() => _backend.disconnect();

  /// Release the service and the transport beneath it. Anything still pending
  /// in the outbox is abandoned — the caller is going away, and there is nobody
  /// left to converge for.
  void dispose() {
    // Flip this before releasing anything: publishEvent's attempts are
    // unawaited and may still be in flight, and their completion must not
    // schedule a resend timer or reach into a torn-down backend after this.
    _disposed = true;
    _backendEvents?.cancel();
    _backendConnections?.cancel();
    _resendTimer?.cancel();

    _backend.dispose();
    _eventController.close();
  }
}

/// Provider for NostrService.
///
/// Overridden in `main.dart`, which owns the relay pool's lifetime. There is no
/// sensible default: a second NostrService would mean a second set of sockets
/// and a second outbox, silently competing to publish the same match.
final nostrServiceProvider = Provider<NostrService>((ref) {
  throw UnimplementedError('nostrServiceProvider must be overridden');
});
