import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/settings/providers/relay_config_provider.dart';

/// In-memory stand-in for [FlutterSecureStorage].
///
/// The relay list is persisted through the secure storage plugin, which does
/// not exist on the test host. [RelayConfigService] only ever calls [read] and
/// [write], so those are the only members implemented; anything else throws
/// via [Fake], loudly, instead of silently pretending.
class InMemorySecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> store = {};

  /// When set, [read]/[write] throw — the storage-failure paths need a way to
  /// fail on demand.
  bool throwOnRead = false;
  bool throwOnWrite = false;

  int writeCount = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnRead) throw Exception('storage read failed');
    return store[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnWrite) throw Exception('storage write failed');
    writeCount++;
    if (value == null) {
      store.remove(key);
    } else {
      store[key] = value;
    }
  }
}

/// A [RelayConfigNotifier] whose connectivity probe never opens a socket.
///
/// `testRelayConnectivity` is the seam the production notifier exposes for its
/// WebSocket ping; overriding it here keeps every add-relay test off the
/// network entirely and makes reachability a knob the test turns.
class TestableRelayConfigNotifier extends RelayConfigNotifier {
  TestableRelayConfigNotifier(super.service, {this.reachable = true});

  /// What the fake probe reports.
  bool reachable;

  /// How many times addRelay actually probed — validation-failure tests
  /// assert this stayed at zero.
  int connectivityChecks = 0;

  /// When set, the probe waits on this before answering, so a test can hold
  /// the screen in its "Adding…" state and look at it.
  Completer<void>? gate;

  @override
  Future<bool> testRelayConnectivity(String url) async {
    connectivityChecks++;
    final pending = gate;
    if (pending != null) await pending.future;
    return reachable;
  }
}

/// A service whose [loadRelays] always throws, to reach the notifier's
/// initialize-failure branch — the real service swallows storage errors and
/// falls back to defaults, so a storage fake alone can never get there.
class ThrowingLoadRelayConfigService extends RelayConfigService {
  ThrowingLoadRelayConfigService()
      : super(secureStorage: InMemorySecureStorage());

  @override
  Future<List<RelayConfig>> loadRelays() async {
    throw Exception('load blew up');
  }
}
