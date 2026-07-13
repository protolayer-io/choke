import '../nostr_service.dart' show NostrEvent;

/// Filter for Nostr subscriptions (NIP-01 `REQ`).
///
/// Every field is optional, and null means *unconstrained*: a filter with
/// nothing set asks a relay for everything it has.
class Filter {
  /// Event kinds to match. The app only ever asks for 31415 (a match).
  final List<int>? kinds;

  /// Hex public keys whose events to match.
  final List<String>? authors;

  /// Specific event ids to match.
  final List<String>? ids;

  /// NIP-50 full-text search term. Relays may ignore it.
  final String? search;

  /// Only events created at or after this unix timestamp (seconds).
  final int? since;

  /// Only events created at or before this unix timestamp (seconds).
  final int? until;

  /// At most this many events. Relays may return fewer.
  final int? limit;

  const Filter({
    this.kinds,
    this.authors,
    this.ids,
    this.search,
    this.since,
    this.until,
    this.limit,
  });

  /// The wire form a relay expects inside a `REQ`. Unset fields are omitted
  /// rather than sent as null — a relay reads an explicit null as a constraint
  /// nothing can satisfy.
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

/// The transport: connections to relays, and nothing else.
///
/// A deliberately narrow contract. Everything that makes publishing *reliable*
/// — the outbox, per-relay convergence, the resend sweep, monotonic
/// `created_at`, the addressable cache — stays above it in `NostrService`,
/// because those behaviors were bought with real bugs (PRs #77, #78) and must
/// not be re-litigated every time the transport changes. A backend is only
/// asked to move bytes to a relay and report, honestly, what the relay said.
///
/// Two properties an implementation owes its caller, both learned the hard way:
///
/// - [publish] resolves only once *that relay* has answered `OK`. "Sent" is not
///   "accepted": a relay may reject an event (rate limits), and the caller has
///   to know the difference to keep it converging.
/// - A relay that stops answering is treated as **disconnected**, not slow. A
///   socket the OS killed without a close frame will accept writes forever
///   while delivering nothing.
///
/// See docs/specs/nostr-sdk-migration.md.
abstract class NostrRelayBackend {
  /// Every event arriving from any relay, filtered by nobody: NIP-40 expiry and
  /// addressable replacement are the caller's job.
  Stream<NostrEvent> get events;

  /// Fires with a relay's URL each time it (re)connects. The caller uses this
  /// to push state the relay missed while it was away.
  Stream<String> get onRelayConnected;

  /// Every configured relay, connected or not. Convergence is measured against
  /// this, not against whoever happens to be up right now.
  List<String> get relayUrls;

  /// The subset currently connected.
  List<String> get connectedRelays;

  /// Register a relay and dial it. Idempotent: adding one twice is a no-op.
  Future<void> addRelay(String url);

  /// Forget a relay and drop its socket. It stops counting towards
  /// convergence — a relay nobody is talking to must not hold a match hostage.
  void removeRelay(String url);

  /// Drop every socket and dial again, without waiting for TCP to notice they
  /// are dead. Used when the app resumes: backgrounding kills sockets without
  /// a close frame.
  Future<void> reconnectAll();

  /// Subscribe on every relay. Subscriptions outlive reconnects: a backend
  /// re-establishes them on a fresh socket by itself.
  void subscribe(String subscriptionId, Filter filter);

  /// Drop a subscription on every relay.
  void unsubscribe(String subscriptionId);

  /// Publish to one relay and wait for its verdict.
  ///
  /// True if the relay accepted the event, false if it rejected it and said so.
  /// Throws if the relay is not connected, or falls silent.
  Future<bool> publish(String relayUrl, NostrEvent event);

  /// Whether a publish of this event is already awaiting an OK on this relay.
  /// The caller checks this before resending, so a slow relay is never sent the
  /// same event twice.
  bool isAwaitingOk(String relayUrl, String eventId);

  /// Close every socket, keeping the relays registered. The backend is still
  /// usable afterwards — [reconnectAll] brings it back.
  void disconnect();

  /// Release everything: sockets, streams, subscriptions. The backend cannot
  /// be used again.
  void dispose();
}
