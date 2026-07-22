import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';
import 'package:choke/shared/providers/locale_provider.dart';

/// A store whose writes always fail — a full disk, a broken platform channel.
class _FailingStore extends InMemorySharedPreferencesStore {
  _FailingStore() : super.empty();

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    throw Exception('disk full');
  }

  @override
  Future<bool> remove(String key) async {
    throw Exception('disk full');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const localeKey = 'choke:locale';

  group('loadSavedLocale', () {
    test('returns the saved locale when one was chosen', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({localeKey: 'es'});

      // Act
      final locale = await LocaleNotifier.loadSavedLocale();

      // Assert
      expect(locale, const Locale('es'));
    });

    test('returns null when nothing has been saved', () async {
      // Arrange — a fresh install follows the system language
      SharedPreferences.setMockInitialValues({});

      // Act
      final locale = await LocaleNotifier.loadSavedLocale();

      // Assert
      expect(locale, isNull);
    });

    test('returns null when the saved locale is not supported', () async {
      // Arrange — a value written by a future (or corrupted) version
      SharedPreferences.setMockInitialValues({localeKey: 'kl'});

      // Act
      final locale = await LocaleNotifier.loadSavedLocale();

      // Assert
      expect(locale, isNull);
    });
  });

  group('hydrate', () {
    test('sets the initial locale synchronously without persisting', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      final notifier = LocaleNotifier();
      expect(notifier.debugState, isNull);

      // Act
      notifier.hydrate(const Locale('ja'));

      // Assert — state moved, storage untouched
      expect(notifier.debugState, const Locale('ja'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(localeKey), isNull);
    });
  });

  group('setLocale', () {
    test('updates state and persists the chosen language code', () async {
      // Arrange
      SharedPreferences.setMockInitialValues({});
      final notifier = LocaleNotifier();

      // Act
      await notifier.setLocale(const Locale('pt'));

      // Assert — both the live state and the stored preference agree
      expect(notifier.debugState, const Locale('pt'));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(localeKey), 'pt');
    });

    test('clears the stored preference when reset to system default', () async {
      // Arrange — Spanish previously chosen
      SharedPreferences.setMockInitialValues({localeKey: 'es'});
      final notifier = LocaleNotifier()..hydrate(const Locale('es'));

      // Act
      await notifier.setLocale(null);

      // Assert — nothing left behind for the next launch to restore
      expect(notifier.debugState, isNull);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(localeKey), isNull);
    });

    test('leaves the locale alone when the write fails', () async {
      // Arrange — every write fails. Register the restore BEFORE swapping the
      // store, so the real backend comes back even if the test exits early.
      SharedPreferences.setMockInitialValues({});
      final previousStore = SharedPreferencesStorePlatform.instance;
      addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore);
      SharedPreferencesStorePlatform.instance = _FailingStore();
      final notifier = LocaleNotifier();

      // Act — the write blows up, and the caller is told
      await expectLater(
        notifier.setLocale(const Locale('en')),
        throwsA(isA<Exception>()),
      );

      // Assert — state never moved. Committing it would show English now and
      // hand back the system language on the next launch: the exact bug this
      // provider exists to prevent.
      expect(notifier.debugState, isNull);
    });

    test('keeps the stored locale when clearing it fails', () async {
      // Arrange — Spanish stored, and every write fails
      SharedPreferences.setMockInitialValues({localeKey: 'es'});
      final previousStore = SharedPreferencesStorePlatform.instance;
      addTearDown(
          () => SharedPreferencesStorePlatform.instance = previousStore);
      SharedPreferencesStorePlatform.instance = _FailingStore();
      final notifier = LocaleNotifier()..hydrate(const Locale('es'));

      // Act
      await expectLater(
        notifier.setLocale(null),
        throwsA(isA<Exception>()),
      );

      // Assert — still Spanish, matching what a restart would restore
      expect(notifier.debugState, const Locale('es'));
    });

    test('survives a restart: a saved choice reloads as the same locale',
        () async {
      // Arrange — first launch, user picks English on a Spanish device
      SharedPreferences.setMockInitialValues({});
      await LocaleNotifier().setLocale(const Locale('en'));

      // Act — the app is killed and started again
      final restored = await LocaleNotifier.loadSavedLocale();

      // Assert
      expect(restored, const Locale('en'));
    });
  });
}
