import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:nostr_tools/nostr_tools.dart' as nostr;
import '../key_management/key_manager.dart';

/// Nostr Event model (wrapper around nostr_tools Event)
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

  /// Convert to nostr_tools Event
  nostr.Event toNostrToolsEvent() {
    return nostr.Event(
      id: id,
      pubkey: pubkey,
      created_at: createdAt,
      kind: kind,
      tags: tags,
      content: content,
      sig: sig,
    );
  }

  /// Create NostrEvent from nostr_tools Event
  factory NostrEvent.fromNostrToolsEvent(nostr.Event event) {
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

/// Filter for Nostr subscriptions
class Filter {
  final List<int>? kinds;
  final List<String>? authors;
  final List<String>? ids;
  final String? search;
  final int? since;
  final int? until;
  final int? limit;

  Filter({
    this.kinds,
    this.authors,
    this.ids,
    this.search,
    this.since,
    this.until,
    this.limit,
  });

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{};
    if (kinds != null) map['kinds'] = kinds;
    if (authors != null) map['authors'] = authors;
    if (ids != null) map['ids'] = ids;
    if (search != null) map['search'] = search;
    if (since != null) map['since'] = since;
    if (until != null) map['until'] = until;
    if (limit != null) map['limit'] = limit;
    return map;
  }
}

/// Creates the WebSocket for a relay connection; injectable for tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// Represents a Nostr relay connection
class RelayConnection {
  final String url;
  bool isConnected = false;
  WebSocketChannel? _channel;
  final WebSocketChannelFactory _channelFactory;

  /// How long to wait for a relay's OK before declaring the socket dead.
  final Duration okTimeout;

  final _messageController = StreamController<NostrEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();
  final _okController = StreamController<List<dynamic>>.broadcast();
  Timer? _reconnectTimer;
  final Set<String> _activeSubscriptions = {};
  final Map<String, Filter> _subscriptionFilters = {};

  /// Publishes waiting for an OK on the *current* socket, by event id. A
  /// socket swap fails them: the OK they wait for can never arrive.
  final Map<String, Completer<List<dynamic>>> _inFlight = {};

  /// Listener on the current socket. Held so it can be cancelled before a
  /// new socket is installed — a stale `onDone` from the old one would
  /// otherwise tear down its replacement.
  StreamSubscription<dynamic>? _channelSub;

  /// Whether a publish of this event is already in flight on this relay.
  bool isAwaitingOk(String eventId) => _inFlight.containsKey(eventId);

  RelayConnection(
    this.url, {
    WebSocketChannelFactory? channelFactory,
    this.okTimeout = const Duration(seconds: 10),
  }) : _channelFactory = channelFactory ?? WebSocketChannel.connect;

  Stream<NostrEvent> get messageStream => _messageController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  Future<void> connect() async {
    try {
      _channel = _channelFactory(Uri.parse(url));

      // Wait for WebSocket handshake to complete with timeout
      await _channel!.ready.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('WebSocket connection to $url timed out');
        },
      );

      isConnected = true;
      _connectionController.add(true);
      debugPrint('NostrService: Connected to $url');

      _channelSub = _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (error) {
          debugPrint('NostrService: Error on $url: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('NostrService: Disconnected from $url');
          _handleDisconnect();
        },
      );

