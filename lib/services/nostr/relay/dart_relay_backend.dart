import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../nostr_service.dart' show NostrEvent;
import 'nostr_relay_backend.dart';

/// Creates the WebSocket for a relay connection; injectable for tests.
typedef WebSocketChannelFactory = WebSocketChannel Function(Uri uri);

/// A single relay's socket, and the protocol spoken over it.
///
/// The subtleties here were all paid for in production (PRs #77, #78):
/// publishing waits for the relay's `OK` rather than assuming the write landed;
/// silence past [okTimeout] means the socket is dead, not slow; and a socket
/// being replaced is torn down explicitly, so its late `onDone` cannot take
/// down its own replacement.
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
      debugPrint('RelayConnection: Connected to $url');

      _channelSub = _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (error) {
          debugPrint('RelayConnection: Error on $url: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('RelayConnection: Disconnected from $url');
          _handleDisconnect();
        },
      );

      // Resubscribe to active subscriptions after connection is confirmed
      for (final entry in _subscriptionFilters.entries) {
        _subscribe(entry.key, entry.value);
      }
    } on TimeoutException catch (e) {
      debugPrint('RelayConnection: Connection timeout to $url: $e');
      _channel?.sink.close();
      _channel = null;
      _scheduleReconnect();
    } catch (e) {
      debugPrint('RelayConnection: Failed to connect to $url: $e');
      _scheduleReconnect();
    }
  }

  void _handleMessage(dynamic data) {
    try {
      final raw = data as String;
      debugPrint(
          'RelayConnection: [$url] received: ${raw.length > 200 ? '${raw.substring(0, 200)}...' : raw}');
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
            'RelayConnection: [$url] OK: eventId=${message[1]}, accepted=${message[2]}, msg=${message.length > 3 ? message[3] : ""}');
        _okController.add(message);
      } else if (type == 'NOTICE' && message.length >= 2) {
        debugPrint('RelayConnection: [$url] NOTICE: ${message[1]}');
      }
    } catch (e) {
      debugPrint('RelayConnection: Error parsing message: $e');
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
      debugPrint('RelayConnection: Attempting reconnect to $url');
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
    debugPrint('RelayConnection: [$url] publishing event ${event.id}');

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
      debugPrint('RelayConnection: [$url] rejected event ${event.id}: $reason');
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

/// [NostrRelayBackend] over hand-written WebSockets — the transport the app has
/// always used, now behind the interface.
///
/// A pool of [RelayConnection]s and nothing more: it moves bytes and reports
/// what each relay said. Reliability lives above it, in `NostrService`.
class DartRelayBackend implements NostrRelayBackend {
  final Map<String, RelayConnection> _relays = {};
  final Map<String, StreamSubscription<NostrEvent>> _eventSubscriptions = {};
  final Map<String, StreamSubscription<bool>> _connectionSubscriptions = {};

  final _eventController = StreamController<NostrEvent>.broadcast();
  final _relayConnectedController = StreamController<String>.broadcast();

  /// Held so a relay added later still gets the subscriptions made earlier.
  final Map<String, Filter> _subscriptionFilters = {};

  final WebSocketChannelFactory? _channelFactory;
  final Duration _okTimeout;

  DartRelayBackend({
    WebSocketChannelFactory? channelFactory,
    Duration okTimeout = const Duration(seconds: 10),
  })  : _channelFactory = channelFactory,
        _okTimeout = okTimeout;

  @override
  Stream<NostrEvent> get events => _eventController.stream;

  @override
  Stream<String> get onRelayConnected => _relayConnectedController.stream;

  @override
  List<String> get relayUrls => _relays.keys.toList();

  @override
  List<String> get connectedRelays =>
      _relays.values.where((r) => r.isConnected).map((r) => r.url).toList();

  @override
  Future<void> addRelay(String url) async {
    if (_relays.containsKey(url)) {
      debugPrint('DartRelayBackend: Relay $url already exists');
      return;
    }

    final relay = RelayConnection(
      url,
      channelFactory: _channelFactory,
      okTimeout: _okTimeout,
    );
    _relays[url] = relay;

    _eventSubscriptions[url] = relay.messageStream.listen(_eventController.add);
    _connectionSubscriptions[url] = relay.connectionStream.listen((connected) {
      if (connected) _relayConnectedController.add(url);
    });

    // A relay joining late still owes us the subscriptions everyone else has.
    for (final entry in _subscriptionFilters.entries) {
      relay.subscribe(entry.key, entry.value);
    }

    await relay.connect();
  }

  @override
  void removeRelay(String url) {
    _eventSubscriptions.remove(url)?.cancel();
    _connectionSubscriptions.remove(url)?.cancel();
    _relays.remove(url)?.dispose();
  }

  @override
  Future<void> reconnectAll() async {
    await Future.wait(_relays.values.map((relay) => relay.reconnectNow()));
  }

  @override
  void subscribe(String subscriptionId, Filter filter) {
    _subscriptionFilters[subscriptionId] = filter;
    for (final relay in _relays.values) {
      relay.subscribe(subscriptionId, filter);
    }
  }

  @override
  void unsubscribe(String subscriptionId) {
    _subscriptionFilters.remove(subscriptionId);
    for (final relay in _relays.values) {
      relay.unsubscribe(subscriptionId);
    }
  }

  @override
  Future<bool> publish(String relayUrl, NostrEvent event) {
    final relay = _relays[relayUrl];
    if (relay == null) {
      throw Exception('Unknown relay $relayUrl');
    }
    return relay.publish(event);
  }

  @override
  bool isAwaitingOk(String relayUrl, String eventId) =>
      _relays[relayUrl]?.isAwaitingOk(eventId) ?? false;

  @override
  void disconnect() {
    for (final relay in _relays.values) {
      relay.disconnect();
    }
  }

  @override
  void dispose() {
    for (final subscription in _eventSubscriptions.values) {
      subscription.cancel();
    }
    _eventSubscriptions.clear();
    for (final subscription in _connectionSubscriptions.values) {
      subscription.cancel();
    }
    _connectionSubscriptions.clear();

    for (final relay in _relays.values) {
      relay.dispose();
    }
    _relays.clear();

    _eventController.close();
    _relayConnectedController.close();
  }
}
