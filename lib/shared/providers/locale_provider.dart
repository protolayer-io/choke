import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/l10n/generated/app_localizations.dart';

const _kLocaleKey = 'choke:locale';

/// Provider for the app locale. null means follow the system language.
///
/// Persists the selection to [SharedPreferences] and hydrates synchronously
/// at startup, the same way the theme and default-duration preferences do —
/// so a chosen language survives the app being closed instead of snapping
/// back to the device language.
final localeProvider = StateNotifierProvider<LocaleNotifier, Locale?>((ref) {
  return LocaleNotifier();
});

/// Manages the app's [Locale] state with persistence.
///
/// On startup, call [loadSavedLocale] to read the saved preference, then
/// [hydrate] to set the initial value synchronously before the first frame
/// renders — otherwise the UI flashes the system language until the read
/// completes.
class LocaleNotifier extends StateNotifier<Locale?> {
  /// Creates a [LocaleNotifier] that follows the system language.
  LocaleNotifier() : super(null);

  /// Load the saved locale from [SharedPreferences]. Call before runApp().
  ///
  /// Returns null when nothing was stored or the stored code is no longer one
  /// of [AppLocalizations.supportedLocales] — a language dropped between
  /// versions must fall back to the system default rather than to a locale
  /// the app can no longer translate.
  static Future<Locale?> loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString(_kLocaleKey);
    if (code == null) return null;
    final isSupported = AppLocalizations.supportedLocales
        .any((locale) => locale.languageCode == code);
    return isSupported ? Locale(code) : null;
  }

  /// Set the initial locale synchronously (called at startup).
  void hydrate(Locale? locale) {
    state = locale;
  }

  /// Updates the locale and persists the choice to [SharedPreferences].
  ///
  /// Pass null to follow the system language; that clears the stored key so
  /// the next launch has nothing to restore.
  ///
  /// The write happens first and [state] moves only once it lands, so the
  /// live locale never promises something a restart would take back — the
  /// exact divergence this provider exists to prevent. A failed write is
  /// logged and rethrown for the caller to surface; it is never swallowed.
  Future<void> setLocale(Locale? locale) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (locale == null) {
        await prefs.remove(_kLocaleKey);
      } else {
        await prefs.setString(_kLocaleKey, locale.languageCode);
      }
    } catch (e, st) {
      // Safe to log: this key holds a language subtag, no key material.
      debugPrint('Locale persistence failed: $e\n$st');
      rethrow;
    }
    state = locale;
  }
}