      // Resubscribe to active subscriptions after connection is confirmed
      for (final entry in _subscriptionFilters.entries) {
        _subscribe(entry.key, entry.value);
      }
    } on TimeoutException catch (e) {
      debugPrint('NostrService: Connection timeout to $url: $e');
      _channel?.sink.close();
      _channel = null;
      _scheduleReconnect();
    } catch (e) {
      debugPrint('NostrService: Failed to connect to $url: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final raw = data as String;
      debugPrint(
          'NostrService: [$url] received: ${raw.length > 200 ? '${raw.substring(0, 200)}...' : raw}');
      final message = jsonDecode(raw) as List<dynamic>;
      if (message.isEmpty) return;

      final type = message[0] as String;
      if (type == 'EVENT' && message.length >= 3) {
        final eventData = message[2] as Map<String, dynamic>;
        final event = NostrEvent.fromJson(eventData);
        _messageController.add(event);
      } else if (type == 'OK' && message.length >= 3) {
        // ["OK", <event_id>, <accepted>, <message>]
        debugPrint(
            'NostrService: [$url] OK: eventId=${message[1]}, accepted=${message[2]}, msg=${message.length > 3 ? message[3] : ""}');
        _okController.add(message);
      } else if (type == 'NOTICE' && message.length >= 2) {
        debugPrint('NostrService: [$url] NOTICE: ${message[1]}');
      }
    } catch (e) {
      debugPrint('NostrService: Error parsing message: $e');
    }
  }

  void _handleDisconnect() {
    if (!isConnected) return;
    isConnected = false;
    _connectionController.add(false);
    _teardownChannel();
    _scheduleReconnect();
  }

  /// Detach from the current socket for good: stop listening (so its late
  /// `onDone` cannot tear down whatever replaces it), close it, and fail
  /// every publish still waiting on an OK it can no longer receive.
  void _teardownChannel() {
    _channelSub?.cancel();
    _channelSub = null;
    _channel?.sink.close();
    _channel = null;

    final orphaned = List.of(_inFlight.values);
    _inFlight.clear();
    for (final completer in orphaned) {
      if (!completer.isCompleted) {
        completer.completeError(
          Exception('Connection to $url closed before the relay answered'),
        );
      }
    }
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      debugPrint('NostrService: Attempting reconnect to $url');
      connect();
    });
  }

  void subscribe(String subscriptionId, Filter filter) {
    _activeSubscriptions.add(subscriptionId);
    _subscriptionFilters[subscriptionId] = filter;
    if (!isConnected) return;
    _subscribe(subscriptionId, filter);
  }

  void _subscribe(String subscriptionId, Filter filter) {
    final message = jsonEncode([
      'REQ',
      subscriptionId,
      filter.toJson(),
    ]);
    _channel?.sink.add(message);
  }

  void unsubscribe(String subscriptionId) {
    _activeSubscriptions.remove(subscriptionId);
    _subscriptionFilters.remove(subscriptionId);
    if (!isConnected) return;

    final message = jsonEncode(['CLOSE', subscriptionId]);
    _channel?.sink.add(message);
  }

  /// Publish an event and wait for OK confirmation from the relay.
  /// Returns true if relay accepted, false if rejected.
  /// Throws on connection error or timeout.
  Future<bool> publish(NostrEvent event) async {
    final channel = _channel;
    if (!isConnected || channel == null) {
      throw Exception('Not connected to relay $url');
    }

    final message = jsonEncode(['EVENT', event.toJson()]);
    debugPrint('NostrService: [$url] publishing event ${event.id}');

    // Listen for OK response matching this event ID.
    // Use manual subscription + completer to avoid stale listener leak on timeout.
    final completer = Completer<List<dynamic>>();
    final subscription = _okController.stream
        .where((msg) => msg.length >= 3 && msg[1] == event.id)
        .listen((msg) {
      if (!completer.isCompleted) completer.complete(msg);
    });

    final timer = Timer(okTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('No OK response from $url for event ${event.id}'),
        );
        // A relay that says nothing for this long is not slow — the socket
        // died without a close frame (phone slept, network switched) and
        // every write goes into a void while isConnected still reads true.
        // Recycle the connection instead of feeding more events into it.
        _handleDisconnect();
      }
    });

    _inFlight[event.id] = completer;
    channel.sink.add(message);

    List<dynamic> okMsg;
    try {
      okMsg = await completer.future;
    } finally {
      // A socket swap may already have dropped (and failed) this entry —
      // only clear it if it is still the one this publish registered.
      if (identical(_inFlight[event.id], completer)) _inFlight.remove(event.id);
      timer.cancel();
      await subscription.cancel();
    }
    final accepted = okMsg[2] as bool;
    if (!accepted) {
      final reason = okMsg.length > 3 ? okMsg[3] as String : 'unknown reason';
      debugPrint('NostrService: [$url] rejected event ${event.id}: $reason');
    }
    return accepted;
  }

  /// Tear down the socket — dead or alive — and connect a fresh one now.
  ///
  /// A socket killed while the app was backgrounded produces no close
  /// event, so [isConnected] can lie until TCP gives up minutes later.
  /// Callers that know the transport is suspect (app just resumed) use
  /// this to skip that wait; subscriptions are re-established on connect.
  Future<void> reconnectNow() async {
    _reconnectTimer?.cancel();
    if (isConnected) {
      isConnected = false;
      _connectionController.add(false);
    }
    _teardownChannel();
    await connect();
  }

  void disconnect() {
    _reconnectTimer?.cancel();
    isConnected = false;
    _teardownChannel();
  }

  void dispose() {
    disconnect();
    _messageController.close();
    _connectionController.close();
    _okController.close();
  }
}

