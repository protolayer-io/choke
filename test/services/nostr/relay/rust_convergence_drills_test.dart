@Tags(['rust'])
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/relay/rust_relay_backend.dart';
import 'package:choke/src/rust/frb_generated.dart';

import 'convergence_drills.dart';

/// The transport Phase 7 hands the keys to, put through the identical failure
/// drills from #78 — the ones that produced the stale-scoreboard bug.
///
///   cargo build --manifest-path rust/Cargo.toml
///   flutter test --tags rust
void main() {
  final libraryPath = _findNativeLibrary();
  if (libraryPath == null) {
    group('RustRelayBackend', skip: 'native library not built', () {
      test('needs cargo build --manifest-path rust/Cargo.toml', () {});
    });
    return;
  }

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  });

  runConvergenceDrills(
    'RustRelayBackend',
    RustRelayBackend.new,
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
