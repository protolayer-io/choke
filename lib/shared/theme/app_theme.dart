import 'package:flutter/material.dart';

/// BJJ Brand Colors - Style Guide
///
/// A powerful color palette extracted from Brazilian Jiu-Jitsu imagery.
/// Four essential colors that embody discipline, growth, achievement, and purity.

class BJJColors {
  // Navy Black - The Foundation
  /// Deep, authoritative background representing discipline and mastery.
  /// Usage: Backgrounds, headers, footers, overlays
  static const Color navy = Color(0xFF121A2E);
  static const Color navyDark = Color(0xFF0D1117);

  // Refreshed dark palette (design turn 2)
  /// App background in dark mode
  static const Color ink = Color(0xFF090E1A);

  /// Card surface in dark mode
  static const Color inkCard = Color(0xFF111A2C);

  /// Inner field surface in dark mode (inputs, segmented tracks)
  static const Color inkField = Color(0xFF0B1322);

  // BJJ Green - The Growth
  /// Vibrant green symbolizing growth, progress, and the journey through belt ranks.
  /// Usage: Primary actions, CTAs, success states, highlights
  static const Color green = Color(0xFF1BA34E);
  static const Color greenLight = Color(0xFF2DC45C);
  static const Color greenDark = Color(0xFF15823E);

  /// Bright accent green from the refreshed dark design
  static const Color greenBright = Color(0xFF2FD46C);

  /// Bottom stop of the primary button gradient
  static const Color greenGradEnd = Color(0xFF1CA653);

  /// Text/icon color on top of the green gradient
  static const Color onGreenGrad = Color(0xFF062012);

  // Championship Gold - The Achievement
  /// Bold gold representing achievement, excellence, and championship spirit.
  /// Usage: Accents, badges, awards, special highlights
  static const Color gold = Color(0xFFF5B800);
  static const Color goldLight = Color(0xFFFFCC33);
  static const Color goldDark = Color(0xFFC49400);

  /// Refreshed gold accent from the design
  static const Color goldBright = Color(0xFFF5C518);

  // Pure White - The Clarity
  /// Clean white for clarity, purity, and the traditional white gi.
  /// Usage: Text on dark backgrounds, cards, clean spaces
  static const Color white = Color(0xFFFFFFFF);
  static const Color offWhite = Color(0xFFF5F5F5);

  // Utility colors
  static const Color grey = Color(0xFF8B949E);
  static const Color greyDark = Color(0xFF484F58);
  static const Color greyLight = Color(0xFFC9D1D9);

  // Semantic colors
  static const Color error = Color(0xFFD32F2F);
  static const Color warning = gold;
  static const Color success = green;
  static const Color info = Color(0xFF2196F3);

  /// Refreshed red accent from the design
  static const Color redBright = Color(0xFFF0554E);

  // Extended palette for fighter color selection
  static const Color red = Color(0xFFD32F2F);
  static const Color blue = Color(0xFF2196F3);
  static const Color purple = Color(0xFF9C27B0);
  static const Color orange = Color(0xFFFF9800);

  /// Pre-defined fighter color palette for match creation
  static const List<Color> fighterPalette = [
    green,
    gold,
    red,
    blue,
    white,
    purple,
    orange,
    navy,
  ];
}

/// Design tokens from the refreshed design (turn 2), themed for both
/// light and dark mode. Access via [ChokeTokens.of].
class ChokeTokens extends ThemeExtension<ChokeTokens> {
  /// Card surface color
  final Color card;

  /// Subtle card border
  final Color cardBorder;

  /// Inner field surface (inputs, segmented tracks) — darker than card
  final Color field;

  /// Secondary text
  final Color muted;

  /// Tertiary/faint text
  final Color faint;

  /// Bright accent (green)
  final Color accent;

  /// Section title tint (Ajustes-style headers)
  final Color sectionTint;

  /// Primary button gradient stops
  final Color gradTop;
  final Color gradBottom;

  /// Foreground on the gradient
  final Color onGrad;

  /// "Finalizado" status chip
  final Color statusFinishedFg;
  final Color statusFinishedBg;

  /// "Cancelado" status chip
  final Color statusCanceledFg;
  final Color statusCanceledBg;

  /// Gold accent readable on this theme's card
  final Color goldFg;

  /// Danger/red accent readable on this theme's card
  final Color dangerFg;

