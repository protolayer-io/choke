import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/account/account_screen.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/services/key_management/key_manager.dart';

import '../../support/nostr_fakes.dart';

/// A [KeyManager] that never touches secure storage. It records whether a new
/// keypair was requested and swaps the identity it reports so the screen can be
/// observed reacting to the regeneration.
class _SpyKeyManager extends KeyManager {
  _SpyKeyManager() : super(crypto: FakeNostrCrypto());

  int generateCalls = 0;
  String _npub = 'npub1before';

  @override
  Future<void> generateNewKeypair() async {
    generateCalls++;
    _npub = 'npub1after';
  }

  @override
  Future<String?> getNpub() async => _npub;

  @override
  Future<String?> getNsec() async => 'nsec1fake';
}

void main() {
  Future<void> pumpAccountScreen(
    WidgetTester tester,
    _SpyKeyManager keyManager,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          keyManagerProvider.overrideWithValue(keyManager),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('en'),
          home: AccountScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('Generate new keypair', () {
    testWidgets('warns the user before regenerating', (tester) async {
      // Arrange
      await pumpAccountScreen(tester, _SpyKeyManager());

      // Act — tap the regenerate button in the header
      await tester.tap(find.byIcon(Icons.autorenew));
      await tester.pumpAndSettle();

      // Assert — the dialog spells out the risk and offers both choices
      expect(find.text('Generate New Keypair?'), findsOneWidget);
      expect(
        find.textContaining('will be lost permanently'),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Cancel'), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, 'Generate'), findsOneWidget);
    });

    testWidgets('cancelling leaves the identity untouched', (tester) async {
      // Arrange
      final keyManager = _SpyKeyManager();
      await pumpAccountScreen(tester, keyManager);
      await tester.tap(find.byIcon(Icons.autorenew));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      // Assert — no keypair generated, dialog dismissed
      expect(keyManager.generateCalls, 0);
      expect(find.text('Generate New Keypair?'), findsNothing);
    });

    testWidgets('confirming generates a new keypair and reports success',
        (tester) async {
      // Arrange
      final keyManager = _SpyKeyManager();
      await pumpAccountScreen(tester, keyManager);
      expect(find.text('npub1before'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.autorenew));
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.widgetWithText(ElevatedButton, 'Generate'));
      await tester.pumpAndSettle();

      // Assert — the keypair was regenerated, the UI refreshed, user informed
      expect(keyManager.generateCalls, 1);
      expect(find.text('Generate New Keypair?'), findsNothing);
      expect(find.text('npub1after'), findsOneWidget);
      expect(
        find.text('New keypair generated successfully'),
        findsOneWidget,
      );
    });
  });
}
