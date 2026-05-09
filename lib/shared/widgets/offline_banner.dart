import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

/// A banner shown at the top of the app when the device is offline.
///
/// Uses [ColorScheme.errorContainer] background with [ColorScheme.onErrorContainer]
/// foreground to clearly signal degraded connectivity without being alarming.
///
/// Rendered by `_ShellScaffold` as an overlay on top of the active tab content
/// (a `Stack` child painted AFTER the body) — see the comment block in
/// `app_router.dart` for why a `Column` sibling above the body does not work
/// on Flutter Web (engine drops the semantics node).
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'offline-banner',
      label: l10n.offlineBanner,
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        color: colorScheme.errorContainer,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.cloud_off,
              size: 16,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.offlineBanner,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
