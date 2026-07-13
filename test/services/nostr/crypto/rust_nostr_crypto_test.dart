@Tags(['rust'])
library;

import 'dart:io';

import 'package:flutter_rust_bridge/flutter_rust_bridge_for_generated.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/crypto/nostr_tools_crypto.dart';
import 'package:choke/services/nostr/crypto/rust_nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/src/rust/frb_generated.dart';

import 'nostr_crypto_contract.dart';

/// Holds the Rust implementation to the same contract the Dart one passes,
/// then puts the two side by side.
///
/// The differential group is the point of this phase. The contract proves each
/// implementation is internally consistent; only comparing them proves they are
/// *interchangeable* — which is what Phase 4 bets the users' identities on.
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

    _differentialTests();
  });
}

/// Both implementations, fed the same inputs, must agree.
void _differentialTests() {
  group('differential (Rust vs nostr_tools)', () {
    late NostrCrypto rust;
    late NostrCrypto dart;

    setUp(() {
      rust = const RustNostrCrypto();
      dart = NostrToolsCrypto();
    });

    // Content that has historically broken hand-rolled serializers. The id is
    // a hash of the event's canonical JSON, so any disagreement about escaping
    // — UTF-8, emoji, quotes, newlines, tabs, slashes — surfaces here as a
    // different id, and the app would be publishing events relays reject.
    const contents = [
      'choke',
      '',
      'Gonçalves',
      '田中太郎',
      '🥋⚡',
      'a "quoted" string',
      'line\nbreak',
      'tab\tseparated',
      'back\\slash',
      'forward/slash',
      '{"f1_name":"José","f2_pt2":3}',
    ];

    test('derive the same public key from the same private key', () {
      // Arrange & Act & Assert — a mismatch here would change users' identities
      for (var i = 0; i < 20; i++) {
        final privateKey = rust.generatePrivateKey();

        expect(
          rust.getPublicKey(privateKey),
          dart.getPublicKey(privateKey),
          reason: 'public key differs for a generated key',
        );
      }
    });

    test('accept each other’s generated private keys', () {
      // Arrange & Act — a key from either generator must be usable by both
      final fromDart = dart.generatePrivateKey();
      final fromRust = rust.generatePrivateKey();

      // Assert
      expect(rust.getPublicKey(fromDart), dart.getPublicKey(fromDart));
      expect(dart.getPublicKey(fromRust), rust.getPublicKey(fromRust));
    });

    test('produce the same npub and nsec', () {
      for (var i = 0; i < 20; i++) {
        // Arrange
        final privateKey = rust.generatePrivateKey();
        final publicKey = rust.getPublicKey(privateKey);

        // Act & Assert — the npub is what the user reads off the Account screen
        // and what a dashboard subscribes to; it cannot change under them
        expect(rust.npubEncode(publicKey), dart.npubEncode(publicKey));
        expect(rust.nsecEncode(privateKey), dart.nsecEncode(privateKey));
      }
    });

    test('decode each other’s nsec back to the same key', () {
      // Arrange
      final privateKey = rust.generatePrivateKey();

      // Act
      final rustNsec = rust.nsecEncode(privateKey);
      final dartNsec = dart.nsecEncode(privateKey);

      // Assert
      expect(dart.nsecDecode(rustNsec), privateKey);
      expect(rust.nsecDecode(dartNsec), privateKey);
    });

    test('agree that a malformed nsec is malformed', () {
      // Arrange — what a user might actually paste into the import field
      final npub =
          rust.npubEncode(rust.getPublicKey(rust.generatePrivateKey()));
      final inputs = ['', 'not an nsec', 'nsec1nonsense', npub];

      // Act & Assert
      for (final input in inputs) {
        expect(
          rust.nsecDecode(input),
          dart.nsecDecode(input),
          reason: 'disagreed about "$input"',
        );
        expect(rust.nsecDecode(input), isNull);
      }
    });

    test('compute the same event id for the same unsigned event', () {
      // Arrange — the id is deterministic (the signature is not), so this is
      // the strongest equivalence available: identical ids mean both libraries
      // serialize the event to identical canonical bytes.
      final privateKey = rust.generatePrivateKey();
      final publicKey = rust.getPublicKey(privateKey);

      for (final content in contents) {
        final unsigned = UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: 1700000000,
          kind: 31415,
          tags: const [
            ['d', 'abcd'],
            ['expiration', '1900000000'],
          ],
          content: content,
        );

        // Act
        final byRust = rust.finishEvent(unsigned, privateKey);
        final byDart = dart.finishEvent(unsigned, privateKey);

        // Assert
        expect(
          byRust.id,
          byDart.id,
          reason: 'event id differs for content: ${_describe(content)}',
        );
      }
    });

    test('compute the same event id whatever the tags look like', () {
      // Arrange — tags carry the d-tag identifying the match and the expiration
      // that stops relays hoarding it; both must survive the crossing
      final privateKey = rust.generatePrivateKey();
      final publicKey = rust.getPublicKey(privateKey);

      const tagSets = [
        <List<String>>[],
        [
          ['d', 'abcd']
        ],
        [
          ['d', 'abcd'],
          ['expiration', '1900000000'],
        ],
        [
          ['d', 'abcd'],
          ['t', 'bjj'],
          ['t', 'gi'],
        ],
        [
          ['d', 'ünïcødé 🥋']
        ],
      ];

      for (final tags in tagSets) {
        final unsigned = UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: 1700000000,
          kind: 31415,
          tags: tags,
          content: 'choke',
        );

        // Act
        final byRust = rust.finishEvent(unsigned, privateKey);
        final byDart = dart.finishEvent(unsigned, privateKey);

        // Assert — matching ids prove Rust hashed the tags correctly *inside*
        // Rust; they say nothing about the return leg, where the struct could
        // still mangle them on the way back to Dart. So check the tags that
        // actually came back, and that each library accepts the other's event.
        expect(byRust.id, byDart.id, reason: 'event id differs for: $tags');
        expect(byRust.tags, tags, reason: 'tags mangled crossing back: $tags');
        expect(byDart.tags, tags);
        expect(dart.verifyEvent(byRust), isTrue);
        expect(rust.verifyEvent(byDart), isTrue);
      }
    });

    test('each verifies an event the other signed', () {
      // Arrange — signatures legitimately differ (Schnorr uses a random nonce),
      // so they cannot be compared byte for byte. What must hold is that each
      // library accepts the other's work — which is what a relay, and every
      // other Nostr client, will do.
      final privateKey = rust.generatePrivateKey();
      final publicKey = rust.getPublicKey(privateKey);

      for (final content in contents) {
        final unsigned = UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: 1700000000,
          kind: 31415,
          tags: const [
            ['d', 'abcd']
          ],
          content: content,
        );

        // Act
        final byRust = rust.finishEvent(unsigned, privateKey);
        final byDart = dart.finishEvent(unsigned, privateKey);

        // Assert
        expect(dart.verifyEvent(byRust), isTrue,
            reason: 'nostr_tools rejected a Rust signature');
        expect(rust.verifyEvent(byDart), isTrue,
            reason: 'Rust rejected a nostr_tools signature');
      }
    });

    test('both reject an event tampered with after signing', () {
      // Arrange
      final privateKey = rust.generatePrivateKey();
      final publicKey = rust.getPublicKey(privateKey);
      final event = rust.finishEvent(
        UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: 1700000000,
          kind: 31415,
          tags: const [
            ['d', 'abcd']
          ],
          content: 'f1 wins',
        ),
        privateKey,
      );

      // Act — the score is rewritten, the signature left in place
      final forged = NostrEvent(
        id: event.id,
        pubkey: event.pubkey,
        createdAt: event.createdAt,
        kind: event.kind,
        tags: event.tags,
        content: 'f2 wins',
        sig: event.sig,
      );

      // Assert — the divergence found in Phase 2 (2.1) stays closed
      expect(rust.verifyEvent(forged), isFalse);
      expect(dart.verifyEvent(forged), isFalse);
    });

    test('preserve created_at exactly across the bridge', () {
      // Arrange — created_at is a 64-bit timestamp crossing an FFI boundary,
      // and NIP-01 replacement turns on it: a value mangled in transit would
      // silently break the ordering that keeps relays showing the latest score
      final privateKey = rust.generatePrivateKey();
      final publicKey = rust.getPublicKey(privateKey);
      const timestamps = [0, 1, 1700000000, 2147483647, 4102444800];

      for (final createdAt in timestamps) {
        final unsigned = UnsignedNostrEvent(
          pubkey: publicKey,
          createdAt: createdAt,
          kind: 31415,
          tags: const [
            ['d', 'abcd']
          ],
          content: 'choke',
        );

        // Act
        final byRust = rust.finishEvent(unsigned, privateKey);

        // Assert
        expect(byRust.createdAt, createdAt);
        expect(byRust.id, dart.finishEvent(unsigned, privateKey).id);
      }
    });
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
