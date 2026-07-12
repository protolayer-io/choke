import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:choke/l10n/generated/app_localizations.dart';
import '../../shared/theme/app_theme.dart';
import '../../services/key_management/key_manager.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _isNsecVisible = false;
  final _importController = TextEditingController();

  @override
  void dispose() {
    _importController.dispose();
    super.dispose();
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      final l10n = AppLocalizations.of(context);
      final primaryColor = Theme.of(context).colorScheme.primary;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.copiedToClipboard(label)),
          backgroundColor: primaryColor,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _showImportDialog() async {
    String? dialogError;
    bool dialogImporting = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogBuildContext, setDialogState) {
          final l10n = AppLocalizations.of(dialogBuildContext);
          final theme = Theme.of(dialogBuildContext);
          final colors = theme.colorScheme;
          return AlertDialog(
            backgroundColor: colors.surface,
            title: Text(
              l10n.importPrivateKey,
              style: TextStyle(color: colors.onSurface),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  l10n.importWarning,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _importController,
                  style: TextStyle(color: colors.onSurface),
                  decoration: InputDecoration(
                    hintText: l10n.enterNsec,
                    errorText: dialogError,
                    errorStyle: TextStyle(color: colors.error),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _importController.clear();
                },
                child: Text(l10n.cancel),
              ),
              ElevatedButton(
                onPressed: dialogImporting
                    ? null
                    : () async {
                        final nsec = _importController.text.trim();
                        if (nsec.isEmpty) {
                          setDialogState(
                            () => dialogError = l10n.pleaseEnterNsec,
                          );
                          return;
                        }

                        if (!nsec.toLowerCase().startsWith('nsec1')) {
                          setDialogState(
                            () => dialogError = l10n.invalidNsecFormat,
                          );
                          return;
                        }

                        setDialogState(() {
                          dialogImporting = true;
                          dialogError = null;
                        });

                        final keyManager = ref.read(keyManagerProvider);
                        final success = await keyManager.importFromNsec(nsec);

                        if (!mounted || !dialogBuildContext.mounted) return;

                        setDialogState(() => dialogImporting = false);

                        if (success) {
                          Navigator.pop(dialogContext);
                          _importController.clear();
                          ref.invalidate(npubProvider);
                          ref.invalidate(nsecProvider);
                          if (mounted) {
                            final primaryColor =
                                Theme.of(context).colorScheme.primary;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(l10n.keyImportedSuccessfully),
                                backgroundColor: primaryColor,
                              ),
                            );
                          }
                        } else {
                          if (dialogBuildContext.mounted) {
                            setDialogState(
                              () => dialogError = l10n.failedToImportKey,
                            );
                          }
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.secondary,
                  foregroundColor: colors.onSecondary,
                ),
                child: dialogImporting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.import),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final npubAsync = ref.watch(npubProvider);
    final nsecAsync = ref.watch(nsecProvider);
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tk = ChokeTokens.of(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header: title + import/change key action
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 14, 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.accountTitle,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.logout, color: tk.muted, size: 21),
                    tooltip: l10n.importChangeKey,
                    onPressed: _showImportDialog,
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  6,
                  20,
                  MediaQuery.of(context).padding.bottom + 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Identity header
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                BJJColors.brandGradStart,
                                BJJColors.brandGradEnd,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(17),
                          ),
                          child: const Icon(
                            Icons.shield,
                            size: 28,
                            color: BJJColors.white,
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.yourNostrIdentity,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  height: 1.1,
                                ),
                              ),
                              Text(
                                l10n.keypairDescription,
                                style:
                                    TextStyle(fontSize: 12.5, color: tk.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),

                    // Public Key (npub)
                    _buildSectionTitle(context, l10n.publicKeyNpub, tk),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: tk.card,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tk.cardBorder),
                      ),
                      child: npubAsync.when(
                        data: (npub) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              npub ?? l10n.generating,
                              style: TextStyle(
                                color: tk.keyFg,
                                fontFamily: 'monospace',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                height: 1.5,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (npub != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildActionButton(
                                      context: context,
                                      icon: Icons.copy,
                                      label: l10n.copy,
                                      onTap: () => _copyToClipboard(
                                          npub, l10n.publicKey),
                                    ),
                                  ),
                                  const SizedBox(width: 9),
                                  Expanded(
                                    child: _buildActionButton(
                                      context: context,
                                      icon: Icons.qr_code,
                                      label: l10n.showQr,
                                      onTap: () => _showQRCode(context, npub),
                                    ),
                                  ),
                                ],
                              )
                            else
                              Text(
                                l10n.keyUnavailable,
                                style: theme.textTheme.bodyMedium,
                              ),
                          ],
                        ),
                        loading: () =>
                            const Center(child: CircularProgressIndicator()),
                        error: (_, __) => Text(
                          l10n.errorLoadingKey,
                          style: TextStyle(color: colors.error),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Private Key (nsec)
                    _buildSectionTitle(context, l10n.privateKeyNsec, tk),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: tk.dangerFg.withOpacity(.07),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: tk.dangerFg.withOpacity(.35)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.warning_amber,
                                color: tk.dangerFg,
                                size: 17,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l10n.neverSharePrivateKey,
                                  style: TextStyle(
                                    color: tk.dangerFg,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 11),
                          nsecAsync.when(
                            data: (nsec) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    setState(
                                        () => _isNsecVisible = !_isNsecVisible);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: tk.field,
                                      borderRadius: BorderRadius.circular(11),
                                      border: Border.all(
                                        color: tk.dangerFg.withOpacity(.2),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            _isNsecVisible
                                                ? (nsec ?? l10n.generating)
                                                : '••••••••••••••••••••',
                                            style: TextStyle(
                                              color: _isNsecVisible
                                                  ? colors.onSurface
                                                  : tk.muted,
                                              fontFamily: 'monospace',
                                              fontSize:
                                                  _isNsecVisible ? 12.5 : 15,
                                              letterSpacing:
                                                  _isNsecVisible ? 0 : 3,
                                            ),
                                          ),
                                        ),
                                        Icon(
                                          _isNsecVisible
                                              ? Icons.visibility_off
                                              : Icons.visibility,
                                          color: tk.muted,
                                          size: 19,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 9),
                                Text(
                                  l10n.tapToReveal,
                                  style: TextStyle(
                                      fontSize: 11.5, color: tk.faint),
                                ),
                                if (_isNsecVisible) ...[
                                  const SizedBox(height: 11),
                                  _buildActionButton(
                                    context: context,
                                    icon: Icons.copy,
                                    label: l10n.copyToClipboard,
                                    onTap: () => _copyToClipboard(
                                        nsec ?? '', l10n.privateKey),
                                  ),
                                ],
                              ],
                            ),
                            loading: () => const Center(
                                child: CircularProgressIndicator()),
                            error: (_, __) => Text(
                              l10n.errorLoadingKey,
                              style: TextStyle(color: colors.error),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),

                    // Security Tips
                    _buildSectionTitle(context, l10n.securityTips, tk),
                    const SizedBox(height: 8),
                    _buildTipCard(
                      context: context,
                      icon: Icons.cloud_upload_outlined,
                      iconColor: tk.accent,
                      title: l10n.tipBackupTitle,
                      description: l10n.tipBackupDescription,
                    ),
                    const SizedBox(height: 8),
                    _buildTipCard(
                      context: context,
                      icon: Icons.block,
                      iconColor: tk.goldFg,
                      title: l10n.tipNeverShareTitle,
                      description: l10n.tipNeverShareDescription,
                    ),
                    const SizedBox(height: 8),
                    _buildTipCard(
                      context: context,
                      icon: Icons.phone_android,
                      iconColor: tk.statusFinishedFg,
                      title: l10n.tipSecureStorageTitle,
                      description: l10n.tipSecureStorageDescription,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(
      BuildContext context, String title, ChokeTokens tk) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        color: tk.muted,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.4,
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final tk = ChokeTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(11),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tk.accent.withOpacity(.1),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: tk.accent.withOpacity(.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: tk.accent, size: 16),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.accent,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String description,
  }) {
    final colors = Theme.of(context).colorScheme;
    final tk = ChokeTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tk.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tk.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 19),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: colors.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: tk.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showQRCode(BuildContext context, String data) {
    showDialog(
      context: context,
      builder: (context) {
        final l10n = AppLocalizations.of(context);
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return AlertDialog(
          backgroundColor: colors.surface,
          title: Text(
            l10n.yourPublicKey,
            style: TextStyle(color: colors.onSurface),
            textAlign: TextAlign.center,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: BJJColors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SizedBox(
                  width: 200,
                  height: 200,
                  child: QrImageView(
                    data: data,
                    backgroundColor: BJJColors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: BJJColors.navy,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: BJJColors.navy,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                data,
                style: TextStyle(
                  color: theme.textTheme.bodyMedium?.color,
                  fontSize: 11,
                  fontFamily: 'monospace',
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Text(
                l10n.scanQrToShare,
                style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.close),
            ),
          ],
        );
      },
    );
  }
}
