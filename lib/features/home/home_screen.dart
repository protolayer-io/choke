import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../match/create_match_screen.dart';
import '../match/match_control_screen.dart';
import '../match/models/match.dart';
import '../match/providers/match_control_provider.dart';
import 'providers/home_providers.dart';

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

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filteredMatches = ref.watch(filteredMatchListProvider);
    final allMatches = ref.watch(recentMatchListProvider);
    final statusFilter = ref.watch(statusFilterProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final tk = ChokeTokens.of(context);

    return Scaffold(
      // Lift the FAB above the translucent nav bar (extendBody lets the
      // body — and this inner Scaffold — extend beneath it).
      floatingActionButton: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 9,
          right: 4,
        ),
        child: _buildFab(context, tk),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: title + subtitle
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.appTitle,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontSize: 25,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -.5,
                      height: 1.05,
                    ),
                  ),
                  Text(
                    l10n.homeSubtitle,
                    style: TextStyle(fontSize: 12.5, color: tk.muted),
                  ),
                ],
              ),
            ),

            // Status filter cards
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child:
                  _buildStatusCards(context, ref, statusFilter, allMatches, tk),
            ),

            // Match list
            Expanded(
              child: filteredMatches.isEmpty
                  ? _buildEmptyState(context)
                  : ListView.builder(
                      padding: EdgeInsets.fromLTRB(
                        20,
                        2,
                        20,
                        MediaQuery.of(context).padding.bottom + 80,
                      ),
                      itemCount: filteredMatches.length,
                      itemBuilder: (context, index) {
                        final match = filteredMatches[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 11),
                          child: _buildMatchCard(context, ref, match, tk),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFab(BuildContext context, ChokeTokens tk) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CreateMatchScreen()),
        );
      },
      child: Container(
        width: 58,
        height: 58,
        decoration: BoxDecoration(
          gradient: tk.gradient,
          borderRadius: BorderRadius.circular(19),
          boxShadow: [
            BoxShadow(
              color: tk.gradTop.withOpacity(.4),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Icon(Icons.add, color: tk.onGrad, size: 28),
      ),
    );
  }

  Widget _buildStatusCards(
    BuildContext context,
    WidgetRef ref,
    Set<MatchStatus> selected,
    List<Match> allMatches,
    ChokeTokens tk,
  ) {
    final statuses = MatchStatus.values;

    return Column(
      children: [
        for (var row = 0; row < statuses.length; row += 2) ...[
          if (row > 0) const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatusCard(
                    context, ref, statuses[row], selected, allMatches, tk),
              ),
              if (row + 1 < statuses.length) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatusCard(context, ref, statuses[row + 1],
                      selected, allMatches, tk),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildStatusCard(
    BuildContext context,
    WidgetRef ref,
    MatchStatus status,
    Set<MatchStatus> selected,
    List<Match> allMatches,
    ChokeTokens tk,
  ) {
    final l10n = AppLocalizations.of(context);
    final isSelected = selected.contains(status);
    final count = allMatches.where((m) => m.status == status).length;
    final color = _statusAccent(tk, status);

    return Semantics(
      button: true,
      selected: isSelected,
      label: '${_statusLabel(l10n, status)}: $count',
      child: GestureDetector(
        onTap: () {
          final current = Set<MatchStatus>.from(ref.read(statusFilterProvider));
          if (isSelected) {
            current.remove(status);
          } else {
            current.add(status);
          }
          ref.read(statusFilterProvider.notifier).state = current;
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(.12) : tk.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isSelected ? color.withOpacity(.5) : tk.cardBorder,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _statusLabel(l10n, status),
                      style: TextStyle(
                        color: isSelected ? color : tk.muted,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$count',
                style: TextStyle(
                  color: count > 0 ? color : tk.faint,
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text('🥋', style: TextStyle(fontSize: 64)),
          const SizedBox(height: 16),
          Text(
            l10n.noMatchesYet,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.createNewOne,
            style: theme.textTheme.bodyMedium?.copyWith(fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildMatchCard(
      BuildContext context, WidgetRef ref, Match match, ChokeTokens tk) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    final f1Color = _hexToColor(match.f1Color, colors.outline);
    final f2Color = _hexToColor(match.f2Color, colors.outline);
    final isLive = match.status == MatchStatus.inProgress;
    final isCanceled = match.status == MatchStatus.canceled;

    final card = Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: isLive
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  tk.accent.withOpacity(.12),
                  tk.accent.withOpacity(.03),
                ],
              )
            : null,
        color: isLive ? null : tk.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isLive ? tk.accent.withOpacity(.45) : tk.cardBorder,
        ),
      ),
      child: Column(
        children: [
          // Top row: match ID + status chip
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '#${match.id}',
                style: TextStyle(
                  color: tk.faint,
                  fontSize: 12,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.w600,
                ),
              ),
              _buildStatusChip(context, match.status, tk),
            ],
          ),
          const SizedBox(height: 11),
          // Fighters + score row
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration:
                          BoxDecoration(color: f1Color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 9),
                    Flexible(
                      child: Text(
                        match.f1Name,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (match.f1Adv > 0) ...[
                      const SizedBox(width: 6),
                      _buildSmallBadge('A:${match.f1Adv}', tk.goldFg),
                    ],
                    if (match.f1Pen > 0) ...[
                      const SizedBox(width: 4),
                      _buildSmallBadge('P:${match.f1Pen}', tk.dangerFg),
                    ],
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '${match.f1Score}',
                    style: TextStyle(
                      color: match.f1Score > match.f2Score && !isCanceled
                          ? tk.accent
                          : tk.muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                      height: 1,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 9),
                    child: Text(
                      l10n.vs,
                      style: TextStyle(fontSize: 12, color: tk.faint),
                    ),
                  ),
                  Text(
                    '${match.f2Score}',
                    style: TextStyle(
                      color: match.f2Score > match.f1Score && !isCanceled
                          ? tk.accent
                          : tk.muted,
                      fontWeight: FontWeight.bold,
                      fontSize: 27,
                      height: 1,
                    ),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (match.f2Adv > 0) ...[
                      _buildSmallBadge('A:${match.f2Adv}', tk.goldFg),
                      const SizedBox(width: 6),
                    ],
                    if (match.f2Pen > 0) ...[
                      _buildSmallBadge('P:${match.f2Pen}', tk.dangerFg),
                      const SizedBox(width: 4),
                    ],
                    Flexible(
                      child: Text(
                        match.f2Name,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          color: colors.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 9),
                    Container(
                      width: 9,
                      height: 9,
                      decoration:
                          BoxDecoration(color: f2Color, shape: BoxShape.circle),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );

    return InkWell(
      onTap: () {
        ref.read(activeMatchProvider.notifier).state = match;
        ref.invalidate(matchControlProvider);
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => MatchControlScreen(match: match),
          ),
        );
      },
      borderRadius: BorderRadius.circular(18),
      child: isCanceled ? Opacity(opacity: .72, child: card) : card,
    );
  }

  Widget _buildStatusChip(
      BuildContext context, MatchStatus status, ChokeTokens tk) {
    final l10n = AppLocalizations.of(context);
    final (fg, bg) = switch (status) {
      MatchStatus.waiting => (tk.goldFg, tk.goldFg.withOpacity(.14)),
      MatchStatus.inProgress => (tk.accent, tk.accent.withOpacity(.2)),
      MatchStatus.finished => (tk.statusFinishedFg, tk.statusFinishedBg),
      MatchStatus.canceled => (tk.statusCanceledFg, tk.statusCanceledBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status == MatchStatus.inProgress) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            _statusLabel(l10n, status),
            style: TextStyle(
              color: fg,
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Color _statusAccent(ChokeTokens tk, MatchStatus status) {
    return switch (status) {
      MatchStatus.waiting => tk.goldFg,
      MatchStatus.inProgress => tk.accent,
      MatchStatus.finished => tk.statusFinishedFg,
      MatchStatus.canceled => tk.statusCanceledFg,
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
