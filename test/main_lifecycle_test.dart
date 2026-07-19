import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/main.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';

import 'support/nostr_fakes.dart';

/// A NostrService that only counts how often the app asks it to recycle its
/// relay connections.
class _ReconnectSpyService extends NostrService {
  _ReconnectSpyService()
      : super(
          KeyManager(crypto: FakeNostrCrypto()),
          crypto: FakeNostrCrypto(),
          backend: FakeRelayBackend(),
        );

  int reconnectCalls = 0;

  @override
  Future<void> reconnectAll() async {
    reconnectCalls++;
  }
}

void main() {
  late _ReconnectSpyService service;

  setUp(() {
    service = _ReconnectSpyService();
  });

  tearDown(() => service.dispose());

  Future<void> pumpApp(WidgetTester tester) async {
    final crypto = FakeNostrCrypto();
    final keyManager = KeyManager(crypto: crypto);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          nostrCryptoProvider.overrideWithValue(crypto),
          keyManagerProvider.overrideWithValue(keyManager),
          nostrServiceProvider.overrideWithValue(service),
        ],
        child: const ChokeApp(),
      ),
    );
  }

  testWidgets('recycles every relay connection when the app resumes',
      (tester) async {
    // Arrange — backgrounding kills sockets without a close frame, so resume
    // must not trust any connection that looks open
    await pumpApp(tester);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    expect(service.reconnectCalls, 0);

    // Act
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    // Assert
    expect(service.reconnectCalls, 1);
  });

  testWidgets('leaves connections alone on every other lifecycle change',
      (tester) async {
    // Arrange
    await pumpApp(tester);

    // Act — the transitions short of resuming
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();

    // Assert — recycling sockets mid-use would drop live subscriptions
    expect(service.reconnectCalls, 0);

    // Restore the default state so later tests see a live app
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
  });
}
