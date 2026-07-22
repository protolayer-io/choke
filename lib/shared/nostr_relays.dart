/// The relays a fresh install starts with.
///
/// The canonical definition. Both the settings layer
/// (`RelayConfigService.defaultRelays`, which seeds secure storage) and the
/// transport (`NostrService.initialize`, which falls back to this when nothing
/// is configured) read it from here — they used to hold separate literals kept
/// in step by a comment, which is the arrangement that quietly drifts.
///
/// `relay.mostro.network` used to be on this list and was removed: it answers
/// `rate-limited: allowed kinds: max 5 events per minute per IP`, and a match
/// publishes one addressable event per tap — a scoring burst blows through five
/// in seconds, after which the relay refuses everything and the remote
/// scoreboard stops moving. Measured, not guessed: 5 of 12 events accepted in
/// one burst, against 25 of 25 for nos.lol and 12 of 12 for relay.primal.net.
/// It is a Mostro P2P relay; a live scoreboard is not what it is for.
///
/// Changing this list only affects fresh installs — existing ones keep whatever
/// is in secure storage.
const List<String> defaultNostrRelays = [
  'wss://nos.lol',
  'wss://relay.primal.net',
];
