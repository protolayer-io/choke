import '../nostr_service.dart' show NostrEvent;

/// Filter for Nostr subscriptions (NIP-01 `REQ`).
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

  Future<void> addRelay(String url);

  void removeRelay(String url);

  /// Drop every socket and dial again, without waiting for TCP to notice they
  /// are dead. Used when the app resumes: backgrounding kills sockets without
  /// a close frame.
  Future<void> reconnectAll();

  /// Subscribe on every relay. Subscriptions outlive reconnects: a backend
  /// re-establishes them on a fresh socket by itself.
  void subscribe(String subscriptionId, Filter filter);

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

  void disconnect();

  void dispose();
}
