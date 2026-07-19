@Tags(['rust'])
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/relay/nostr_relay_backend.dart';
import 'package:choke/services/nostr/relay/rust_relay_backend.dart';
import 'package:choke/src/rust/frb_generated.dart';

/// Edge paths of the Rust transport the contract suite does not reach:
/// registration failure rollback, unsubscribe, and disconnect. None of them
/// need a live relay — they exercise the backend's own bookkeeping.
void main() {
  final libraryPath = _findNativeLibrary();
  if (libraryPath == null) {
    group('RustRelayBackend edges', skip: 'native library not built', () {
      test('needs cargo build --manifest-path rust/Cargo.toml', () {});
    });
    return;
  }

  setUpAll(() async {
    await RustLib.init(externalLibrary: ExternalLibrary.open(libraryPath));
  });

  late RustRelayBackend backend;

  setUp(() {
    backend = RustRelayBackend();
  });

  tearDown(() => backend.dispose());

  test('a relay the pool refuses to register never joins the convergence set',
      () async {
    // Arrange — a URL nostr-sdk cannot parse

    // Act + Assert — the failure propagates...
    await expectLater(
      backend.addRelay('not a relay url'),
      throwsA(anything),
    );

    // ...and leaves no phantom behind: convergence must never wait on a
    // relay that does not exist
    expect(backend.relayUrls, isEmpty);
  });

  test('unsubscribe drops a subscription without complaint', () async {
    // Arrange — the pool needs at least one registered relay to take a
    // subscription; this one is never actually reachable
    await backend.addRelay('wss://relay.invalid.example');
    backend.subscribe('edge_sub', const Filter(kinds: [31415]));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    // Act — must not throw even though the relay never connected
    backend.unsubscribe('edge_sub');
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });

  test('disconnect clears the connected view immediately', () async {
    // Arrange
    await backend.addRelay('wss://relay.invalid.example');

    // Act — the sockets are dropped and, synchronously, nothing counts as up
    backend.disconnect();

    // Assert
    expect(backend.connectedRelays, isEmpty);
    // The relay stays registered: disconnect() is not removeRelay()
    expect(backend.relayUrls, ['wss://relay.invalid.example']);
    await Future<void>.delayed(const Duration(milliseconds: 100));
  });
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
