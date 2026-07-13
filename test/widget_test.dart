import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:choke/main.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/crypto/nostr_crypto.dart';
import 'package:choke/services/nostr/nostr_service.dart';

import 'support/nostr_fakes.dart';

/// The app's providers no longer invent a default Nostr stack — a default
/// would have to name an implementation, and naming one twice is what the
/// interfaces exist to prevent. A widget test says what it wants instead.
List<Override> _fakeNostrStack() {
  final crypto = FakeNostrCrypto();
  final keyManager = KeyManager(crypto: crypto);
  return [
    nostrCryptoProvider.overrideWithValue(crypto),
    keyManagerProvider.overrideWithValue(keyManager),
    nostrServiceProvider.overrideWithValue(
      NostrService(keyManager, crypto: crypto, backend: FakeRelayBackend()),
    ),
  ];
}

void main() {
  testWidgets('App loads with bottom navigation', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(
      ProviderScope(overrides: _fakeNostrStack(), child: const ChokeApp()),
    );

    // Verify that bottom navigation items exist.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Match'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Verify app title in header.
    expect(find.text('Choke'), findsOneWidget);
  });

  testWidgets('Can navigate to different tabs', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(overrides: _fakeNostrStack(), child: const ChokeApp()),
    );

    // Tap on Match tab.
    await tester.tap(find.text('Match'));
    await tester.pump();

    // Verify Match screen content.
    expect(find.text('Create a match from the Home screen'), findsOneWidget);

    // Tap on Account tab.
    await tester.tap(find.text('Account'));
    await tester.pump();

    // Verify Account screen content.
    expect(find.text('Account'), findsWidgets);
  });
}
