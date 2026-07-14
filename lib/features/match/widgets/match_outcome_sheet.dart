import 'package:flutter/material.dart';
import 'package:choke/l10n/generated/app_localizations.dart';

import '../../../shared/theme/app_theme.dart';
import '../models/match.dart';
import '../models/match_outcome.dart';

/// Asks the referee how the match ended, and will not let them not answer.
///
/// The constraint that shapes this: a referee is standing over two people, one
/// of whom has just tapped, holding a phone in one hand. So the common cases are
/// two taps — and it must be impossible to record the wrong fighter by accident,
/// which is why fighters are always offered **in their own colours**, the same
/// two the referee has been tapping all match, never by position.
///
/// What the scoreboard already says is pre-selected: points (or advantages), or
/// a disqualification when someone has four penalties. That is an *offer*. The
/// referee is the authority on what happened; the app only makes it fast to
/// record — and hard to record wrongly.
///
/// Returns null if dismissed, which leaves the match open. That is the honest
/// state of a match nobody has decided.
///
/// See docs/specs/match-outcome.md.
Future<MatchOutcome?> showMatchOutcomeSheet(
  BuildContext context, {
  required Match match,
  required MatchOutcome? suggested,
}) {
  return showModalBottomSheet<MatchOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _MatchOutcomeSheet(match: match, suggested: suggested),
  );
}

class _MatchOutcomeSheet extends StatefulWidget {
  final Match match;
  final MatchOutcome? suggested;

  const _MatchOutcomeSheet({required this.match, this.suggested});

  @override
  State<_MatchOutcomeSheet> createState() => _MatchOutcomeSheetState();
}

