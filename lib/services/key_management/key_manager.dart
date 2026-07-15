import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../nostr/crypto/nostr_crypto.dart';

/// Service for managing Nostr keypairs
/// Handles generation, storage, and recovery of keys
///
/// All cryptography goes through [NostrCrypto] rather than through a library
/// of its own, so the implementation can be swapped without touching this
/// class. See docs/specs/nostr-sdk-migration.md.
class KeyManager {
  static const String _privateKeyKey = 'nostr_private_key';
  static const String _publicKeyKey = 'nostr_public_key';

  final FlutterSecureStorage _secureStorage;
  final NostrCrypto _crypto;
  String? _cachedPrivateKey;
  String? _cachedPublicKey;

  KeyManager({required NostrCrypto crypto, FlutterSecureStorage? secureStorage})
      : _crypto = crypto,
        _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            );

  /// Initialize the key manager
  /// Generates a new keypair if none exists
  /// Validates that stored public key matches the private key
  Future<void> initialize() async {
    final existingPrivateKey = await _secureStorage.read(key: _privateKeyKey);

    if (existingPrivateKey == null || existingPrivateKey.isEmpty) {
      // Generate new keypair on first launch
      await _generateAndStoreKeypair();
    } else {
      // Always derive the public key from the private key to ensure
      // the npub displayed actually corresponds to the stored nsec.
      final derivedPublicKey = _derivePublicKeyHex(existingPrivateKey);

      // Check if stored public key matches derived key and fix if needed
      final storedPublicKey = await _secureStorage.read(key: _publicKeyKey);
      if (storedPublicKey != derivedPublicKey) {
        debugPrint('KeyManager: Stored public key mismatch — correcting');
        await _secureStorage.write(key: _publicKeyKey, value: derivedPublicKey);
      }
      _cachedPrivateKey = existingPrivateKey;
      _cachedPublicKey = derivedPublicKey;
    }
  }

  /// Generate a new secp256k1 keypair and store it securely.
  Future<void> _generateAndStoreKeypair() async {
    final privateKeyHex = _crypto.generatePrivateKey();
    final publicKeyHex = _crypto.getPublicKey(privateKeyHex);

    // Store securely
    await _secureStorage.write(key: _privateKeyKey, value: privateKeyHex);
    await _secureStorage.write(key: _publicKeyKey, value: publicKeyHex);

    // Cache in memory
    _cachedPrivateKey = privateKeyHex;
    _cachedPublicKey = publicKeyHex;

    debugPrint('KeyManager: New keypair generated and stored');
  }

  /// Get the public key in hex format
  Future<String?> getPublicKeyHex() async {
    if (_cachedPublicKey != null) return _cachedPublicKey;
    return await _secureStorage.read(key: _publicKeyKey);
  }

  /// Get the private key in hex format (nsec without prefix)
  /// WARNING: Only use this when absolutely necessary
  Future<String?> getPrivateKeyHex() async {
    if (_cachedPrivateKey != null) return _cachedPrivateKey;
    return await _secureStorage.read(key: _privateKeyKey);
  }

  /// Get public key in NIP-19 npub format
  Future<String?> getNpub() async {
    final publicKeyHex = await getPublicKeyHex();
    if (publicKeyHex == null) return null;
    return _encodeNpub(publicKeyHex);
  }

  /// Get private key in NIP-19 nsec format
  Future<String?> getNsec() async {
    final privateKeyHex = await getPrivateKeyHex();
    if (privateKeyHex == null) return null;
    return _encodeNsec(privateKeyHex);
  }

  /// Generate a brand new keypair, replacing the current identity.
  ///
  /// WARNING: this discards the keypair currently in secure storage. If the
  /// user has not backed up their nsec beforehand, the previous identity is
  /// permanently lost. Callers must confirm intent before invoking this.
  Future<void> generateNewKeypair() async {
    await _generateAndStoreKeypair();
  }

  /// Import a private key from nsec format
  /// Returns true if successful, false otherwise
  Future<bool> importFromNsec(String nsec) async {
    try {
      // Validate and decode nsec
      final privateKeyHex = _decodeNsec(nsec);
      if (privateKeyHex == null) {
        debugPrint('KeyManager: Invalid nsec format');
        return false;
      }

      // Derive public key from private key using secp256k1
      final publicKeyHex = _derivePublicKeyHex(privateKeyHex);

      // Store new keys (replaces existing)
      await _secureStorage.write(key: _privateKeyKey, value: privateKeyHex);
      await _secureStorage.write(key: _publicKeyKey, value: publicKeyHex);

      // Update cache
      _cachedPrivateKey = privateKeyHex;
      _cachedPublicKey = publicKeyHex;

      debugPrint('KeyManager: Keypair imported successfully');
      return true;
    } catch (_) {
      // Not logged: everything inside this try handles the private key the
      // user is importing, so the exception's message can carry it into the
      // device log.
      debugPrint('KeyManager: Error importing nsec');
      return false;
    }
  }

  /// Export public key as QR code data
  Future<String?> getPublicKeyForQR() async {
    return await getNpub();
  }

  /// Check if keys exist
  Future<bool> hasKeys() async {
    final privateKey = await _secureStorage.read(key: _privateKeyKey);
    return privateKey != null && privateKey.isNotEmpty;
  }

  /// Delete all keys (use with caution!)
  Future<void> deleteKeys() async {
    await _secureStorage.delete(key: _privateKeyKey);
    await _secureStorage.delete(key: _publicKeyKey);
    _cachedPrivateKey = null;
    _cachedPublicKey = null;
    debugPrint('KeyManager: All keys deleted');
  }

  /// Derive secp256k1 public key from private key.
  String _derivePublicKeyHex(String privateKeyHex) {
    try {
      return _crypto.getPublicKey(privateKeyHex);
    } catch (_) {
      // The exception is not logged: it was raised while handling the private
      // key, so its message can carry the key itself into the device log —
      // and debugPrint is not stripped from release builds. The throw still
      // propagates, so no error is swallowed.
      debugPrint('KeyManager: Error deriving public key');
      rethrow;
    }
  }

  /// Encode hex public key to npub (NIP-19 bech32)
  String _encodeNpub(String hexPublicKey) {
    try {
      return _crypto.npubEncode(hexPublicKey);
    } catch (e) {
      debugPrint('KeyManager: Error encoding npub: $e');
      rethrow;
    }
  }

  /// Encode hex private key to nsec (NIP-19 bech32)
  String _encodeNsec(String hexPrivateKey) {
    try {
      return _crypto.nsecEncode(hexPrivateKey);
    } catch (_) {
      // Same reasoning as _derivePublicKeyHex: the input is the private key,
      // so the exception's message must not reach the log.
      debugPrint('KeyManager: Error encoding nsec');
      rethrow;
    }
  }

  /// Decode nsec to hex private key, or null if it is not a valid nsec.
  String? _decodeNsec(String nsec) => _crypto.nsecDecode(nsec);
}

/// Provider for KeyManager.
///
/// Overridden in `main.dart` with the app's real one. It cannot build a default
/// any more: a KeyManager needs a NostrCrypto, and quietly inventing one here
/// is how a test ends up asserting against an identity the app never uses.
final keyManagerProvider = Provider<KeyManager>((ref) {
  throw UnimplementedError('keyManagerProvider must be overridden');
});

/// Provider for npub (public identity)
final npubProvider = FutureProvider<String?>((ref) async {
  final keyManager = ref.watch(keyManagerProvider);
  return await keyManager.getNpub();
});

/// Provider for nsec (private key - use with caution)
final nsecProvider = FutureProvider<String?>((ref) async {
  final keyManager = ref.watch(keyManagerProvider);
  return await keyManager.getNsec();
});
