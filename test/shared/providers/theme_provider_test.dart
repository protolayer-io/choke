import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:choke/shared/providers/theme_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const themeModeKey = 'choke:theme-mode';

  group('loadSavedThemeMode', () {
    test('returns dark when the saved preference says dark', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({themeModeKey: 'dark'});

      // Act
      final mode = await ThemeModeNotifier.loadSavedThemeMode();

      // Assert
      expect(mode, ThemeMode.dark);
    });

    test('returns light when the saved preference says light', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({themeModeKey: 'light'});

      // Act
      final mode = await ThemeModeNotifier.loadSavedThemeMode();

      // Assert
      expect(mode, ThemeMode.light);
    });

    test('falls back to system when nothing has been saved', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});

      // Act
      final mode = await ThemeModeNotifier.loadSavedThemeMode();

      // Assert
      expect(mode, ThemeMode.system);
    });

    test('falls back to system when the saved value is unrecognized',
        () async {
      // Arrange — a value written by a future (or corrupted) version
      SharedPreferences.setMockInitialValues({themeModeKey: 'sepia'});

      // Act
      final mode = await ThemeModeNotifier.loadSavedThemeMode();

      // Assert
      expect(mode, ThemeMode.system);
    });
  });

  group('hydrate', () {
    test('sets the initial mode synchronously without persisting', () {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      final notifier = ThemeModeNotifier();
      expect(notifier.debugState, ThemeMode.system);

      // Act
      notifier.hydrate(ThemeMode.dark);

      // Assert
      expect(notifier.debugState, ThemeMode.dark);
    });
  });

  group('setThemeMode', () {
    for (final (mode, persisted) in [
      (ThemeMode.dark, 'dark'),
      (ThemeMode.light, 'light'),
      (ThemeMode.system, 'system'),
    ]) {
      test('updates state and persists "$persisted"', () async {
        // Arrange
        SharedPreferences.setMockInitialValues({});
        final notifier = ThemeModeNotifier();

        // Act
        await notifier.setThemeMode(mode);

        // Assert — both the live state and the stored preference agree
        expect(notifier.debugState, mode);
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString(themeModeKey), persisted);
      });
    }
  });
}