  const ChokeTokens({
    required this.card,
    required this.cardBorder,
    required this.field,
    required this.muted,
    required this.faint,
    required this.accent,
    required this.sectionTint,
    required this.gradTop,
    required this.gradBottom,
    required this.onGrad,
    required this.statusFinishedFg,
    required this.statusFinishedBg,
    required this.statusCanceledFg,
    required this.statusCanceledBg,
    required this.goldFg,
    required this.dangerFg,
  });

  /// Primary button gradient
  LinearGradient get gradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [gradTop, gradBottom],
      );

  static ChokeTokens of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<ChokeTokens>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  static const dark = ChokeTokens(
    card: BJJColors.inkCard,
    cardBorder: Color(0x0FFFFFFF),
    field: BJJColors.inkField,
    muted: Color(0x80E8EEF7),
    faint: Color(0x73E8EEF7),
    accent: BJJColors.greenBright,
    sectionTint: Color(0xFF4FCF83),
    gradTop: BJJColors.greenBright,
    gradBottom: BJJColors.greenGradEnd,
    onGrad: BJJColors.onGreenGrad,
    statusFinishedFg: Color(0xFF7FB0FF),
    statusFinishedBg: Color(0x264C8DFF),
    statusCanceledFg: Color(0xFFF0817B),
    statusCanceledBg: Color(0x26F0554E),
    goldFg: BJJColors.goldBright,
    dangerFg: BJJColors.redBright,
  );

  static const light = ChokeTokens(
    card: BJJColors.white,
    cardBorder: Color(0x14121A2E),
    field: Color(0xFFEDF1F6),
    muted: Color(0x99121A2E),
    faint: Color(0x6B121A2E),
    accent: Color(0xFF17A254),
    sectionTint: Color(0xFF148746),
    gradTop: BJJColors.greenBright,
    gradBottom: BJJColors.greenGradEnd,
    onGrad: BJJColors.onGreenGrad,
    statusFinishedFg: Color(0xFF3466CC),
    statusFinishedBg: Color(0x244C8DFF),
    statusCanceledFg: Color(0xFFC2423B),
    statusCanceledBg: Color(0x1FF0554E),
    goldFg: Color(0xFFA07E00),
    dangerFg: Color(0xFFC2423B),
  );

  @override
  ChokeTokens copyWith({
    Color? card,
    Color? cardBorder,
    Color? field,
    Color? muted,
    Color? faint,
    Color? accent,
    Color? sectionTint,
    Color? gradTop,
    Color? gradBottom,
    Color? onGrad,
    Color? statusFinishedFg,
    Color? statusFinishedBg,
    Color? statusCanceledFg,
    Color? statusCanceledBg,
    Color? goldFg,
    Color? dangerFg,
  }) {
    return ChokeTokens(
      card: card ?? this.card,
      cardBorder: cardBorder ?? this.cardBorder,
      field: field ?? this.field,
      muted: muted ?? this.muted,
      faint: faint ?? this.faint,
      accent: accent ?? this.accent,
      sectionTint: sectionTint ?? this.sectionTint,
      gradTop: gradTop ?? this.gradTop,
      gradBottom: gradBottom ?? this.gradBottom,
      onGrad: onGrad ?? this.onGrad,
      statusFinishedFg: statusFinishedFg ?? this.statusFinishedFg,
      statusFinishedBg: statusFinishedBg ?? this.statusFinishedBg,
      statusCanceledFg: statusCanceledFg ?? this.statusCanceledFg,
      statusCanceledBg: statusCanceledBg ?? this.statusCanceledBg,
      goldFg: goldFg ?? this.goldFg,
      dangerFg: dangerFg ?? this.dangerFg,
    );
  }

  @override
  ChokeTokens lerp(ThemeExtension<ChokeTokens>? other, double t) {
    if (other is! ChokeTokens) return this;
    return ChokeTokens(
      card: Color.lerp(card, other.card, t)!,
      cardBorder: Color.lerp(cardBorder, other.cardBorder, t)!,
      field: Color.lerp(field, other.field, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      faint: Color.lerp(faint, other.faint, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      sectionTint: Color.lerp(sectionTint, other.sectionTint, t)!,
      gradTop: Color.lerp(gradTop, other.gradTop, t)!,
      gradBottom: Color.lerp(gradBottom, other.gradBottom, t)!,
      onGrad: Color.lerp(onGrad, other.onGrad, t)!,
      statusFinishedFg:
          Color.lerp(statusFinishedFg, other.statusFinishedFg, t)!,
      statusFinishedBg:
          Color.lerp(statusFinishedBg, other.statusFinishedBg, t)!,
      statusCanceledFg:
          Color.lerp(statusCanceledFg, other.statusCanceledFg, t)!,
      statusCanceledBg:
          Color.lerp(statusCanceledBg, other.statusCanceledBg, t)!,
      goldFg: Color.lerp(goldFg, other.goldFg, t)!,
      dangerFg: Color.lerp(dangerFg, other.dangerFg, t)!,
    );
  }
}

/// App Theme Configuration
class AppTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: BJJColors.ink,
      extensions: const [ChokeTokens.dark],
      colorScheme: const ColorScheme.dark(
        primary: BJJColors.greenBright,
        onPrimary: BJJColors.onGreenGrad,
        secondary: BJJColors.goldBright,
        onSecondary: BJJColors.navy,
        surface: BJJColors.inkCard,
        onSurface: Color(0xFFE8EEF7),
        error: BJJColors.redBright,
        onError: BJJColors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BJJColors.ink,
        foregroundColor: Color(0xFFE8EEF7),
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BJJColors.greenBright,
          foregroundColor: BJJColors.onGreenGrad,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BJJColors.greenBright,
          side: const BorderSide(color: BJJColors.greenBright, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BJJColors.goldBright),
      ),
      cardTheme: CardThemeData(
        color: BJJColors.inkCard,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Color(0x0FFFFFFF)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: BJJColors.inkField,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0x14FFFFFF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: BJJColors.greenBright, width: 2),
        ),
        labelStyle: const TextStyle(color: BJJColors.grey),
        hintStyle: const TextStyle(color: Color(0x66E8EEF7)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BJJColors.inkField,
        selectedItemColor: BJJColors.greenBright,
        unselectedItemColor: Color(0x8CE8EEF7),
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BJJColors.greenBright,
        foregroundColor: BJJColors.onGreenGrad,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: Color(0xFFE8EEF7),
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: Color(0xFFE8EEF7),
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EEF7),
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Color(0xFFE8EEF7),
        ),
        bodyLarge: TextStyle(fontSize: 16, color: Color(0xFFE8EEF7)),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xB3E8EEF7)),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: BJJColors.greenBright,
        ),
      ),
    );
  }

  /// Light theme — light backgrounds, dark text, same BJJ accent colors
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF3F5F8),
      extensions: const [ChokeTokens.light],
      colorScheme: const ColorScheme.light(
        primary: BJJColors.green,
        onPrimary: BJJColors.white,
        secondary: BJJColors.gold,
        onSecondary: BJJColors.navy,
        surface: BJJColors.white,
        onSurface: BJJColors.navy,
        error: BJJColors.error,
        onError: BJJColors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF3F5F8),
        foregroundColor: BJJColors.navy,
        elevation: 0,
        centerTitle: true,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: BJJColors.green,
          foregroundColor: BJJColors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BJJColors.green,
          side: const BorderSide(color: BJJColors.green, width: 2),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: BJJColors.goldDark),
      ),
      cardTheme: CardThemeData(
        color: BJJColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
          side: const BorderSide(color: Color(0x14121A2E)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFEDF1F6),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0x1F121A2E)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0x1F121A2E)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: BJJColors.green, width: 2),
        ),
        labelStyle: const TextStyle(color: BJJColors.grey),
        hintStyle: const TextStyle(color: Color(0x66121A2E)),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: BJJColors.white,
        selectedItemColor: BJJColors.green,
        unselectedItemColor: BJJColors.grey,
        type: BottomNavigationBarType.fixed,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: BJJColors.green,
        foregroundColor: BJJColors.white,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.bold,
          color: BJJColors.navy,
        ),
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: BJJColors.navy,
        ),
        headlineSmall: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: BJJColors.navy,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: BJJColors.navy,
        ),
        bodyLarge: TextStyle(fontSize: 16, color: BJJColors.navy),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xB3121A2E)),
        labelLarge: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF148746),
        ),
      ),
    );
  }

  /// Championship theme variant - for special screens
  static ThemeData get championshipTheme {
    return darkTheme.copyWith(
      colorScheme: const ColorScheme.dark(
        primary: BJJColors.gold,
        onPrimary: BJJColors.navy,
        secondary: BJJColors.white,
        onSecondary: BJJColors.navy,
        surface: BJJColors.navy,
        onSurface: BJJColors.gold,
      ),
      scaffoldBackgroundColor: BJJColors.navy,
    );
  }
}