/// Service for managing Nostr relay connections and event handling
class NostrService {
  static const int _maxCachedEvents = 1000; // Max addressable events to cache

  final KeyManager _keyManager;
  final Map<String, RelayConnection> _relays = {};
  final Map<String, StreamSubscription<NostrEvent>> _relaySubscriptions = {};
  final Map<String, StreamSubscription<bool>> _connectionSubscriptions = {};
  final _eventController = StreamController<NostrEvent>.broadcast();
  final _relayConnectedController = StreamController<String>.broadcast();
  final Map<String, NostrEvent> _addressableEvents = {};
  final Map<String, int> _lastCreatedAt = {};

  /// Latest signed event per d-tag that some relay has not accepted yet,
  /// and the relay urls that already did. "One relay accepted" is enough
  /// for the caller, but every configured relay must converge to the
  /// latest state — stragglers are resent on reconnect and by [_resendTimer].
  final Map<String, NostrEvent> _pendingLatest = {};
  final Map<String, Set<String>> _pendingAcks = {};
  Timer? _resendTimer;

  /// How often relays that are connected but still missing the latest
  /// event (e.g. they rejected it) are retried.
  final Duration resendInterval;

  final WebSocketChannelFactory? _channelFactory;
  final Duration _okTimeout;

  NostrService(
    this._keyManager, {
    WebSocketChannelFactory? channelFactory,
    Duration okTimeout = const Duration(seconds: 10),
    this.resendInterval = const Duration(seconds: 5),
  })  : _channelFactory = channelFactory,
        _okTimeout = okTimeout;

  Stream<NostrEvent> get eventStream => _eventController.stream;

  /// Fires with the relay URL each time a relay (re)connects. Publishers
  /// holding unconfirmed state listen to this to retry immediately instead
  /// of waiting out a backoff against a relay that just came back.
  Stream<String> get onRelayConnected => _relayConnectedController.stream;

  /// Connect to configured relays on app start
  Future<void> initialize({List<String>? relayUrls}) async {
    final urls = relayUrls ??
        [
          'wss://relay.mostro.network',
          'wss://nos.lol',
        ];
    for (final url in urls) {
      await addRelay(url);
    }
  }

  /// Add a custom relay
  Future<void> addRelay(String url) async {
    if (_relays.containsKey(url)) {
      debugPrint('NostrService: Relay $url already exists');
      return;
    }

    final relay = RelayConnection(
      url,
      channelFactory: _channelFactory,
      okTimeout: _okTimeout,
    );
    _relays[url] = relay;

    // Listen to events from this relay and store subscription
    final subscription = relay.messageStream.listen((event) {
      _handleIncomingEvent(event);
    });
    _relaySubscriptions[url] = subscription;

    _connectionSubscriptions[url] = relay.connectionStream.listen((connected) {
      if (!connected) return;
      _relayConnectedController.add(url);
      // A fresh socket may belong to a relay that missed events while it
      // was down — bring it up to date right away.
      _resendPendingTo(relay);
    });

    await relay.connect();
  }

