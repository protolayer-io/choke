import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/settings/providers/relay_config_provider.dart';
import 'package:choke/features/settings/screens/relay_management_screen.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/shared/theme/app_theme.dart';

import '../../../support/relay_fakes.dart';

/// A service whose load waits until the test releases it, to hold the screen
/// in its loading state long enough to look at it.
class _GatedLoadService extends RelayConfigService {
  _GatedLoadService() : super(secureStorage: InMemorySecureStorage());

  final gate = Completer<void>();

  @override
  Future<List<RelayConfig>> loadRelays() async {
    await gate.future;
    return super.loadRelays();
  }
}

void main() {
  late AppLocalizations l10n;
  late InMemorySecureStorage storage;
  late TestableRelayConfigNotifier notifier;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    List<RelayConfig>? initial,
    bool reachable = true,
    RelayConfigNotifier? withNotifier,
  }) async {
    storage = InMemorySecureStorage();
    if (initial != null) {
      storage.store['nostr_relays'] =
          jsonEncode(initial.map((r) => r.toJson()).toList());
    }
    final effective = withNotifier ??
        (notifier = TestableRelayConfigNotifier(
          RelayConfigService(secureStorage: storage),
          reachable: reachable,
        ));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          relayConfigProvider.overrideWith((ref) => effective),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const RelayManagementScreen(),
        ),
      ),
    );
  }

  testWidgets('shows a spinner while the relay list is loading',
      (tester) async {
    // Arrange — a service that refuses to answer until the test says so
    final gated = _GatedLoadService();
    await pumpScreen(tester, withNotifier: RelayConfigNotifier(gated));

    // Assert — loading
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Act — release the load
    gated.gate.complete();
    await tester.pumpAndSettle();

    // Assert — the list replaced the spinner
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.text('wss://relay.mostro.network'), findsOneWidget);
  });

  testWidgets('renders the default relays as connecting, with switches on',
      (tester) async {
    // Arrange + Act
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // Assert — both defaults listed, each with an enabled switch, and the
    // status line says they are defaults still connecting
    expect(find.text('wss://relay.mostro.network'), findsOneWidget);
    expect(find.text('wss://nos.lol'), findsOneWidget);
    expect(find.text(l10n.relayStatusConnectingDefault), findsNWidgets(2));
    final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
    expect(switches, hasLength(2));
    expect(switches.every((s) => s.value), isTrue);
  });

  testWidgets('a connected default relay says so', (tester) async {
    // Arrange
    await pumpScreen(tester);
    await tester.pumpAndSettle();

    // Act — the backend reports the socket opened
    notifier.updateConnectionStatus('wss://relay.mostro.network', true);
    await tester.pump();

    // Assert — one connected, one still connecting
    expect(find.text(l10n.relayStatusConnectedDefault), findsOneWidget);
    expect(find.text(l10n.relayStatusConnectingDefault), findsOneWidget);
  });

  testWidgets('a custom relay uses the non-default status strings',
      (tester) async {
    // Arrange — one custom relay alongside a default
    await pumpScreen(tester, initial: const [
      RelayConfig(url: 'wss://relay.mostro.network'),
      RelayConfig(url: 'wss://custom.example'),
    ]);
    await tester.pumpAndSettle();

    // Assert — connecting, custom flavor
    expect(find.text(l10n.relayStatusConnecting), findsOneWidget);

    // Act
    notifier.updateConnectionStatus('wss://custom.example', true);
    await tester.pump();

    // Assert — connected, custom flavor
    expect(find.text(l10n.relayStatusConnected), findsOneWidget);
  });

  testWidgets('a disabled relay is struck through and labeled disabled',
      (tester) async {
    // Arrange
    await pumpScreen(tester, initial: const [
      RelayConfig(url: 'wss://relay.mostro.network'),
      RelayConfig(url: 'wss://off.example', isEnabled: false),
    ]);
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(l10n.relayStatusDisabled), findsOneWidget);
    final title = tester.widget<Text>(find.text('wss://off.example'));
    expect(title.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('an empty relay list shows the empty state', (tester) async {
    // Arrange — explicitly stored empty list, not first-run defaults
    await pumpScreen(tester, initial: const []);
    await tester.pumpAndSettle();

    // Assert
    expect(find.text(l10n.noRelaysConfigured), findsOneWidget);
    expect(find.text(l10n.addRelayToStart), findsOneWidget);
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
  });

  group('add relay input validation', () {
    testWidgets('an empty URL is rejected by the form', (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act — tap Add with nothing typed
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert — the field shows the error, and no probe ever ran
      expect(find.text(l10n.pleaseEnterRelayUrl), findsOneWidget);
      expect(notifier.connectivityChecks, 0);
    });

    testWidgets('a URL with the wrong scheme is rejected by the form',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(
          find.byType(TextFormField), 'https://relay.example');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayUrlMustStartWithWss), findsOneWidget);
      expect(notifier.connectivityChecks, 0);
    });

    testWidgets('rejects ws:// at the field: secure websockets only',
        (tester) async {
      // Arrange — the form enforces the same wss:// rule as the notifier, so
      // an insecure URL fails at the field instead of passing the form and
      // bouncing off addRelay with a mismatched snackbar.
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byType(TextFormField), 'ws://plain.example');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert — field error, no snackbar, and no connectivity probe fired
      expect(find.text(l10n.relayUrlMustStartWithWss), findsOneWidget);
      expect(find.text(l10n.relayErrorInvalidUrl), findsNothing);
      expect(notifier.connectivityChecks, 0);
    });
  });

  group('add relay flow', () {
    testWidgets('adds a reachable relay and confirms with a snackbar',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byType(TextFormField), 'wss://new.example');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert — listed, persisted, celebrated, input cleared
      expect(find.text('wss://new.example'), findsOneWidget);
      expect(find.text(l10n.relayAddedSuccessfully), findsOneWidget);
      expect(storage.store['nostr_relays'], contains('wss://new.example'));
      final field = tester.widget<TextFormField>(find.byType(TextFormField));
      expect(field.controller?.text, isEmpty);
    });

    testWidgets('shows the busy state while the probe is in flight',
        (tester) async {
      // Arrange — hold the connectivity probe open
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      notifier.gate = Completer<void>();

      // Act
      await tester.enterText(find.byType(TextFormField), 'wss://slow.example');
      await tester.tap(find.text(l10n.add));
      await tester.pump();

      // Assert — button swaps to a spinner and the adding label
      expect(find.text(l10n.adding), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ElevatedButton),
          matching: find.byType(CircularProgressIndicator),
        ),
        findsOneWidget,
      );

      // Act — release the probe
      notifier.gate!.complete();
      await tester.pumpAndSettle();

      // Assert — back to normal, relay added
      expect(find.text(l10n.add), findsOneWidget);
      expect(find.text('wss://slow.example'), findsOneWidget);
    });

    testWidgets('an unreachable relay shows the unreachable error snackbar',
        (tester) async {
      // Arrange
      await pumpScreen(tester, reachable: false);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(find.byType(TextFormField), 'wss://dead.example');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert — error shown once, relay not listed. The URL is still in the
      // text field (only a success clears it), so scope the check to the list.
      expect(find.text(l10n.relayErrorUnreachable), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ListTile),
          matching: find.text('wss://dead.example'),
        ),
        findsNothing,
      );
    });

    testWidgets('a duplicate relay shows the already-exists error snackbar',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act
      await tester.enterText(
          find.byType(TextFormField), 'wss://relay.mostro.network');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayErrorAlreadyExists), findsOneWidget);
    });
  });

  group('toggle relay', () {
    testWidgets('the switch disables a relay when another remains enabled',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();

      // Act — toggle the second default off
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayStatusDisabled), findsOneWidget);
      final switches = tester.widgetList<Switch>(find.byType(Switch)).toList();
      expect(switches.where((s) => s.value), hasLength(1));
    });

    testWidgets('disabling the last enabled relay is refused with an error',
        (tester) async {
      // Arrange — only one relay, enabled
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network'),
      ]);
      await tester.pumpAndSettle();

      // Act
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Assert — still enabled, error explained
      expect(find.text(l10n.relayErrorCannotDisableLast), findsOneWidget);
      expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);
    });
  });

  group('remove relay', () {
    const custom = RelayConfig(url: 'wss://custom.example');

    testWidgets('default relays cannot be swiped away', (tester) async {
      // Arrange — one default, one custom
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network'),
        custom,
      ]);
      await tester.pumpAndSettle();

      // Assert — only the custom relay is wrapped in a Dismissible
      expect(find.byType(Dismissible), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('wss://custom.example'),
          matching: find.byType(Dismissible),
        ),
        findsOneWidget,
      );
    });

    testWidgets('cancelling the confirm dialog keeps the relay',
        (tester) async {
      // Arrange
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network'),
        custom,
      ]);
      await tester.pumpAndSettle();

      // Act — swipe, then think better of it
      await tester.drag(
          find.text('wss://custom.example'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      expect(find.text(l10n.removeRelayQuestion), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('wss://custom.example'), findsOneWidget);
    });

    testWidgets('confirming the swipe removes the relay with a snackbar',
        (tester) async {
      // Arrange
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network'),
        custom,
      ]);
      await tester.pumpAndSettle();

      // Act
      await tester.drag(
          find.text('wss://custom.example'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.remove));
      await tester.pumpAndSettle();

      // Assert — gone from the list and from disk
      expect(find.text('wss://custom.example'), findsNothing);
      expect(find.text(l10n.relayRemoved), findsOneWidget);
      expect(storage.store['nostr_relays'],
          isNot(contains('wss://custom.example')));
    });
  });

  group('failure snackbars', () {
    // Every RelayError arm has its own localized string; these pin the
    // remaining mappings the happy-path tests never reach.

    testWidgets('a failing load reports the load error over an empty list',
        (tester) async {
      // Arrange — a service that cannot load at all
      await pumpScreen(
        tester,
        withNotifier: RelayConfigNotifier(ThrowingLoadRelayConfigService()),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayErrorLoadFailed), findsOneWidget);
      expect(find.text(l10n.noRelaysConfigured), findsOneWidget);
    });

    testWidgets('a failing save while adding reports the add error',
        (tester) async {
      // Arrange — probe passes, persistence does not
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      storage.throwOnWrite = true;

      // Act
      await tester.enterText(find.byType(TextFormField), 'wss://new.example');
      await tester.tap(find.text(l10n.add));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayErrorAddFailed), findsOneWidget);
    });

    testWidgets('a failing save while removing reports the remove error',
        (tester) async {
      // Arrange
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network'),
        RelayConfig(url: 'wss://custom.example'),
      ]);
      await tester.pumpAndSettle();
      storage.throwOnWrite = true;

      // Act
      await tester.drag(
          find.text('wss://custom.example'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.remove));
      await tester.pumpAndSettle();

      // Assert — error shown, relay still listed
      expect(find.text(l10n.relayErrorRemoveFailed), findsOneWidget);
      expect(find.text('wss://custom.example'), findsOneWidget);
    });

    testWidgets('removing the only enabled relay reports the last-relay error',
        (tester) async {
      // Arrange — the custom relay is the only enabled one
      await pumpScreen(tester, initial: const [
        RelayConfig(url: 'wss://relay.mostro.network', isEnabled: false),
        RelayConfig(url: 'wss://custom.example'),
      ]);
      await tester.pumpAndSettle();

      // Act
      await tester.drag(
          find.text('wss://custom.example'), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.remove));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayErrorCannotRemoveLast), findsOneWidget);
      expect(find.text('wss://custom.example'), findsOneWidget);
    });

    testWidgets('a failing save while toggling reports the toggle error',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await tester.pumpAndSettle();
      storage.throwOnWrite = true;

      // Act
      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.relayErrorToggleFailed), findsOneWidget);
    });
  });

  testWidgets('the refresh action reloads the list from storage',
      (tester) async {
    // Arrange — storage changes behind the screen's back
    await pumpScreen(tester);
    await tester.pumpAndSettle();
    storage.store['nostr_relays'] =
        jsonEncode([const RelayConfig(url: 'wss://fresh.example').toJson()]);

    // Act
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    // Assert
    expect(find.text('wss://fresh.example'), findsOneWidget);
    expect(find.text('wss://nos.lol'), findsNothing);
  });
}
