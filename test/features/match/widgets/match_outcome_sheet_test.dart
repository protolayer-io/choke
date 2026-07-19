import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/models/match_outcome.dart';
import 'package:choke/features/match/models/submission_catalog.dart';
import 'package:choke/features/match/providers/submissions_provider.dart';
import 'package:choke/features/match/widgets/match_outcome_sheet.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/shared/theme/app_theme.dart';

Match _match() {
  return Match(
    id: 'abcd',
    status: MatchStatus.inProgress,
    startAt: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    duration: 300,
    f1Name: 'Pana',
    f2Name: 'Buchecha',
    f1Color: '#1BA34E',
    f2Color: '#F5B800',
  );
}

void main() {
  late AppLocalizations l10n;
  Future<MatchOutcome?>? result;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    result = null;
  });

  /// Pump a host page whose button opens the sheet, then open it.
  Future<void> pumpAndOpen(
    WidgetTester tester, {
    MatchOutcome? suggested,
    List<Override> overrides = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    result = showMatchOutcomeSheet(
                      context,
                      match: _match(),
                      suggested: suggested,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('the suggested outcome', () {
    testWidgets('a suggested disqualification is one tap to confirm',
        (tester) async {
      // Arrange — Pana has four penalties on the board; the scoreboard
      // already implies the DQ, so it comes back pre-selected
      const suggested = MatchOutcome.disqualifying(
        MatchWinner.f2,
        DqReason.accumulatedPenalties,
      );
      await pumpAndOpen(tester, suggested: suggested);

      // Act — one tap on what the scoreboard already says
      final label = '${l10n.outcomeWinsBy('Buchecha')} · ${l10n.outcomeDq}';
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();

      // Assert — offered, and accepted verbatim
      final outcome = await result;
      expect(outcome?.winner, MatchWinner.f2);
      expect(outcome?.method, MatchMethod.dq);
      expect(outcome?.dqReason, DqReason.accumulatedPenalties);
    });

    testWidgets('an advantages lead reads as a win by advantages',
        (tester) async {
      // Arrange — points level, Buchecha ahead on advantages
      const suggested = MatchOutcome.onScoreboard(
        MatchWinner.f2,
        MatchMethod.advantages,
      );

      // Act
      await pumpAndOpen(tester, suggested: suggested);

      // Assert
      expect(
        find.text(
            '${l10n.outcomeWinsBy('Buchecha')} · ${l10n.outcomeAdvantages}'),
        findsOneWidget,
      );
    });

    testWidgets('every method the sheet can be handed renders a label',
        (tester) async {
      // The sheet describes whatever suggestion it is given: a caller
      // wiring a new suggestion source must never produce a blank button.
      final cases = <MatchOutcome, String>{
        const MatchOutcome.submissionBy(MatchWinner.f1):
            '${l10n.outcomeWinsBy('Pana')} · ${l10n.outcomeSubmission}',
        const MatchOutcome.decision(MatchWinner.f1):
            '${l10n.outcomeWinsBy('Pana')} · ${l10n.outcomeDecision}',
        const MatchOutcome.forfeitBy(MatchWinner.f1):
            '${l10n.outcomeWinsBy('Pana')} · ${l10n.outcomeForfeit}',
      };

      for (final entry in cases.entries) {
        // Arrange + Act
        await pumpAndOpen(tester, suggested: entry.key);

        // Assert
        expect(find.text(entry.value), findsOneWidget);

        // Close the sheet before the next round
        await tester.tapAt(const Offset(10, 10));
        await tester.pumpAndSettle();
      }

      // A suggested draw has no winner to name, so the label is the
      // method alone — once as the offer, once as the secondary action.
      await pumpAndOpen(tester, suggested: const MatchOutcome.draw());
      expect(find.text(l10n.outcomeDraw), findsNWidgets(2));
    });
  });

  group('the rarer endings', () {
    testWidgets('a draw is recorded with no winner', (tester) async {
      // Arrange — nothing suggested: the scoreboard is level
      await pumpAndOpen(tester);

      // Act
      await tester.tap(find.text(l10n.outcomeDraw));
      await tester.pumpAndSettle();

      // Assert — a draw is a method with no winner, by construction
      final outcome = await result;
      expect(outcome?.method, MatchMethod.draw);
      expect(outcome?.winner, isNull);
    });

    testWidgets('a forfeit asks for the winner, in their own colour',
        (tester) async {
      // Arrange
      await pumpAndOpen(tester);

      // Act — forfeit, then the fighter who stays standing
      await tester.tap(find.text(l10n.outcomeForfeit));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pana'));
      await tester.pumpAndSettle();

      // Assert
      final outcome = await result;
      expect(outcome?.method, MatchMethod.forfeit);
      expect(outcome?.winner, MatchWinner.f1);
    });

    testWidgets('a referee decision names the fighter they chose',
        (tester) async {
      // Arrange
      await pumpAndOpen(tester);

      // Act
      await tester.tap(find.text(l10n.outcomeDecision));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Buchecha'));
      await tester.pumpAndSettle();

      // Assert
      final outcome = await result;
      expect(outcome?.method, MatchMethod.decision);
      expect(outcome?.winner, MatchWinner.f2);
    });

    testWidgets('dismissing the fighter picker leaves the sheet open',
        (tester) async {
      // Arrange — the referee tapped Forfeit by mistake
      await pumpAndOpen(tester);
      await tester.tap(find.text(l10n.outcomeForfeit));
      await tester.pumpAndSettle();

      // Act — back out of the fighter question
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert — no half-answered outcome: the sheet is still asking
      expect(find.text(l10n.outcomeTitle), findsOneWidget);
    });
  });

  group('disqualification', () {
    testWidgets('winner, category and a typed detail travel together',
        (tester) async {
      // Arrange
      await pumpAndOpen(tester);

      // Act — the winner (never the loser: no thinking in negatives), the
      // category, then what actually happened — submitted from the keyboard
      await tester.tap(find.text(l10n.outcomeDq));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pana'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.outcomeDqTechnical));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'knee reap');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Assert — the enumerated category and the free-text detail both
      // arrive: rulesets differ, so what happened stays free text
      final outcome = await result;
      expect(outcome?.method, MatchMethod.dq);
      expect(outcome?.winner, MatchWinner.f1);
      expect(outcome?.dqReason, DqReason.technicalFoul);
      expect(outcome?.dqDetail, 'knee reap');
    });

    testWidgets('the detail is skippable — a DQ without prose still ends it',
        (tester) async {
      // Arrange
      await pumpAndOpen(tester);

      // Act
      await tester.tap(find.text(l10n.outcomeDq));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Buchecha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.outcomeDqDisciplinary));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.skip));
      await tester.pumpAndSettle();

      // Assert — no detail is a valid answer, not a blocked flow
      final outcome = await result;
      expect(outcome?.method, MatchMethod.dq);
      expect(outcome?.dqReason, DqReason.disciplinaryFoul);
      expect(outcome?.dqDetail, isNull);
    });
  });

  group('an emptied submission catalog', () {
    testWidgets('says so instead of showing a blank picker', (tester) async {
      // Arrange — the referee hid every built-in technique in settings
      await pumpAndOpen(
        tester,
        overrides: [
          submissionsProvider.overrideWith(
            (ref) => SubmissionsNotifier(
              SubmissionsState(hidden: defaultSubmissions.toSet()),
            ),
          ),
        ],
      );

      // Act — a submission still has to be recordable
      await tester.tap(find.text(l10n.outcomeSubmission));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, 'Pana'));
      await tester.pumpAndSettle();

      // Assert — an honest empty state, with the escape hatches pinned
      expect(find.text(l10n.submissionsEmpty), findsOneWidget);
      expect(find.text(l10n.outcomeSubmissionOther), findsOneWidget);

      // Act — skipping the technique still records the submission
      await tester.tap(find.text(l10n.skip));
      await tester.pumpAndSettle();

      // Assert
      final outcome = await result;
      expect(outcome?.method, MatchMethod.submission);
      expect(outcome?.winner, MatchWinner.f1);
      expect(outcome?.submission, isNull);
    });
  });
}