  /// Remove a relay
  void removeRelay(String url) {
    // Cancel stream subscriptions to prevent memory leaks
    final subscription = _relaySubscriptions.remove(url);
    subscription?.cancel();
    final connectionSubscription = _connectionSubscriptions.remove(url);
    connectionSubscription?.cancel();

    final relay = _relays.remove(url);
    relay?.dispose();
  }

  /// Recycle every relay connection with a fresh socket.
  ///
  /// Meant for app resume: the OS kills sockets in the background without a
  /// close frame, so connections can look open while dropping every event.
  Future<void> reconnectAll() async {
    await Future.wait(_relays.values.map((relay) => relay.reconnectNow()));
  }

  /// Subscribe to kind 31415 events for the current user
  Future<void> subscribeToUserEvents() async {
    final publicKey = await _keyManager.getPublicKeyHex();
    if (publicKey == null) {
      throw Exception('No public key available');
    }

    final filter = Filter(
      kinds: [31415],
      authors: [publicKey],
    );

    for (final relay in _relays.values) {
      relay.subscribe('user_events', filter);
    }
  }

  /// Subscribe to kind 31415 events from a specific author
  void subscribeToAuthor(String authorPubkey, {String? subscriptionId}) {
    final filter = Filter(
      kinds: [31415],
      authors: [authorPubkey],
    );

    final subId = subscriptionId ?? 'author_$authorPubkey';
    for (final relay in _relays.values) {
      relay.subscribe(subId, filter);
    }
  }

  /// Unsubscribe from a subscription
  void unsubscribe(String subscriptionId) {
    for (final relay in _relays.values) {
      relay.unsubscribe(subscriptionId);
    }
  }

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

  /// Publish a signed event to all connected relays.
  /// Waits for OK confirmation from each relay.
  ///
  /// Succeeds when at least one relay accepts, but keeps working after
  /// returning: relays that were down, timed out, or rejected the event are
  /// resent the latest state per d-tag until every configured relay has it.
  Future<void> publishEvent(NostrEvent event) async {
    final dTag = _dTagOf(event);
    if (dTag != null) {
      // This event supersedes whatever was pending for the match: relays
      // that missed older states only ever need the newest one.
      _pendingLatest[dTag] = event;
      _pendingAcks[dTag] = <String>{};
    }

    final connectedRelays = _relays.values.where((r) => r.isConnected).toList();

    debugPrint(
        'NostrService: publishing event ${event.id} (kind ${event.kind}, content ${event.content.length} chars) to ${connectedRelays.length} relays');

    if (connectedRelays.isEmpty) {
      // Pending state stays registered: the reconnect listener delivers it
      // as soon as any relay comes back.
      throw Exception('No connected relays');
    }

    // Publish to all relays and wait for OK confirmations
    final results = await Future.wait(
      connectedRelays.map((relay) async {
        try {
          final accepted = await relay.publish(event);
          debugPrint('NostrService: [${relay.url}] accepted=$accepted');
          if (accepted) _markAccepted(dTag, event, relay.url);
          return accepted;
        } catch (e) {
          debugPrint('NostrService: [${relay.url}] publish error: $e');
          return false;
        }
      }),
    );

    final successCount = results.where((r) => r).length;
    debugPrint(
        'NostrService: published to $successCount/${connectedRelays.length} relays');

    _scheduleResendSweep();

    if (successCount == 0) {
      throw Exception('Event rejected by all relays');
    }
  }

  static String? _dTagOf(NostrEvent event) {
    for (final tag in event.tags) {
      if (tag.length >= 2 && tag[0] == 'd') return tag[1];
    }
    return null;
  }

