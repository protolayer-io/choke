@Tags(['rust'])
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/relay/rust_relay_backend.dart';
import 'package:choke/src/rust/frb_generated.dart';

import 'relay_backend_contract.dart';

/// The `nostr-sdk` transport, held to the identical contract the Dart one
/// passes — same relay, same questions, not a line of the contract changed.
///
/// This is what Phase 7 flips the transport on. The two backends share no code
/// at all, so nothing short of putting both on the same wire proves them
/// interchangeable.
///
///   cargo build --manifest-path rust/Cargo.toml
///   flutter test --tags rust
void main() {
  final libraryPath = _findNativeLibrary();
  if (libraryPath == null) {
    // A group to hang the skip on, so a plain `flutter test` stays green
    // without a Rust toolchain.
    group('RustRelayBackend', skip: 'native library not built', () {
      test('needs cargo build --manifest-path rust/Cargo.toml', () {});
    });
    return;
  }

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  });

  runRelayBackendContract(
    'RustRelayBackend',
    RustRelayBackend.new,
    // The Rust pool connects and reports status asynchronously, across an FFI
    // boundary and a tokio runtime. The Dart transport answers in-process and
    // needs no such grace.
    settle: const Duration(milliseconds: 600),
  );
}

/// Where `cargo build` leaves the crate, or null if it has not been built.
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
