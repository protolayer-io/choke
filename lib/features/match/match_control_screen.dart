import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import 'models/match.dart';
import 'providers/match_control_provider.dart';
import 'widgets/hold_button.dart';

/// Parse hex color string (#RRGGBB) to Color with fallback
Color _hexToColor(String hex, Color fallback) {
  try {
    final h = hex.replaceFirst('#', '');
    if (h.length != 6) return fallback;
    return Color(int.parse('FF$h', radix: 16));
  } catch (_) {
    return fallback;
  }
}

/// Format seconds as mm:ss
String _formatTime(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// Landscape "thumb rails" match control screen.
///
/// Each fighter owns a side rail with their scoring buttons, so every
/// action is a single tap — no fighter selector. Holding a scoring button
/// for one second subtracts that score instead of adding it.
class MatchControlScreen extends ConsumerStatefulWidget {
  final Match match;

  const MatchControlScreen({super.key, required this.match});

  @override
  ConsumerState<MatchControlScreen> createState() => _MatchControlScreenState();
}

class _MatchControlScreenState extends ConsumerState<MatchControlScreen> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(matchControlProvider);
    final notifier = ref.read(matchControlProvider.notifier);
    final match = state.match;
    final colors = Theme.of(context).colorScheme;
    final f1Color = _hexToColor(match.f1Color, colors.outline);
    final f2Color = _hexToColor(match.f2Color, colors.outline);

    return PopScope(
      canPop: !state.isRunning,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final railWidth =
                  (constraints.maxWidth * 0.18).clamp(96.0, 160.0);
              return Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: railWidth,
                          child: _buildRail(
                            context,
                            state,
                            notifier,
                            fighter: 1,
                            color: f1Color,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildCenter(
                              context, state, notifier, f1Color, f2Color),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: railWidth,
                          child: _buildRail(
                            context,
                            state,
                            notifier,
                            fighter: 2,
                            color: f2Color,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (state.isWaiting) _buildWaitingOverlay(context, notifier),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─── Side rails ────────────────────────────────────────────────────────

  Widget _buildRail(
    BuildContext context,
    MatchControlState state,
    MatchControlNotifier notifier, {
    required int fighter,
    required Color color,
  }) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final enabled = state.isRunning;

    return Column(
      children: [
        Expanded(
          flex: 13,
          child: _railButton(
            context,
            fighter: fighter,
            accent: color,
            enabled: enabled,
            points: '+2',
            label: l10n.takedownSweep,
            onTap: () => notifier.scorePt2(fighter),
            onHold: () => notifier.subtractPt2(fighter),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 13,
          child: _railButton(
            context,
            fighter: fighter,
            accent: color,
            enabled: enabled,
            points: '+3',
            label: l10n.guardPass,
            onTap: () => notifier.scorePt3(fighter),
            onHold: () => notifier.subtractPt3(fighter),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 13,
          child: _railButton(
            context,
            fighter: fighter,
            accent: color,
            enabled: enabled,
            points: '+4',
            label: l10n.mountBackTake,
            onTap: () => notifier.scorePt4(fighter),
            onHold: () => notifier.subtractPt4(fighter),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 10,
          child: _railButton(
            context,
            fighter: fighter,
            accent: BJJColors.gold,
            enabled: enabled,
            label: l10n.advantage,
            onTap: () => notifier.scoreAdv(fighter),
            onHold: () => notifier.subtractAdv(fighter),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          flex: 10,
          child: _railButton(
            context,
            fighter: fighter,
            accent: colors.error,
            enabled: enabled,
            label: l10n.penalty,
            onTap: () => notifier.scorePen(fighter),
            onHold: () => notifier.subtractPen(fighter),
          ),
        ),
      ],
    );
  }

  Widget _railButton(
    BuildContext context, {
    required int fighter,
    required Color accent,
    required bool enabled,
    String? points,
    required String label,
    required VoidCallback onTap,
    required VoidCallback onHold,
  }) {
    final colors = Theme.of(context).colorScheme;
    final accentSide = BorderSide(color: accent, width: 4);
    // Accent bar faces the screen edge, where the operator's thumb rests
    final border =
        fighter == 1 ? Border(left: accentSide) : Border(right: accentSide);

    return HoldButton(
      enabled: enabled,
      accentColor: accent,
      holdFillColor: colors.error.withOpacity(.35),
      border: border,
      onTap: onTap,
      onHoldComplete: onHold,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (points != null)
              Text(
                points,
                style: TextStyle(
                  color: accent,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  height: 1,
                ),
              ),
            Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color:
                    points != null ? colors.onSurface.withOpacity(.6) : accent,
                fontSize: points != null ? 9 : 13,
                fontWeight: points != null ? FontWeight.w500 : FontWeight.w600,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Center column ─────────────────────────────────────────────────────

  Widget _buildCenter(
    BuildContext context,
    MatchControlState state,
    MatchControlNotifier notifier,
    Color f1Color,
    Color f2Color,
  ) {
    final match = state.match;

    return Column(
      children: [
        _buildHeader(context, state),
        const SizedBox(height: 8),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: _buildScorePanel(
                  context,
                  name: match.f1Name,
                  score: match.f1Score,
                  advantages: match.f1Adv,
                  penalties: match.f1Pen,
                  color: f1Color,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildScorePanel(
                  context,
                  name: match.f2Name,
                  score: match.f2Score,
                  advantages: match.f2Adv,
                  penalties: match.f2Pen,
                  color: f2Color,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        _buildFooter(context, state, notifier),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, MatchControlState state) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final isLow = state.remainingSeconds <= 30 && state.isRunning;

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: () => _onBack(context, state),
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    _formatTime(state.remainingSeconds),
                    style: TextStyle(
                      color: isLow ? colors.error : colors.onSurface,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusColor(state.match.status).withOpacity(.15),
                      borderRadius: BorderRadius.circular(99),
                      border: Border.all(
                        color: _statusColor(state.match.status).withOpacity(.4),
                      ),
                    ),
                    child: Text(
                      _statusLabel(l10n, state.match.status),
                      style: TextStyle(
                        color: _statusColor(state.match.status),
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    l10n.matchId(state.match.id),
                    style: TextStyle(
                      color: colors.onSurface.withOpacity(.4),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 32,
            child: state.isPublishing
                ? Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.secondary,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildScorePanel(
    BuildContext context, {
    required String name,
    required int score,
    required int advantages,
    required int penalties,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          Expanded(
            child: FittedBox(
              fit: BoxFit.contain,
              child: Text(
                '$score',
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 74,
                  height: 1.1,
                ),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildBadge('A:$advantages', BJJColors.gold),
              const SizedBox(width: 6),
              _buildBadge('P:$penalties', BJJColors.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style:
            TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w500),
      ),
    );
  }

  Widget _buildFooter(
    BuildContext context,
    MatchControlState state,
    MatchControlNotifier notifier,
  ) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    // A finished or canceled match is read-only: replace the scoring controls
    // with a status indicator instead of showing disabled buttons.
    if (state.isFinished) return _buildReadOnlyFooter(context, state);

    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            flex: 8,
            child: OutlinedButton.icon(
              onPressed: state.canUndo ? notifier.undo : null,
              icon: const Icon(Icons.undo, size: 16),
              label: Text(
                l10n.undoLastAction,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                side: BorderSide(color: colors.onSurface.withOpacity(.25)),
                foregroundColor: colors.onSurface.withOpacity(.8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: HoldButton(
              enabled: state.isRunning,
              accentColor: colors.primary,
              backgroundColor: Colors.transparent,
              border: Border.all(color: colors.primary.withOpacity(.5)),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              onHoldComplete: notifier.finishMatch,
              child: Text(
                '${l10n.finish} · ${l10n.holdHint}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 5,
            child: HoldButton(
              enabled: state.isRunning,
              accentColor: colors.error,
              backgroundColor: Colors.transparent,
              border: Border.all(color: colors.error.withOpacity(.5)),
              borderRadius: const BorderRadius.all(Radius.circular(10)),
              onHoldComplete: notifier.cancelMatch,
              child: Text(
                '${l10n.cancel} · ${l10n.holdHint}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.error,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Overlays ──────────────────────────────────────────────────────────

  Widget _buildWaitingOverlay(
      BuildContext context, MatchControlNotifier notifier) {
    final l10n = AppLocalizations.of(context);

    return _overlay(
      context,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        Center(
          child: SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: notifier.startMatch,
              icon: const Icon(Icons.play_arrow),
              label: Text(
                l10n.startMatch,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Read-only footer shown in place of the scoring controls once a match is
  /// finished or canceled. The match detail stays fully visible above it.
  Widget _buildReadOnlyFooter(BuildContext context, MatchControlState state) {
    final l10n = AppLocalizations.of(context);
    final finished = state.match.status == MatchStatus.finished;
    final accent = finished ? BJJColors.info : BJJColors.error;
    final label = finished ? l10n.matchFinished : l10n.matchCanceled;

    return SizedBox(
      height: 44,
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withOpacity(.12),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: accent.withOpacity(.4)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                finished ? Icons.emoji_events_outlined : Icons.cancel_outlined,
                size: 16,
                color: accent,
              ),
              const SizedBox(width: 8),
              Text(
                '$label · ${l10n.matchReadOnly}',
                style: TextStyle(
                  color: accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlay(BuildContext context, {required List<Widget> children}) {
    final colors = Theme.of(context).colorScheme;
    return Positioned.fill(
      child: Container(
        color: colors.surface.withOpacity(.88),
        child: Stack(children: children),
      ),
    );
  }

  // ─── Navigation & status helpers ───────────────────────────────────────

  void _onBack(BuildContext context, MatchControlState state) {
    if (state.isRunning) {
      _confirmLeave(context);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _confirmLeave(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.leaveMatchQuestion),
        content: Text(l10n.leaveMatchDescription),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.stay),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.of(context).pop();
            },
            child: Text(
              l10n.leave,
              style: TextStyle(color: colors.error),
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(MatchStatus status) {
    return switch (status) {
      MatchStatus.waiting => BJJColors.gold,
      MatchStatus.inProgress => BJJColors.green,
      MatchStatus.finished => BJJColors.info,
      MatchStatus.canceled => BJJColors.error,
    };
  }

  String _statusLabel(AppLocalizations l10n, MatchStatus status) {
    return switch (status) {
      MatchStatus.waiting => l10n.statusWaiting,
      MatchStatus.inProgress => l10n.statusInProgress,
      MatchStatus.finished => l10n.statusFinished,
      MatchStatus.canceled => l10n.statusCanceled,
    };
  }
}
