import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/features/match/models/submission_catalog.dart';
import 'package:choke/features/match/providers/submissions_provider.dart';
import 'package:choke/features/settings/screens/submissions_screen.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/shared/theme/app_theme.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    // The notifier persists through SharedPreferences, a plugin that does not
    // exist in a widget test unless it is mocked.
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    SubmissionsState? initial,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (initial != null)
            submissionsProvider
                .overrideWith((ref) => SubmissionsNotifier(initial)),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('en'),
          home: const SubmissionsScreen(),
        ),
      ),
    );
  }

  SubmissionsNotifier notifierOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(SubmissionsScreen)),
    );
    return container.read(submissionsProvider.notifier);
  }

  testWidgets('renders the catalog under its localized names', (tester) async {
    // Arrange + Act
    await pumpScreen(tester);

    // Assert — the first catalog entries are visible, localized, with a
    // remove button each; restore is absent because nothing is hidden
    expect(find.text(l10n.subArmbar), findsOneWidget);
    expect(find.text(l10n.subRearNakedChoke), findsOneWidget);
    expect(find.byIcon(Icons.close), findsWidgets);
    expect(find.text(l10n.submissionsRestore), findsNothing);
  });

  testWidgets('removing a technique hides it and offers restore',
      (tester) async {
    // Arrange
    await pumpScreen(tester);

    // Act — remove the armbar row via its close button
    await tester.tap(
      find.descendant(
        of: find.widgetWithText(ListTile, l10n.subArmbar),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pump();

    // Assert — gone from the list, restore appears in the app bar
    expect(find.text(l10n.subArmbar), findsNothing);
    expect(find.text(l10n.submissionsRestore), findsOneWidget);

    // Assert — the removal reached disk, as the next launch will see it
    await notifierOf(tester).saved;
    final persisted = await SubmissionsNotifier.loadSaved();
    expect(persisted.hidden, contains('armbar'));
  });

  testWidgets('restore brings every hidden default back', (tester) async {
    // Arrange — armbar already hidden
    await pumpScreen(
      tester,
      initial: const SubmissionsState(hidden: {'armbar'}),
    );
    expect(find.text(l10n.subArmbar), findsNothing);

    // Act
    await tester.tap(find.text(l10n.submissionsRestore));
    await tester.pump();

    // Assert — armbar is back and the restore action retired itself
    expect(find.text(l10n.subArmbar), findsOneWidget);
    expect(find.text(l10n.submissionsRestore), findsNothing);
  });

  testWidgets('hiding the whole catalog shows the empty state', (tester) async {
    // Arrange — everything hidden, nothing custom
    await pumpScreen(
      tester,
      initial: SubmissionsState(hidden: defaultSubmissions.toSet()),
    );

    // Assert
    expect(find.text(l10n.submissionsEmpty), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  group('adding a submission', () {
    testWidgets('a typed technique is added, shown, and persisted',
        (tester) async {
      // Arrange
      await pumpScreen(tester);

      // Act — FAB, type, confirm
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Baratoplata');
      await tester.tap(find.text(l10n.outcomeConfirm));
      await tester.pumpAndSettle();

      // Assert — custom entries go to the end of the list
      await tester.scrollUntilVisible(find.text('Baratoplata'), 200);
      expect(find.text('Baratoplata'), findsOneWidget);

      // Assert — persisted verbatim: that exact string is what gets published
      await notifierOf(tester).saved;
      final persisted = await SubmissionsNotifier.loadSaved();
      expect(persisted.custom, contains('Baratoplata'));
    });

    testWidgets('submitting from the keyboard confirms the dialog',
        (tester) async {
      // Arrange
      await pumpScreen(tester);

      // Act — type and hit the keyboard's done action instead of the button
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Twister');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Assert
      await tester.scrollUntilVisible(find.text('Twister'), 200);
      expect(find.text('Twister'), findsOneWidget);
    });

    testWidgets('a known technique is refused as a duplicate with a snackbar',
        (tester) async {
      // Arrange — 'Armbar' is the localized name of catalog id `armbar`,
      // which is already visible; canonicalize maps it back before adding
      await pumpScreen(tester);

      // Act
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Armbar');
      await tester.tap(find.text(l10n.outcomeConfirm));
      await tester.pumpAndSettle();

      // Assert
      expect(find.text(l10n.submissionsDuplicate), findsOneWidget);
    });

    testWidgets('typing back a removed default resurrects the catalog entry',
        (tester) async {
      // Arrange — armbar was removed earlier
      await pumpScreen(
        tester,
        initial: const SubmissionsState(hidden: {'armbar'}),
      );

      // Act — the referee types its display name back in
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'armbar');
      await tester.tap(find.text(l10n.outcomeConfirm));
      await tester.pumpAndSettle();

      // Assert — the canonical entry is back; no second spelling was created
      expect(find.text(l10n.subArmbar), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SubmissionsScreen)),
      );
      expect(container.read(submissionsProvider).custom, isEmpty);
      expect(container.read(submissionsProvider).hidden, isEmpty);
    });

    testWidgets('cancelling the dialog adds nothing', (tester) async {
      // Arrange
      await pumpScreen(tester);
      final before = tester.widgetList(find.byType(ListTile)).length;

      // Act
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Never mind');
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();

      // Assert
      expect(find.byType(ListTile), findsNWidgets(before));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SubmissionsScreen)),
      );
      expect(container.read(submissionsProvider).custom, isEmpty);
    });

    testWidgets('confirming an empty name adds nothing', (tester) async {
      // Arrange
      await pumpScreen(tester);

      // Act — confirm with only whitespace typed
      await tester.tap(find.text(l10n.submissionsAdd));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text(l10n.outcomeConfirm));
      await tester.pumpAndSettle();

      // Assert — no new row, no duplicate complaint either
      final container = ProviderScope.containerOf(
        tester.element(find.byType(SubmissionsScreen)),
      );
      expect(container.read(submissionsProvider).custom, isEmpty);
      expect(find.text(l10n.submissionsDuplicate), findsNothing);
    });
  });
}
