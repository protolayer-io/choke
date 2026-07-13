import 'package:choke/services/nostr/crypto/nostr_tools_crypto.dart';

import 'nostr_crypto_contract.dart';

/// The incumbent Dart implementation, held to the shared contract. Phase 3
/// runs the identical contract against the Rust implementation.
void main() {
  runNostrCryptoContract('NostrToolsCrypto', NostrToolsCrypto.new);
}
