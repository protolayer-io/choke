import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/crypto/nostr_tools_crypto.dart';

/// Pins the identity guarantees the crypto migration must not break: the key
/// in secure storage *is* the user's identity, and swapping the crypto
/// implementation underneath it (Phase 4) must leave the npub it derives
/// untouched. See docs/specs/nostr-sdk-migration.md (I7).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // In-memory stand-in for the platform keystore.
  late Map<String, String> storage;

  setUp(() {
    storage = {};
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        final args = (call.arguments as Map?)?.cast<String, dynamic>() ?? {};
        final key = args['key'] as String?;
        switch (call.method) {
          case 'write':
            storage[key!] = args['value'] as String;
            return null;
          case 'read':
            return storage[key];
          case 'delete':
            storage.remove(key);
            return null;
          case 'readAll':
            return storage;
          case 'deleteAll':
            storage.clear();
            return null;
          case 'containsKey':
            return storage.containsKey(key);
          default:
            return null;
        }
      },
    );
  });

  KeyManager subject() => KeyManager(
        secureStorage: const FlutterSecureStorage(),
        crypto: NostrToolsCrypto(),
      );

  group('first launch', () {
    test('generates and stores a keypair', () async {
      // Arrange
      final manager = subject();

      // Act
      await manager.initialize();

      // Assert
      expect(await manager.hasKeys(), isTrue);
      expect(await manager.getPrivateKeyHex(), hasLength(64));
      expect(await manager.getNpub(), startsWith('npub1'));
      expect(await manager.getNsec(), startsWith('nsec1'));
    });

    test('the stored public key belongs to the stored private key', () async {
      // Arrange
      final manager = subject();

      // Act
      await manager.initialize();

      // Assert — the npub the user shows the world must be the one their nsec
      // actually signs with
      final privateKey = (await manager.getPrivateKeyHex())!;
      final derived = NostrToolsCrypto().getPublicKey(privateKey);
      expect(await manager.getPublicKeyHex(), derived);
    });
  });

  group('reopening the app', () {
    test('keeps the identity it already had', () async {
      // Arrange — a first run generates the keys
      await subject().initialize();
      final npubBefore = await subject().getNpub();

      // Act — a later run reads them back
      final reopened = subject();
      await reopened.initialize();

      // Assert — the invariant Phase 4 must not break: the key lives in secure
      // storage, so changing the crypto backend may change *how* the npub is
      // derived but never *what* it is.
      expect(await reopened.getNpub(), npubBefore);
    });

    test('repairs a stored public key that does not match the private key',
        () async {
      // Arrange — a corrupted install whose npub lies about its nsec
      await subject().initialize();
      final privateKey = storage['nostr_private_key']!;
      storage['nostr_public_key'] = 'deadbeef' * 8;

      // Act
      final manager = subject();
      await manager.initialize();

      // Assert — always re-derived from the private key, never trusted
      expect(
        await manager.getPublicKeyHex(),
        NostrToolsCrypto().getPublicKey(privateKey),
      );
    });
  });

  group('importing an nsec', () {
    // The NIP-19 spec's own test vector.
    const nsec =
        'nsec1vl029mgpspedva04g90vltkh6fvh240zqtv9k0t9af8935ke9laqsnlfe5';
    const privateKeyHex =
        '67dea2ed018072d675f5415ecfaed7d2597555e202d85b3d65ea4e58d2d92ffa';

    test('replaces the identity with the imported one', () async {
      // Arrange
      final manager = subject();
      await manager.initialize();

      // Act
      final imported = await manager.importFromNsec(nsec);

      // Assert
      expect(imported, isTrue);
      expect(await manager.getPrivateKeyHex(), privateKeyHex);
      expect(await manager.getNsec(), nsec);
      expect(
        await manager.getPublicKeyHex(),
        NostrToolsCrypto().getPublicKey(privateKeyHex),
      );
    });

    test('rejects a malformed nsec without disturbing the current keys',
        () async {
      // Arrange
      final manager = subject();
      await manager.initialize();
      final npubBefore = await manager.getNpub();

      // Act
      final imported = await manager.importFromNsec('nsec1nonsense');

      // Assert — a typo in the import field must not cost the user their
      // identity
      expect(imported, isFalse);
      expect(await manager.getNpub(), npubBefore);
    });
  });

  test('deleting keys leaves nothing behind', () async {
    // Arrange
    final manager = subject();
    await manager.initialize();

    // Act
    await manager.deleteKeys();

    // Assert
    expect(await manager.hasKeys(), isFalse);
    expect(await manager.getPrivateKeyHex(), isNull);
  });
}
