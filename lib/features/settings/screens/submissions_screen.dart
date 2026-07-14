import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:choke/l10n/generated/app_localizations.dart';

import '../../match/models/submission_catalog.dart';
import '../../match/providers/submissions_provider.dart';

/// Manage the submissions the outcome sheet offers.
///
/// Adding happens in two places, on purpose. A referee discovers a missing
/// technique **while looking for it**, mid-match, so the outcome sheet has its
/// own "Other…" — walking off the mat to Settings is not a thing anyone does
/// with two fighters waiting.
///
/// This screen is the other half: the housekeeping. Removing techniques, and
/// putting the built-in ones back. That belongs somewhere calm, not under a
/// thumb that is in a hurry.
class SubmissionsScreen extends ConsumerStatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  ConsumerState<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends ConsumerState<SubmissionsScreen> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(submissionsProvider);
    final submissions = state.visible;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSubmissions),
        actions: [
          if (state.hidden.isNotEmpty)
            TextButton(
              onPressed: ref.read(submissionsProvider.notifier).restoreDefaults,
              child: Text(l10n.submissionsRestore),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: Text(l10n.submissionsAdd),
      ),
      body: submissions.isEmpty
          ? _empty(l10n)
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: submissions.length,
              itemBuilder: (context, i) {
                final submission = submissions[i];
                return ListTile(
                  title: Text(labelFor(l10n, submission)),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: l10n.submissionsRemove,
                    onPressed: () => ref
                        .read(submissionsProvider.notifier)
                        .remove(submission),
                  ),
                );
              },
            ),
    );
  }

  Widget _empty(AppLocalizations l10n) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          l10n.submissionsEmpty,
          textAlign: TextAlign.center,
          style: TextStyle(
            color:
                Theme.of(context).colorScheme.onSurface.withValues(alpha: .6),
          ),
        ),
      ),
    );
  }

  Future<void> _add() async {
    final l10n = AppLocalizations.of(context);
    _text.clear();

    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.submissionsAdd),
        content: TextField(
          controller: _text,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(labelText: l10n.submissionsName),
          onSubmitted: (value) => Navigator.of(ctx).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(_text.text),
            child: Text(l10n.outcomeConfirm),
          ),
        ],
      ),
    );

    final value = typed?.trim();
    if (value == null || value.isEmpty || !mounted) return;

    // A technique we already know goes back to its canonical id, so the same
    // submission is never published under two spellings.
    final submission = canonicalize(l10n, value) ?? value;
    final added = ref.read(submissionsProvider.notifier).add(submission);

    if (!added && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.submissionsDuplicate)),
      );
    }
  }
}
