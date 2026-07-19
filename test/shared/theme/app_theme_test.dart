import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:choke/shared/theme/app_theme.dart';

void main() {
  group('ChokeTokens.copyWith', () {
    test('returns an identical set of tokens when nothing is overridden', () {
      // Arrange
      const original = ChokeTokens.dark;

      // Act — every argument null exercises every `?? this.x` fallback
      final copy = original.copyWith();

      // Assert
      expect(copy.card, original.card);
      expect(copy.cardBorder, original.cardBorder);
      expect(copy.field, original.field);
      expect(copy.muted, original.muted);
      expect(copy.faint, original.faint);
      expect(copy.accent, original.accent);
      expect(copy.sectionTint, original.sectionTint);
      expect(copy.gradTop, original.gradTop);
      expect(copy.gradBottom, original.gradBottom);
      expect(copy.onGrad, original.onGrad);
      expect(copy.statusFinishedFg, original.statusFinishedFg);
      expect(copy.statusFinishedBg, original.statusFinishedBg);
      expect(copy.statusCanceledFg, original.statusCanceledFg);
      expect(copy.statusCanceledBg, original.statusCanceledBg);
      expect(copy.goldFg, original.goldFg);
      expect(copy.dangerFg, original.dangerFg);
      expect(copy.keyFg, original.keyFg);
      expect(copy.strongBorder, original.strongBorder);
    });

    test('replaces every field that is overridden', () {
      // Arrange
      const original = ChokeTokens.dark;
      const replacement = Color(0xFF123456);

      // Act — every argument set exercises the other side of each `??`
      final copy = original.copyWith(
        card: replacement,
        cardBorder: replacement,
        field: replacement,
        muted: replacement,
        faint: replacement,
        accent: replacement,
        sectionTint: replacement,
        gradTop: replacement,
        gradBottom: replacement,
        onGrad: replacement,
        statusFinishedFg: replacement,
        statusFinishedBg: replacement,
        statusCanceledFg: replacement,
        statusCanceledBg: replacement,
        goldFg: replacement,
        dangerFg: replacement,
        keyFg: replacement,
        strongBorder: replacement,
      );

      // Assert — a sample from start, middle and end of the field list
      expect(copy.card, replacement);
      expect(copy.statusCanceledBg, replacement);
      expect(copy.strongBorder, replacement);
      expect(copy.card, isNot(original.card));
    });
  });

  group('ChokeTokens.lerp', () {
    test('returns itself when the other side is not ChokeTokens', () {
      // Arrange
      const tokens = ChokeTokens.dark;

      // Act — the theme system may hand any extension type here
      final result = tokens.lerp(null, 0.5);

      // Assert
      expect(identical(result, tokens), isTrue);
    });

    test('interpolates every color between light and dark', () {
      // Arrange
      const from = ChokeTokens.light;
      const to = ChokeTokens.dark;

      // Act
      final atStart = from.lerp(to, 0.0);
      final atEnd = from.lerp(to, 1.0);

      // Assert — t=0 lands on light, t=1 on dark, for a sample of fields
      expect(atStart.card, from.card);
      expect(atStart.keyFg, from.keyFg);
      expect(atEnd.card, to.card);
      expect(atEnd.strongBorder, to.strongBorder);
    });
  });

  test('gradient runs from gradTop to gradBottom, top to bottom', () {
    // Arrange
    const tokens = ChokeTokens.dark;

    // Act
    final gradient = tokens.gradient;

    // Assert
    expect(gradient.begin, Alignment.topCenter);
    expect(gradient.end, Alignment.bottomCenter);
    expect(gradient.colors, [tokens.gradTop, tokens.gradBottom]);
  });

  group('ChokeTokens.of', () {
    testWidgets('reads the tokens registered as a theme extension',
        (tester) async {
      // Arrange
      late ChokeTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              tokens = ChokeTokens.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Assert
      expect(identical(tokens, ChokeTokens.dark), isTrue);
    });

    testWidgets('falls back to dark tokens under a dark theme without them',
        (tester) async {
      // Arrange — a theme that never registered the extension
      late ChokeTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Builder(
            builder: (context) {
              tokens = ChokeTokens.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Assert
      expect(identical(tokens, ChokeTokens.dark), isTrue);
    });

    testWidgets('falls back to light tokens under a light theme without them',
        (tester) async {
      // Arrange
      late ChokeTokens tokens;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: Brightness.light),
          home: Builder(
            builder: (context) {
              tokens = ChokeTokens.of(context);
              return const SizedBox();
            },
          ),
        ),
      );

      // Assert
      expect(identical(tokens, ChokeTokens.light), isTrue);
    });
  });

  group('AppTheme', () {
    test('darkTheme is a Material 3 dark theme carrying the dark tokens', () {
      // Act
      final theme = AppTheme.darkTheme;

      // Assert
      expect(theme.brightness, Brightness.dark);
      expect(theme.useMaterial3, isTrue);
      expect(theme.extension<ChokeTokens>(), ChokeTokens.dark);
    });

    test('lightTheme is a Material 3 light theme carrying the light tokens',
        () {
      // Act
      final theme = AppTheme.lightTheme;

      // Assert
      expect(theme.brightness, Brightness.light);
      expect(theme.extension<ChokeTokens>(), ChokeTokens.light);
    });

    test('championshipTheme restyles the dark theme in gold on navy', () {
      // Act
      final theme = AppTheme.championshipTheme;

      // Assert
      expect(theme.colorScheme.primary, BJJColors.gold);
      expect(theme.colorScheme.surface, BJJColors.navy);
      expect(theme.scaffoldBackgroundColor, BJJColors.navy);
    });
  });
}
