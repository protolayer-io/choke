import 'package:choke/services/nostr/relay/dart_relay_backend.dart';

import 'relay_backend_contract.dart';

/// The incumbent transport, held to the shared contract against a real relay.
/// The Rust backend is held to the identical one.
void main() {
  runRelayBackendContract('DartRelayBackend', DartRelayBackend.new);
}
