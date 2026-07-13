@Tags(['rust'])
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/crypto/rust_nostr_crypto.dart';
import 'package:choke/src/rust/frb_generated.dart';

import 'nostr_crypto_contract.dart';

/// The app's only crypto implementation, held to the contract.
///
/// The differential suite that compared it against `nostr_tools` lived here
/// until Phase 8. It did its job — it is what earned the switch — and it went
/// out with the library it was comparing against.
///
/// Needs the native library, so it skips itself when the crate has not been
/// built:
///
///   cargo build --manifest-path rust/Cargo.toml
///   flutter test --tags rust
void main() {
  final libraryPath = _findNativeLibrary();
  final skip = libraryPath == null
      ? 'native library not built — run: cargo build --manifest-path rust/Cargo.toml'
      : null;

  group('Rust crypto', skip: skip, () {
    setUpAll(() async {
      await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath!));
    });

    tearDownAll(() => RustLib.dispose());

    // The identical suite NostrToolsCrypto passes, not one line changed.
    runNostrCryptoContract('RustNostrCrypto', RustNostrCrypto.new);

  });
}

/// Renders control characters visibly, so a failure message stays readable.
String _describe(String content) =>
    content.replaceAll('\n', r'\n').replaceAll('\t', r'\t');

/// Where `cargo build` leaves the crate, or null if it has not been built.
///
/// The filename follows the host: these tests run on a developer's machine and
/// on CI, not on a device, so a hardcoded `.so` would silently skip the whole
/// suite on macOS or Windows.
String? _findNativeLibrary() {
  final name = Platform.isMacOS
      ? 'librust_lib_choke.dylib'
      : Platform.isWindows
          ? 'rust_lib_choke.dll'
          : 'librust_lib_choke.so';

  for (final profile in ['debug', 'release']) {
    final path = 'rust/target/$profile/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
}
