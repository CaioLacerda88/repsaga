import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';
import 'language_picker_sheet.dart';

/// Tappable row in the preferences section that opens the
/// [LanguagePickerSheet] bottom sheet. Renamed from `_LanguageRow` to
/// `ProfileLanguageRow` after extraction to avoid naming collision with
/// the picker sheet it triggers.
class ProfileLanguageRow extends StatelessWidget {
  const ProfileLanguageRow({super.key, required this.locale});

  final Locale locale;

  /// Display names in the language's own script (never translated).
  static const _displayNames = {'en': 'English', 'pt': 'Português (Brasil)'};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final displayName =
        _displayNames[locale.languageCode] ?? locale.languageCode;

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => _showLanguagePicker(context),
        child: Semantics(
          identifier: 'profile-language-row',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.language, style: AppTextStyles.title),
                ),
                Text(
                  displayName,
                  style: AppTextStyles.body.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => const LanguagePickerSheet(),
    );
  }
}