class _MatchOutcomeSheetState extends State<_MatchOutcomeSheet> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _finish(MatchOutcome outcome) => Navigator.of(context).pop(outcome);

  String _nameOf(MatchWinner winner) =>
      winner == MatchWinner.f1 ? widget.match.f1Name : widget.match.f2Name;

  Color _colorOf(MatchWinner winner) {
    final hex =
        winner == MatchWinner.f1 ? widget.match.f1Color : widget.match.f2Color;
    return _hexToColor(hex, Theme.of(context).colorScheme.outline);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final tk = ChokeTokens.of(context);
    final suggested = widget.suggested;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.onSurface.withValues(alpha: .2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l10n.outcomeTitle,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),

              // Submission first: it is what the sport is for, and the reason a
              // scoreboard on its own can lie.
              _primaryAction(
                label: l10n.outcomeSubmission,
                accent: tk.accent,
                onTap: _askSubmission,
              ),
              const SizedBox(height: 10),

              // Whatever the scoreboard already says — one tap to confirm it.
              if (suggested != null)
                _primaryAction(
                  label: _describe(l10n, suggested),
                  accent: suggested.method == MatchMethod.dq
                      ? colors.error
                      : tk.goldFg,
                  onTap: () => _finish(suggested),
                ),

              const SizedBox(height: 18),
              Divider(color: colors.onSurface.withValues(alpha: .12)),
              const SizedBox(height: 6),

              // The rarer endings, kept out of the way of a hurried thumb.
              _secondaryAction(l10n.outcomeDq, _askDisqualification),
              _secondaryAction(l10n.outcomeForfeit, _askForfeit),
              _secondaryAction(l10n.outcomeDecision, _askDecision),
              _secondaryAction(
                l10n.outcomeDraw,
                () => _finish(const MatchOutcome.draw()),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "Bob wins · Points" — what the scoreboard already implies.
  String _describe(AppLocalizations l10n, MatchOutcome outcome) {
    final method = switch (outcome.method) {
      MatchMethod.points => l10n.outcomePoints,
      MatchMethod.advantages => l10n.outcomeAdvantages,
      MatchMethod.dq => l10n.outcomeDq,
      MatchMethod.submission => l10n.outcomeSubmission,
      MatchMethod.decision => l10n.outcomeDecision,
      MatchMethod.forfeit => l10n.outcomeForfeit,
      MatchMethod.draw => l10n.outcomeDraw,
    };
    final winner = outcome.winner;
    if (winner == null) return method;
    return '${l10n.outcomeWinsBy(_nameOf(winner))} · $method';
  }

  // ─── Follow-up questions ───────────────────────────────────────────────

  Future<void> _askSubmission() async {
    final winner = await _pickFighter();
    if (winner == null || !mounted) return;

    final technique =
        await _askText(AppLocalizations.of(context).outcomeTechnique);
    if (!mounted) return;

    _finish(MatchOutcome.submissionBy(winner, submission: _clean(technique)));
  }

  Future<void> _askForfeit() async {
    final winner = await _pickFighter();
    if (winner == null || !mounted) return;
    _finish(MatchOutcome.forfeitBy(winner));
  }

  Future<void> _askDecision() async {
    final winner = await _pickFighter();
    if (winner == null || !mounted) return;
    _finish(MatchOutcome.decision(winner));
  }

  Future<void> _askDisqualification() async {
    final l10n = AppLocalizations.of(context);

    // The *loser* is disqualified, but we ask for the winner, as everywhere
    // else. A referee with a phone in one hand should never be asked to think
    // in negatives.
    final winner = await _pickFighter();
    if (winner == null || !mounted) return;

    final reason = await _pickDqReason();
    if (reason == null || !mounted) return;

    final detail = await _askText(l10n.outcomeDqDetail);
    if (!mounted) return;

    _finish(
      MatchOutcome.disqualifying(winner, reason, dqDetail: _clean(detail)),
    );
  }

  /// Blank means "the referee did not say", not "an empty technique".
  String? _clean(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// Which fighter — always in their own colours, never by position.
  Future<MatchWinner?> _pickFighter() {
    final l10n = AppLocalizations.of(context);

    return showDialog<MatchWinner>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.outcomeWhichFighter),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final winner in MatchWinner.values) ...[
              _fighterButton(ctx, winner),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fighterButton(BuildContext ctx, MatchWinner winner) {
    final color = _colorOf(winner);
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton(
        onPressed: () => Navigator.of(ctx).pop(winner),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: color, width: 2),
          backgroundColor: color.withValues(alpha: .12),
          foregroundColor: Theme.of(ctx).colorScheme.onSurface,
        ),
        child: Text(
          _nameOf(winner),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<DqReason?> _pickDqReason() {
    final l10n = AppLocalizations.of(context);

    return showDialog<DqReason>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(l10n.outcomeDqCategory),
        children: [
          for (final entry in <(DqReason, String)>[
            (DqReason.accumulatedPenalties, l10n.outcomeDqAccumulated),
            (DqReason.technicalFoul, l10n.outcomeDqTechnical),
            (DqReason.disciplinaryFoul, l10n.outcomeDqDisciplinary),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(entry.$1),
              child: Text(entry.$2),
            ),
        ],
      ),
    );
  }

  /// Optional free text — the technique, or what the disqualified fighter did.
  /// Always skippable: a referee must never be blocked from ending a match
  /// because the app has never heard of a *baratoplata*.
  Future<String?> _askText(String label) {
    final l10n = AppLocalizations.of(context);
    _text.clear();

    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(label),
        content: TextField(
          controller: _text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.skip),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_text.text),
            child: Text(l10n.outcomeConfirm),
          ),
        ],
      ),
    );
  }

  // ─── Buttons ───────────────────────────────────────────────────────────

  Widget _primaryAction({
    required String label,
    required Color accent,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 56,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: accent, width: 2),
          backgroundColor: accent.withValues(alpha: .12),
          foregroundColor: Theme.of(context).colorScheme.onSurface,
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _secondaryAction(String label, VoidCallback onTap) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        alignment: Alignment.centerLeft,
        foregroundColor:
            Theme.of(context).colorScheme.onSurface.withValues(alpha: .8),
      ),
      child: Text(label, style: const TextStyle(fontSize: 15)),
    );
  }
}

/// Parse hex color string (#RRGGBB) to Color with fallback.
Color _hexToColor(String hex, Color fallback) {
  try {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return fallback;
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return fallback;
  }
}
