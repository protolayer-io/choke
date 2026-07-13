@Tags(['rust'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/src/rust/api/crypto.dart';
import 'package:choke/src/rust/frb_generated.dart';

/// Proves the Rust toolchain is wired end to end: the crate builds, the
/// generated bindings load it, and a call crosses the bridge and comes back.
///
/// Needs the compiled native library, so it skips itself when the crate has
/// not been built — a plain `flutter test` stays green without a Rust
/// toolchain. To run it:
///
///   cargo build --manifest-path rust/Cargo.toml
///   flutter test --tags rust
void main() {
  final libraryPath = _findNativeLibrary();

  // Declared as a group with a `skip` reason rather than an early return: the
  // reason has to reach the test runner, and a bare `markTestSkipped` at
  // declaration time has no test to mark. Absent the library the group is
  // reported as skipped — not silently missing, and not a failure, so the
  // suite stays green for contributors who never touch Rust.
  group(
    'Rust bridge',
    skip: libraryPath == null
        ? 'native library not built — run: cargo build --manifest-path rust/Cargo.toml'
        : null,
    () => _bridgeTests(libraryPath),
  );
}

void _bridgeTests(String? libraryPath) {
  // A genuinely signed event, generated once with a throwaway key. Its id and
  // signature are real, so a bridge that quietly did nothing could not make
  // this pass.
  const signedEvent = '{'
      '"id":"c8f5fb4436a11dde83a4a9b737d657ac31f719e521bec41fb9a49b45a3a0d1ab",'
      '"pubkey":"fdbe9ea04b2a228b5dcd8b4dbfb665fd5465333f5f00d946d0e4e823a68e967d",'
      '"created_at":1783950883,'
      '"kind":1,'
      '"tags":[],'
      '"content":"choke phase-1 fixture",'
      '"sig":"6e198da2888437eff67ac17f178e86026dd6f29605c7322493adc25b6b1df1750a574910cfc1719e1ed0eff6e997ca97b622e0b9b2fcb4cf91a35efe2145b7c9"'
      '}';

  setUpAll(() async {
    // Non-null whenever this group runs: a null path is what skips it.
    await RustLib.init(
      externalLibrary: ExternalLibrary.open(libraryPath!),
    );
  });

  tearDownAll(() => RustLib.dispose());

  test('verifies a correctly signed event', () {
    // Act
    final isValid = verifyEvent(eventJson: signedEvent);

    // Assert
    expect(isValid, isTrue);
  });

  test('rejects an event whose content was tampered with after signing', () {
    // Arrange — same event, content changed: the id and signature no longer
    // describe it
    final tampered = jsonDecode(signedEvent) as Map<String, dynamic>;
    tampered['content'] = 'choke phase-1 forgery';

    // Act
    final isValid = verifyEvent(eventJson: jsonEncode(tampered));

    // Assert
    expect(isValid, isFalse);
  });

  test('throws when the input is not an event at all', () {
    // Act & Assert
    expect(
      () => verifyEvent(eventJson: '{"not":"an event"}'),
      throwsA(anything),
    );
  });
}

/// Where `cargo build` leaves the crate, or null if it has not been built.
/// Debug first: that is what a contributor (and CI) has just produced.
String? _findNativeLibrary() {
  const name = 'librust_lib_choke.so';
  for (final profile in ['debug', 'release']) {
    final path = 'rust/target/$profile/$name';
    if (File(path).existsSync()) return path;
  }
  return null;
}
