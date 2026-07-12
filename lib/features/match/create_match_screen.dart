import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../services/nostr/nostr_service.dart';
import 'models/match.dart';
import 'providers/match_providers.dart';
import 'providers/match_control_provider.dart';
import '../home/providers/home_providers.dart';
import 'match_control_screen.dart';
import '../../shared/providers/match_duration_provider.dart';

// Fighter color palette sourced from BJJColors.fighterPalette

/// Convert Color to hex string (#RRGGBB)
String _colorToHex(Color color) {
  return '#${color.red.toRadixString(16).padLeft(2, '0')}'
          '${color.green.toRadixString(16).padLeft(2, '0')}'
          '${color.blue.toRadixString(16).padLeft(2, '0')}'
      .toUpperCase();
}

/// Format seconds as mm:ss — delegates to shared [formatDuration].
String _formatDuration(int seconds) => formatDuration(seconds);

class CreateMatchScreen extends ConsumerStatefulWidget {
  const CreateMatchScreen({super.key});

  @override
  ConsumerState<CreateMatchScreen> createState() => _CreateMatchScreenState();
}

class _CreateMatchScreenState extends ConsumerState<CreateMatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _f1NameController = TextEditingController();
  final _f2NameController = TextEditingController();

  Color _f1Color = BJJColors.fighterPalette[0]; // Green
  Color _f2Color = BJJColors.fighterPalette[1]; // Gold
  late int _duration;
  bool _isPublishing = false;
  bool _durationInitialized = false;

  @override
  void dispose() {
    _f1NameController.dispose();
    _f2NameController.dispose();
    super.dispose();
  }

  Future<void> _createMatch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isPublishing = true);

    try {
      // Create match with auto-generated ID
      final match = Match.create(
        f1Name: _f1NameController.text.trim(),
        f2Name: _f2NameController.text.trim(),
        f1Color: _colorToHex(_f1Color),
        f2Color: _colorToHex(_f2Color),
        duration: _duration,
        status: MatchStatus.waiting,
        startAt: 0,
      );

      // Calculate expiration: now + 1 week
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final expiration = now + 604800; // 7 days

      // Publish to Nostr
      final nostrService = ref.read(nostrServiceProvider);
      await nostrService.publishAddressableEvent(
        dTag: match.id,
        content: match.toJsonString(),
        additionalTags: [
          ['expiration', expiration.toString()],
        ],
      );

      // Add to local state + home feed
      ref.read(matchListProvider.notifier).addMatch(match);
      ref.read(matchFeedProvider.notifier).addLocal(match);

      if (mounted) {
        // Set active match and navigate to control screen
        ref.read(activeMatchProvider.notifier).state = match;
        // Invalidate to force re-creation with new match
        ref.invalidate(matchControlProvider);
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MatchControlScreen(match: match),
          ),
        );
      }
    } catch (e) {
      debugPrint('CreateMatch: publish failed: $e');
      if (mounted) {
        final l10n = AppLocalizations.of(context);
        final colors = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.couldNotPublishMatch),
            backgroundColor: colors.error,
            action: SnackBarAction(
              label: l10n.retry,
              textColor: colors.onError,
              onPressed: _createMatch,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isPublishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize duration from provider only once
    if (!_durationInitialized) {
      _duration = ref.read(matchDurationProvider);
      _durationInitialized = true;
    }
    final l10n = AppLocalizations.of(context);
    final tk = ChokeTokens.of(context);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header: back button + title
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  _buildBackButton(context, tk),
                  const SizedBox(width: 12),
                  Text(
                    l10n.newMatch,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fighter cards with VS circle in between
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Column(
                            children: [
                              _buildFighterCard(
                                context: context,
                                label: l10n.fighter1,
                                controller: _f1NameController,
                                selectedColor: _f1Color,
                                onColorSelected: (c) =>
                                    setState(() => _f1Color = c),
                                validatorMessage: l10n.fighter1NameRequired,
                              ),
                              const SizedBox(height: 12),
                              _buildFighterCard(
                                context: context,
                                label: l10n.fighter2,
                                controller: _f2NameController,
                                selectedColor: _f2Color,
                                onColorSelected: (c) =>
                                    setState(() => _f2Color = c),
                                validatorMessage: l10n.fighter2NameRequired,
                              ),
                            ],
                          ),
                          _buildVsBadge(context, tk),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Duration
                      _buildSectionLabel(context, l10n.matchDuration, tk),
                      const SizedBox(height: 10),
                      _buildDurationSelector(context, tk),
                    ],
                  ),
                ),
              ),
            ),
            // Fixed bottom create button
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .scaffoldBackgroundColor
                    .withValues(alpha: .6),
                border: Border(top: BorderSide(color: tk.cardBorder)),
              ),
              child: _buildGradientButton(
                context: context,
                tk: tk,
                enabled: !_isPublishing,
                onTap: _createMatch,
                child: _isPublishing
                    ? SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: tk.onGrad,
                        ),
                      )
                    : Text(
                        l10n.createMatch,
                        style: TextStyle(
                          color: tk.onGrad,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackButton(BuildContext context, ChokeTokens tk) {
    return GestureDetector(
      onTap: () => Navigator.of(context).pop(),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: tk.field,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: tk.cardBorder),
        ),
        child: const Icon(Icons.arrow_back_ios_new, size: 17),
      ),
    );
  }

  Widget _buildVsBadge(BuildContext context, ChokeTokens tk) {
    final theme = Theme.of(context);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        shape: BoxShape.circle,
        border: Border.all(color: tk.strongBorder),
      ),
      child: Center(
        child: Text(
          AppLocalizations.of(context).vs.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: tk.muted,
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(
      BuildContext context, String label, ChokeTokens tk) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        color: tk.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildFighterCard({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    required Color selectedColor,
    required ValueChanged<Color> onColorSelected,
    required String validatorMessage,
  }) {
    final l10n = AppLocalizations.of(context);
    final tk = ChokeTokens.of(context);
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: tk.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selectedColor.withOpacity(.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionLabel(context, label, tk),
          const SizedBox(height: 10),
          TextFormField(
            controller: controller,
            style: TextStyle(
              color: colors.onSurface,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              hintText: l10n.enterFighterName,
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 13, vertical: 13),
              prefixIcon: Icon(Icons.person_outline,
                  color: selectedColor == BJJColors.white
                      ? tk.muted
                      : selectedColor,
                  size: 20),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return validatorMessage;
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          _buildColorDots(
            context: context,
            selectedColor: selectedColor,
            onColorSelected: onColorSelected,
          ),
        ],
      ),
    );
  }

  Widget _buildColorDots({
    required BuildContext context,
    required Color selectedColor,
    required ValueChanged<Color> onColorSelected,
  }) {
    final theme = Theme.of(context);
    final tk = ChokeTokens.of(context);

    return Wrap(
      spacing: 9,
      runSpacing: 9,
      children: BJJColors.fighterPalette.map((color) {
        final isSelected = color == selectedColor;
        return GestureDetector(
          onTap: () => onColorSelected(color),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: color == BJJColors.white || color == BJJColors.navy
                  ? Border.all(color: tk.cardBorder)
                  : null,
              // Painted in list order (bottom first): outer color ring,
              // then a background-colored gap ring on top of it.
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: color == BJJColors.white ? tk.muted : color,
                        spreadRadius: 3.5,
                      ),
                      BoxShadow(
                        color: theme.scaffoldBackgroundColor,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDurationSelector(BuildContext context, ChokeTokens tk) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: defaultDurationOptions.map((seconds) {
          final isSelected = seconds == _duration;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => setState(() => _duration = seconds),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
                decoration: BoxDecoration(
                  gradient: isSelected ? tk.gradient : null,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? null
                      : Border.all(color: tk.cardBorder, width: 1),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: tk.gradTop.withOpacity(.3),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  _formatDuration(seconds),
                  style: TextStyle(
                    color: isSelected ? tk.onGrad : tk.muted,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                    fontSize: 15,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildGradientButton({
    required BuildContext context,
    required ChokeTokens tk,
    required bool enabled,
    required VoidCallback onTap,
    required Widget child,
  }) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : .6,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            gradient: tk.gradient,
            borderRadius: BorderRadius.circular(15),
            boxShadow: [
              BoxShadow(
                color: tk.gradTop.withOpacity(.35),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
