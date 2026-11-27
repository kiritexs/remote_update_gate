import 'package:material_ui/material_ui.dart';

import 'update_manifest.dart';
import 'update_status.dart';

/// Everything a card needs to render one prompt.
@immutable
class UpdateCardData {
  const UpdateCardData({
    required this.status,
    required this.manifest,
    required this.onUpdate,
    this.onSkip,
    this.skipLabel = 'Skip this version',
    this.onContinueOffline,
    this.hasDownloadTarget = true,
    this.downloadHost,
  });

  final UpdateStatus status;
  final UpdateManifest manifest;

  /// Opens the download link.
  final VoidCallback onUpdate;

  /// Dismiss an optional update; null for a forced update.
  final VoidCallback? onSkip;

  /// Label for the [onSkip] action. Ignored when [onSkip] is null.
  final String skipLabel;

  /// Keep using offline content instead of updating now (forced only). Null hides it.
  final VoidCallback? onContinueOffline;

  /// Whether a download URL is available; when false the card shows a "repairing" state.
  final bool hasDownloadTarget;

  /// Host an https update link opens, shown on the card; else null.
  final String? downloadHost;

  bool get isForced => status == UpdateStatus.forced;
}

/// Builds the card widget for a given [UpdateCardData].
typedef UpdateCardBuilder = Widget Function(
  BuildContext context,
  UpdateCardData data,
);

/// A clean, theme-driven default card.
class DefaultUpdateCard extends StatelessWidget {
  const DefaultUpdateCard({super.key, required this.data});

  final UpdateCardData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final forced = data.isForced;
    final message = data.manifest.message.trim();
    final repairing = !data.hasDownloadTarget;

    return Center(
      child: Container(
        margin: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 420),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 32,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              repairing
                  ? Icons.cloud_sync_rounded
                  : forced
                  ? Icons.system_security_update_warning_rounded
                  : Icons.system_update_rounded,
              color: scheme.primary,
              size: 46,
            ),
            const SizedBox(height: 16),
            Text(
              repairing
                  ? 'Update on the way'
                  : forced
                  ? 'Update required'
                  : 'Update available',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message.isNotEmpty
                  ? message
                  : repairing
                  ? 'A new version is being prepared — please check back soon.'
                  : forced
                  ? 'A newer version is required to keep using the app.'
                  : 'A newer version is available with improvements and fixes.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.75),
                height: 1.4,
              ),
            ),
            const SizedBox(height: 24),
            if (!repairing)
              FilledButton(
                onPressed: data.onUpdate,
                style: FilledButton.styleFrom(
                  backgroundColor: scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Update now',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            if (!repairing && data.downloadHost != null) ...[
              const SizedBox(height: 8),
              Text(
                'Opens ${data.downloadHost}',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ],
            if (data.onSkip != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: data.onSkip,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurface.withValues(alpha: 0.6),
                ),
                child: Text(data.skipLabel),
              ),
            ],
            if (data.onContinueOffline != null) ...[
              const SizedBox(height: 6),
              TextButton(
                onPressed: data.onContinueOffline,
                style: TextButton.styleFrom(
                  foregroundColor: scheme.onSurface.withValues(alpha: 0.6),
                ),
                child: const Text('Continue with offline content'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
