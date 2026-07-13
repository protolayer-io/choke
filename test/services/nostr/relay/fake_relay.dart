import 'dart:convert';
import 'dart:io';

/// A real Nostr relay, in-process, speaking just enough NIP-01 to be honest:
/// `EVENT` → `OK`, `REQ` → the events it holds, then `EOSE`.
///
/// A real socket rather than a mock, on purpose. The two backends being
/// compared share no code at all — one is Dart over `web_socket_channel`, the
/// other is Rust over `nostr-sdk`. The wire is the only place they can be held
/// to the same standard; a mock would prove only that each matches its own idea
/// of the protocol.
class FakeRelay {
  final HttpServer _server;
  final List<WebSocket> _clients = [];
  final List<Map<String, dynamic>> _stored = [];

  /// When set, every event is rejected with this reason — a relay that is up,
  /// answering, and saying no (rate limiting, policy).
  String? rejectReason;

  /// Events this relay accepted, oldest first.
  List<Map<String, dynamic>> get received => List.unmodifiable(_stored);

  /// Captured at construction: a stopped relay still has to be able to say
  /// where it *was*, since a drill's whole point is bringing it back there.
  final int port;
  final String url;

  FakeRelay._(this._server)
      : port = _server.port,
        url = 'ws://127.0.0.1:${_server.port}' {
    _server.transform(WebSocketTransformer()).listen(_handleClient);
  }

  /// Start a relay. Pass [port] to take over an address a stopped relay left
  /// behind — that is how a drill makes a relay *come back*, rather than
  /// replacing it with a different one the app has never heard of.
  static Future<FakeRelay> start({int port = 0}) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
    return FakeRelay._(server);
  }

  void _handleClient(WebSocket socket) {
    _clients.add(socket);
    socket.listen(
      (dynamic raw) => _handleMessage(socket, raw as String),
      onDone: () => _clients.remove(socket),
      onError: (_) => _clients.remove(socket),
    );
  }

  void _handleMessage(WebSocket socket, String raw) {
    final message = jsonDecode(raw) as List<dynamic>;
    if (message.isEmpty) return;

    switch (message[0] as String) {
      case 'EVENT':
        // Client-to-relay is ["EVENT", <event>]; the subscription id only
        // appears in the relay-to-client direction.
        final event = message[1] as Map<String, dynamic>;
        final id = event['id'] as String;
        final reason = rejectReason;
        if (reason != null) {
          socket.add(jsonEncode(['OK', id, false, reason]));
          return;
        }
        _stored.add(event);
        socket.add(jsonEncode(['OK', id, true, '']));

      case 'REQ':
        final subscriptionId = message[1] as String;
        for (final event in _stored) {
          socket.add(jsonEncode(['EVENT', subscriptionId, event]));
        }
        socket.add(jsonEncode(['EOSE', subscriptionId]));

      case 'CLOSE':
        break;
    }
  }

  /// Push an event to every subscriber, as a relay does when somebody else
  /// publishes one.
  void broadcast(String subscriptionId, Map<String, dynamic> event) {
    _stored.add(event);
    for (final client in _clients) {
      client.add(jsonEncode(['EVENT', subscriptionId, event]));
    }
  }

  Future<void> stop() async {
    for (final client in List.of(_clients)) {
      await client.close();
    }
    _clients.clear();
    await _server.close(force: true);
  }
}
