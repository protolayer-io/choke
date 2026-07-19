import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';

void main() {
  test('nostrCryptoProvider refuses to build without an override', () {
    // Arrange — the provider deliberately has no default implementation:
    // main.dart must name the backend exactly once
    final container = ProviderContainer();
    addTearDown(container.dispose);

    // Act + Assert
    expect(
      () => container.read(nostrCryptoProvider),
      throwsUnimplementedError,
    );
  });
}
