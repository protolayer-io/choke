# Translations & Internationalization (i18n)

Choke is fully localized. All user-facing text lives in translation files, never
hardcoded in widgets, so contributors can fix wording or add a whole new language
without touching UI logic.

This guide covers three tasks:

- [Change an existing translation](#change-an-existing-translation)
- [Add a new string](#add-a-new-string-for-developers)
- [Add a new language](#add-a-new-language)

## How it works

Choke uses Flutter's built-in [`gen-l10n`](https://docs.flutter.dev/ui/accessibility-and-internationalization/internationalization)
tooling. Text is stored in [ARB](https://github.com/google/app-resource-bundle)
files (`.arb` — JSON with metadata), one per language, under `lib/l10n/`.

| Path | What it is |
|---|---|
| `lib/l10n/app_en.arb` | **Template / source of truth** (English). Every key and its metadata is defined here. |
| `lib/l10n/app_es.arb`, `app_pt.arb`, `app_ja.arb` | Translations. One key/value per string, no metadata. |
| `lib/l10n/generated/` | Auto-generated Dart (`AppLocalizations`). **Committed to the repo** — regenerate, don't hand-edit. |
| `l10n.yaml` | Config: template file, output dir, etc. |
| `lib/features/settings/settings_screen.dart` | Holds `_localeNames`, the map that drives the in-app language picker. |

Configuration (`l10n.yaml`):

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n/generated
nullable-getter: false
```

The list of languages the app offers (`AppLocalizations.supportedLocales`, wired
in `lib/main.dart`) is derived **automatically** from the `.arb` files present —
you never edit a locale list by hand. The active locale is stored in
`localeProvider` (`lib/shared/providers/locale_provider.dart`); `null` means
"follow the system language".

### Regenerating

After editing any `.arb` file, regenerate the Dart bindings:

```bash
flutter gen-l10n
```

This rewrites `lib/l10n/generated/`. **Commit those generated files** together
with your `.arb` changes — they are tracked in the repo. (A plain
`flutter run` / `flutter build` also regenerates them, because `generate: true`
is set in `pubspec.yaml`, but run the command explicitly so the diff is part of
your commit.)

---

## Change an existing translation

To fix wording or a typo in a language that already exists:

1. Open the file for that language, e.g. `lib/l10n/app_es.arb` for Spanish.
2. Find the key and edit its **value** (the right-hand side). Do not rename the
   key — the key is shared across all languages.
   ```json
   "cancel": "Cancelar",
   ```
3. If you are changing the **English** source text, edit `lib/l10n/app_en.arb`
   and leave its `@key` metadata block untouched:
   ```json
   "cancel": "Cancel",
   "@cancel": {
     "description": "Cancel button label"
   },
   ```
4. Regenerate and commit:
   ```bash
   flutter gen-l10n
   ```

That's it — no Dart changes are needed to reword existing text.

---

## Add a new string (for developers)

When you add UI that needs new text:

1. **Add the key to the template**, `lib/l10n/app_en.arb`, *with* a `@key`
   metadata block describing it:
   ```json
   "generate": "Generate",
   "@generate": {
     "description": "Confirm button label in the generate new keypair dialog"
   },
   ```
2. **Add the same key** (value only, no metadata) to every other language file
   (`app_es.arb`, `app_pt.arb`, `app_ja.arb`). If you can't translate a language,
   copy the English value so nothing is missing; a native speaker can refine it
   later.
3. **Regenerate**: `flutter gen-l10n`.
4. **Use it** in a widget via `AppLocalizations`:
   ```dart
   final l10n = AppLocalizations.of(context);
   Text(l10n.generate);
   ```
   Never hardcode a user-facing string in a widget — always route it through a
   key.

### Placeholders (dynamic values)

For text that interpolates a value, use `{placeholderName}` and declare it in the
**template's** metadata (only the template needs the `placeholders` block):

```json
"copiedToClipboard": "{label} copied to clipboard",
"@copiedToClipboard": {
  "description": "Snackbar message when something is copied",
  "placeholders": {
    "label": { "type": "String" }
  }
}
```

Other language files just reuse the placeholder in their translated string:

```json
"copiedToClipboard": "{label} copiado al portapapeles",
```

It is then called as a method: `l10n.copiedToClipboard(l10n.publicKey)`.

---

## Add a new language

Say you want to add French (`fr`). The language code is an
[ISO 639-1](https://en.wikipedia.org/wiki/List_of_ISO_639_language_codes) code
(optionally with a region, e.g. `pt` vs. `pt_BR`).

1. **Create the ARB file** `lib/l10n/app_fr.arb`. The fastest way is to copy the
   Spanish or Portuguese file (they contain only values, no metadata) and
   translate each value. Start it with the `@@locale` header:
   ```json
   {
     "@@locale": "fr",
     "appTitle": "Choke",
     "homeSubtitle": "Notez vos combats de BJJ",
     "cancel": "Annuler",
     ...
   }
   ```
   - Translate **every** key that exists in `lib/l10n/app_en.arb`. Missing keys
     fall back to English at runtime, so aim for full coverage.
   - Do **not** copy the `@key` metadata blocks — those belong only to the
     English template.

2. **Register the language in the in-app picker.** Add the code and its native
   display name to `_localeNames` in
   `lib/features/settings/settings_screen.dart`:
   ```dart
   const _localeNames = {
     'en': 'English',
     'es': 'Español',
     'pt': 'Português (Brasil)',
     'ja': '日本語',
     'fr': 'Français', // ← new
   };
   ```
   > ⚠️ This step is easy to forget. `supportedLocales` picks up your `.arb` file
   > automatically, so the translation *works* — but without this entry the
   > language will **not appear** in Settings → Language for users to choose.
   > Write the display name in the language itself (an endonym), e.g. `Français`,
   > not `French`.

3. **Regenerate the bindings:**
   ```bash
   flutter gen-l10n
   ```

4. **Verify:**
   ```bash
   flutter analyze
   flutter test
   ```
   Then run the app, open **Settings → Language**, pick the new language, and
   sanity-check the screens (Account, Settings, Match). Watch for text that
   overflows its button or card — some languages are noticeably longer than
   English.

5. **Commit** your new `app_fr.arb`, the `settings_screen.dart` change, and the
   regenerated files under `lib/l10n/generated/`, then open a pull request.

### Checklist for a new language

- [ ] `lib/l10n/app_<code>.arb` created, starts with `"@@locale": "<code>"`
- [ ] Every key from `app_en.arb` is translated (no missing keys)
- [ ] No `@key` metadata blocks copied into the translation file
- [ ] `_localeNames` updated in `settings_screen.dart`
- [ ] `flutter gen-l10n` run and `lib/l10n/generated/` committed
- [ ] `flutter analyze` and `flutter test` pass
- [ ] Verified in-app via Settings → Language

---

Questions or a language you'd like to see? Open an issue or PR — see the
[Contributing](../README.md#contributing) section.