  /// Record that [url] accepted [event]; forget the d-tag once every
  /// configured relay has the latest state.
  void _markAccepted(String? dTag, NostrEvent event, String url) {
    if (dTag == null) return;
    // A newer state may have superseded this event mid-flight; an ack for
    // the old one says nothing about the state the relays must converge to.
    if (!identical(_pendingLatest[dTag], event)) return;
    final acked = _pendingAcks[dTag];
    if (acked == null) return;
    acked.add(url);
    if (_relays.keys.every(acked.contains)) {
      _pendingLatest.remove(dTag);
      _pendingAcks.remove(dTag);
    }
  }

  /// Send every pending latest event this relay has not accepted yet.
  Future<void> _resendPendingTo(RelayConnection relay) async {
    for (final dTag in _pendingLatest.keys.toList()) {
      final event = _pendingLatest[dTag];
      if (event == null) continue;
      final acked = _pendingAcks[dTag];
      if (acked == null || acked.contains(relay.url)) continue;
      // The original publish may still be waiting on this relay's OK —
      // don't race it with a duplicate frame for the same event.
      if (relay.isAwaitingOk(event.id)) continue;
      try {
        final accepted = await relay.publish(event);
        debugPrint(
            'NostrService: resent ${event.id} to ${relay.url}, accepted=$accepted');
        if (accepted) _markAccepted(dTag, event, relay.url);
      } catch (e) {
        debugPrint('NostrService: resend to ${relay.url} failed: $e');
      }
    }
    _scheduleResendSweep();
  }

  /// While any relay is missing the latest state, keep a slow retry loop
  /// alive for relays that are connected but rejected it (rate limits and
  /// the like). Disconnected relays are handled by the reconnect listener.
  void _scheduleResendSweep() {
    if (_pendingLatest.isEmpty) return;
    _resendTimer ??= Timer(resendInterval, () async {
      _resendTimer = null;
      for (final relay in _relays.values.where((r) => r.isConnected)) {
        await _resendPendingTo(relay);
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

    // Build nostr_tools Event
    final nostrEvent = nostr.Event(
      kind: 31415,
      tags: tags,
      content: content,
      created_at: createdAt,
      pubkey: publicKey,
    );

    // Sign event using nostr_tools (calculates id + signature)
    final eventApi = nostr.EventApi();
    final finishedEvent = eventApi.finishEvent(nostrEvent, privateKey);
    debugPrint('NostrService: event id: ${finishedEvent.id}');
    debugPrint(
        'NostrService: event sig: ${finishedEvent.sig.substring(0, 16)}...');
    debugPrint('NostrService: event pubkey: ${finishedEvent.pubkey}');

    // Verify the signature before publishing
    final isValid = eventApi.verifySignature(finishedEvent);
    debugPrint('NostrService: signature valid: $isValid');
    if (!isValid) {
      throw Exception('Event signature verification failed');
    }

    final event = NostrEvent.fromNostrToolsEvent(finishedEvent);

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
  List<String> get connectedRelays =>
      _relays.values.where((r) => r.isConnected).map((r) => r.url).toList();

  /// Disconnect all relays
  void disconnect() {
    for (final relay in _relays.values) {
      relay.disconnect();
    }
  }

  void dispose() {
    // Cancel all relay subscriptions to prevent memory leaks
    for (final subscription in _relaySubscriptions.values) {
      subscription.cancel();
    }
    _relaySubscriptions.clear();
    for (final subscription in _connectionSubscriptions.values) {
      subscription.cancel();
    }
    _connectionSubscriptions.clear();
    _resendTimer?.cancel();

    disconnect();
    _eventController.close();
    _relayConnectedController.close();
  }
}

/// Provider for NostrService
final nostrServiceProvider = Provider<NostrService>((ref) {
  final keyManager = ref.watch(keyManagerProvider);
  final service = NostrService(keyManager);
  ref.onDispose(() => service.dispose());
  return service;
});
