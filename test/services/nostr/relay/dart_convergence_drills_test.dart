import 'package:choke/services/nostr/relay/dart_relay_backend.dart';

import 'convergence_drills.dart';

/// The incumbent transport, put through the failure drills from #78.
void main() {
  runConvergenceDrills('DartRelayBackend', DartRelayBackend.new);
}
