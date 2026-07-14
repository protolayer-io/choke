import 'package:choke/l10n/generated/app_localizations.dart';

/// The submissions the app ships with, as **canonical ids**.
///
/// These ids are what goes on the wire, and they are English on purpose. A
/// Japanese referee taps 腕十字, a Brazilian taps *chave de braço*, and both
/// events say `armbar` — so a dashboard counting armbars across a tournament
/// counts one technique, not three. Publishing the localized string instead
/// would fragment the data at the exact moment we started collecting it.
///
/// The display is another matter: [labelFor] gives each id its name in the
/// referee's own language.
///
/// A submission the user adds themselves is published **verbatim**, exactly as
/// they typed it. That is what the free-text field is for — BJJ invents
/// submissions faster than any list can hold them, and a referee must never be
/// blocked from finishing a match because the app has never heard of a
/// baratoplata. This is a catalog, not an enum.
///
/// See docs/specs/match-outcome.md §3.3.
const List<String> defaultSubmissions = [
  'armbar',
  'rear_naked_choke',
  'triangle',
  'guillotine',
  'kimura',
  'americana',
  'cross_collar_choke',
  'bow_and_arrow',
  'ezekiel',
  'omoplata',
  'arm_triangle',
  'north_south_choke',
  'straight_ankle_lock',
  'heel_hook',
  'toe_hold',
];

/// The catalog id a typed submission means, or null if we have never heard of it.
///
/// Matches the id (`armbar`) **and** the name in the referee's own language
/// (*palanca de brazo*, 腕十字固め), because a referee who types a technique the
/// app already knows should not end up publishing a second spelling of it. That
/// is the whole point of having canonical ids; letting free text quietly bypass
/// them would fragment exactly the data this design exists to keep whole.
///
/// Anything genuinely new returns null, and is published verbatim.
String? canonicalize(AppLocalizations l10n, String typed) {
  final folded = typed.trim().toLowerCase();
  if (folded.isEmpty) return null;

  for (final id in defaultSubmissions) {
    if (id.toLowerCase() == folded) return id;
    if (labelFor(l10n, id).toLowerCase() == folded) return id;
  }
  return null;
}

/// The submission's name in the referee's language.
///
/// Anything outside the catalog — one the user added, or one published by a
/// client we have never met — comes back unchanged. Showing the raw string is
/// the right call: it is what somebody actually wrote down.
String labelFor(AppLocalizations l10n, String submission) {
  return switch (submission) {
    'armbar' => l10n.subArmbar,
    'rear_naked_choke' => l10n.subRearNakedChoke,
    'triangle' => l10n.subTriangle,
    'guillotine' => l10n.subGuillotine,
    'kimura' => l10n.subKimura,
    'americana' => l10n.subAmericana,
    'cross_collar_choke' => l10n.subCrossCollarChoke,
    'bow_and_arrow' => l10n.subBowAndArrow,
    'ezekiel' => l10n.subEzekiel,
    'omoplata' => l10n.subOmoplata,
    'arm_triangle' => l10n.subArmTriangle,
    'north_south_choke' => l10n.subNorthSouthChoke,
    'straight_ankle_lock' => l10n.subStraightAnkleLock,
    'heel_hook' => l10n.subHeelHook,
    'toe_hold' => l10n.subToeHold,
    _ => submission,
  };
}
