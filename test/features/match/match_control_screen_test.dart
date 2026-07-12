import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/features/match/match_control_screen.dart';
import 'package:choke/features/match/models/match.dart';
import 'package:choke/features/match/providers/match_control_provider.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import 'package:choke/services/key_management/key_manager.dart';
import 'package:choke/services/nostr/nostr_service.dart';
import 'package:choke/shared/theme/app_theme.dart';

/// Fake NostrService that skips relay publishing entirely
class _FakeNostrService extends NostrService {
  _FakeNostrService() : super(KeyManager());

  @override
  Future<void> publishAddressableEvent({
    required String dTag,
    required String content,
    List<List<String>> additionalTags = const [],
  }) async {}
}

Match _runningMatch() {
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
  late MatchControlNotifier notifier;

  Future<void> pumpScreen(WidgetTester tester, Match match) async {
    // Landscape phone viewport
    tester.view.physicalSize = const Size(1600, 740);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    notifier = MatchControlNotifier(match, _FakeNostrService());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matchControlProvider.overrideWith((ref) => notifier),
        ],
        child: MaterialApp(
          theme: AppTheme.darkTheme,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MatchControlScreen(match: match),
        ),
      ),
    );
  }

  testWidgets('shows both fighters with their own scoring rails',
      (tester) async {
    // Arrange + Act
    await pumpScreen(tester, _runningMatch());

    // Assert
    expect(find.text('Pana'), findsOneWidget);
    expect(find.text('Buchecha'), findsOneWidget);
    expect(find.text('+2'), findsNWidgets(2));
    expect(find.text('+3'), findsNWidgets(2));
    expect(find.text('+4'), findsNWidgets(2));
  });

  testWidgets('tapping +2 on fighter 1 rail adds two points', (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());

    // Act
    await tester.tap(find.text('+2').first);
    await tester.pump();

    // Assert
    expect(notifier.state.match.f1Score, 2);
    expect(notifier.state.match.f2Score, 0);
  });

  testWidgets('holding +2 on fighter 1 rail subtracts two points',
      (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());
    await tester.tap(find.text('+2').first);
    await tester.tap(find.text('+2').first);
    await tester.pump();
    expect(notifier.state.match.f1Score, 4);

    // Act: press and hold for over a second
    final gesture =
        await tester.startGesture(tester.getCenter(find.text('+2').first));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pump();

    // Assert
    expect(notifier.state.match.f1Score, 2);
  });

  testWidgets('holding finish button ends the match', (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));
    final finishLabel = '${l10n.finish} · ${l10n.holdHint}';

    // Act
    final gesture =
        await tester.startGesture(tester.getCenter(find.text(finishLabel)));
    await tester.pump(); // first ticker frame (t = 0)
    await tester.pump(const Duration(milliseconds: 1100));
    await gesture.up();
    await tester.pump();

    // Assert
    expect(notifier.state.match.status, MatchStatus.finished);
    expect(
      find.text('${l10n.matchFinished} · ${l10n.matchReadOnly}'),
      findsOneWidget,
    );
  });

  testWidgets('waiting match shows start overlay', (tester) async {
    // Arrange
    final waiting = _runningMatch().copyWith(
      status: MatchStatus.waiting,
      startAt: null,
    );

    // Act
    await pumpScreen(tester, waiting);
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Assert
    expect(find.text(l10n.startMatch), findsOneWidget);
  });

  testWidgets('running match offers a pause button next to the clock',
      (tester) async {
    // Arrange + Act
    await pumpScreen(tester, _runningMatch());

    // Assert
    expect(find.byIcon(Icons.pause), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsNothing);
  });

  testWidgets('tapping pause stops the clock and offers resume',
      (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());
    final l10n = await AppLocalizations.delegate.load(const Locale('en'));

    // Act
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    // Assert
    expect(notifier.state.isPaused, isTrue);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    expect(find.text(l10n.statusPaused), findsOneWidget);
  });

  testWidgets('tapping resume restarts the clock', (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    // Act
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();

    // Assert
    expect(notifier.state.isPaused, isFalse);
    expect(find.byIcon(Icons.pause), findsOneWidget);
  });

  testWidgets('a waiting match has no pause button', (tester) async {
    // Arrange
    final waiting = _runningMatch().copyWith(
      status: MatchStatus.waiting,
      startAt: null,
    );

    // Act
    await pumpScreen(tester, waiting);

    // Assert
    expect(find.byIcon(Icons.pause), findsNothing);
  });

  testWidgets('scoring rails stay live while paused', (tester) async {
    // Arrange
    await pumpScreen(tester, _runningMatch());
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();

    // Act — the referee awards a takedown during the stoppage
    await tester.tap(find.text('+2').first);
    await tester.pump();

    // Assert
    expect(notifier.state.match.f1Score, 2);
  });
}
