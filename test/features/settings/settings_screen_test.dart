import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/features/settings/screens/relay_management_screen.dart';
import 'package:choke/features/settings/screens/submissions_screen.dart';
import 'package:choke/features/settings/settings_screen.dart';
import 'package:choke/features/settings/providers/relay_config_provider.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/shared/providers/locale_provider.dart';
import 'package:choke/shared/providers/match_duration_provider.dart';
import 'package:choke/shared/providers/theme_provider.dart';
import 'package:choke/shared/theme/app_theme.dart';

import '../../support/relay_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppLocalizations l10n;

  /// Every URL the screen asked the platform to open, in order.
  final launched = <String>[];

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    // Theme and duration pickers persist via SharedPreferences.
    SharedPreferences.setMockInitialValues({});
    // The version row reads the real packageInfoProvider.
    PackageInfo.setMockInitialValues(
      appName: 'Choke',
      packageName: 'io.protolayer.choke',
      version: '9.9.9',
      buildNumber: '99',
      buildSignature: '',
    );
    // url_launcher goes through a method channel; recording it here keeps
    // link taps observable without any platform (or browser) existing.
    launched.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      (call) async {
        if (call.method == 'launch') {
          launched
              .add((call.arguments as Map<Object?, Object?>)['url']! as String);
          return true;
        }
        if (call.method == 'canLaunch') return true;
        return null;
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/url_launcher'),
      null,
    );
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    ThemeData? theme,
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // The relay screen this screen can push must never touch the real
          // secure-storage plugin or a socket.
          relayConfigProvider.overrideWith(
            (ref) => TestableRelayConfigNotifier(
              RelayConfigService(secureStorage: InMemorySecureStorage()),
            ),
          ),
          ...overrides,
        ],
        child: MaterialApp(
          theme: theme ?? AppTheme.lightTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  ProviderContainer containerOf(WidgetTester tester) {
    return ProviderScope.containerOf(
      tester.element(find.byType(SettingsScreen)),
    );
  }

  group('language tile', () {
    testWidgets('shows system default and lets the user pick a language',
        (tester) async {
      // Arrange — no explicit locale chosen yet. "System" also labels a
      // theme segment, so the subtitle check is scoped to the language row.
      await pumpScreen(tester);
      final languageRow = find
          .ancestor(of: find.text(l10n.language), matching: find.byType(InkWell))
          .first;
      expect(
        find.descendant(
            of: languageRow, matching: find.text(l10n.systemDefault)),
        findsOneWidget,
      );

      // Act — open the picker and choose Spanish
      await tester.tap(find.text(l10n.language));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectLanguage), findsOneWidget);
      await tester.tap(find.text('Español'));
      await tester.pumpAndSettle();

      // Assert — provider updated, dialog closed, subtitle reflects it
      expect(containerOf(tester).read(localeProvider), const Locale('es'));
      expect(find.text(l10n.selectLanguage), findsNothing);
      expect(find.text('Español'), findsOneWidget);
    });

    testWidgets('a chosen language can be reset to system default',
        (tester) async {
      // Arrange — Japanese already selected
      await pumpScreen(tester, overrides: [
        localeProvider.overrideWith((ref) => const Locale('ja')),
      ]);
      expect(find.text('日本語'), findsOneWidget);

      // Act — reopen and pick the system default entry (the picker shows a
      // second copy of that label inside the dialog)
      await tester.tap(find.text(l10n.language));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.systemDefault),
        ),
      );
      await tester.pumpAndSettle();

      // Assert — scoped to the row, since a theme segment says "System" too
      expect(containerOf(tester).read(localeProvider), isNull);
      final languageRow = find
          .ancestor(of: find.text(l10n.language), matching: find.byType(InkWell))
          .first;
      expect(
        find.descendant(
            of: languageRow, matching: find.text(l10n.systemDefault)),
        findsOneWidget,
      );
    });

    testWidgets('an unknown locale code falls back to the raw code',
        (tester) async {
      // Arrange — a locale the display-name map has never heard of
      await pumpScreen(tester, overrides: [
        localeProvider.overrideWith((ref) => const Locale('fr')),
      ]);

      // Assert — the subtitle shows the code rather than nothing
      expect(find.text('fr'), findsOneWidget);
    });
  });

  group('theme tile', () {
    testWidgets('tapping a segment changes the theme mode', (tester) async {
      // Arrange — system is the default, so it is the selected segment
      await pumpScreen(tester);
      expect(containerOf(tester).read(themeModeProvider), ThemeMode.system);

      // Act
      await tester.tap(find.text(l10n.dark));
      await tester.pumpAndSettle();

      // Assert — provider changed and the choice was persisted
      expect(containerOf(tester).read(themeModeProvider), ThemeMode.dark);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('choke:theme-mode'), 'dark');
    });

    testWidgets('the selected segment shows a check instead of its icon',
        (tester) async {
      // Arrange
      await pumpScreen(tester, overrides: [
        themeModeProvider.overrideWith((ref) {
          final notifier = ThemeModeNotifier();
          notifier.hydrate(ThemeMode.light);
          return notifier;
        }),
      ]);

      // Assert — light is selected: check shown, its own icon hidden
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.light_mode_outlined), findsNothing);
      expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);
    });
  });

  group('match section', () {
    testWidgets('the duration tile opens a picker and persists the choice',
        (tester) async {
      // Arrange — default is 05:00
      await pumpScreen(tester);
      await scrollTo(tester, find.text(l10n.defaultMatchDuration));
      expect(find.text('05:00'), findsOneWidget);

      // Act — pick three minutes
      await tester.tap(find.text(l10n.defaultMatchDuration));
      await tester.pumpAndSettle();
      // The current value is marked selected inside the dialog
      expect(find.byIcon(Icons.check), findsOneWidget);
      await tester.tap(find.text('03:00'));
      await tester.pumpAndSettle();

      // Assert — dialog gone, tile and provider updated, choice saved
      expect(find.text(l10n.defaultMatchDuration), findsOneWidget);
      expect(containerOf(tester).read(matchDurationProvider), 180);
      expect(find.text('03:00'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('choke:default-match-duration'), 180);
    });

    testWidgets('the submissions tile pushes the submissions screen',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await scrollTo(tester, find.text(l10n.settingsSubmissions));

      // Act
      await tester.tap(find.text(l10n.settingsSubmissions));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(SubmissionsScreen), findsOneWidget);
    });
  });

  testWidgets('the relays tile pushes the relay management screen',
      (tester) async {
    // Arrange
    await pumpScreen(tester);
    await scrollTo(tester, find.text(l10n.relays));

    // Act
    await tester.tap(find.text(l10n.relays));
    await tester.pumpAndSettle();

    // Assert
    expect(find.byType(RelayManagementScreen), findsOneWidget);
  });

  group('about section', () {
    testWidgets('website and source rows open their URLs externally',
        (tester) async {
      // Arrange
      await pumpScreen(tester);

      // Act
      await scrollTo(tester, find.text(l10n.website));
      await tester.tap(find.text(l10n.website));
      await scrollTo(tester, find.text(l10n.sourceCode));
      await tester.tap(find.text(l10n.sourceCode));
      await tester.pumpAndSettle();

      // Assert — exactly the URLs printed on the tiles
      expect(launched, [
        'https://protolayer.io/choke',
        'https://github.com/protolayer-io/choke',
      ]);
    });

    testWidgets('the license row opens a dialog that can be closed',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await scrollTo(tester, find.text(l10n.licenseLabel));

      // Act — the row and the dialog can share the word "License", so the
      // dialog itself is what gets asserted
      await tester.tap(find.text(l10n.licenseLabel));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text(l10n.licenseTitle),
        ),
        findsOneWidget,
      );

      // Act — close it
      await tester.tap(find.text(l10n.close));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(AlertDialog), findsNothing);
    });
  });

  group('footer', () {
    testWidgets('shows the version from the real package info provider',
        (tester) async {
      // Arrange + Act — no provider override: this exercises the provider's
      // own PackageInfo.fromPlatform call against the mocked plugin values
      await pumpScreen(tester);
      await scrollTo(tester, find.text('v9.9.9'));

      // Assert
      expect(find.text('v9.9.9'), findsOneWidget);
    });

    testWidgets('the credit line and the belt both link to protolayer.io',
        (tester) async {
      // Arrange
      await pumpScreen(tester);
      await scrollTo(tester, find.text(l10n.builtBy('ProtoLayer')));

      // Act — tap the text link, then the belt badge
      await tester.tap(find.text(l10n.builtBy('ProtoLayer')));
      await tester.tap(find.byType(Image), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Assert
      expect(launched,
          ['https://protolayer.io', 'https://protolayer.io']);
    });

    testWidgets('dark theme gives the belt a lightened backdrop',
        (tester) async {
      // Arrange + Act — the belt is near-black and needs the tinted tile to
      // read against the ink scaffold; light theme deliberately has none
      await pumpScreen(tester, theme: AppTheme.darkTheme);
      await scrollTo(tester, find.byType(Image));

      // Assert — the container directly around the image is decorated
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(Container))
            .first,
      );
      expect(container.decoration, isNotNull);
    });

    testWidgets('light theme leaves the belt without a backdrop',
        (tester) async {
      // Arrange + Act
      await pumpScreen(tester, theme: AppTheme.lightTheme);
      await scrollTo(tester, find.byType(Image));

      // Assert
      final container = tester.widget<Container>(
        find
            .ancestor(of: find.byType(Image), matching: find.byType(Container))
            .first,
      );
      expect(container.decoration, isNull);
    });
  });
}
