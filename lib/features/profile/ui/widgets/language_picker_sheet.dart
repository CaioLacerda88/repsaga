import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/l10n/locale_provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// A modal bottom sheet that lets the user pick between English and
/// Portuguese (Brasil). Language display names are always shown in their
/// own language (not translated).
class LanguagePickerSheet extends ConsumerWidget {
  const LanguagePickerSheet({super.key});

  /// Supported locale entries. Display names are hardcoded in the
  /// language's own script so they never change with the app locale.
  static const _options = [
    _LanguageOption(locale: Locale('en'), displayName: 'English'),
    _LanguageOption(
      locale: Locale('pt'),
      displayName: 'Portugu\u00eas (Brasil)',
    ),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final currentLocale = ref.watch(localeProvider);

    return Semantics(
      container: true,
      identifier: 'profile-language-picker',
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.language,
                style: AppTextStyles.title.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 16),
              for (final option in _options) ...[
                _LanguageTile(
                  option: option,
                  isSelected:
                      currentLocale.languageCode == option.locale.languageCode,
                  onTap: () {
                    ref.read(localeProvider.notifier).setLocale(option.locale);
                    Navigator.of(context).pop();
                  },
                ),
                if (option != _options.last) const SizedBox(height: 4),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageTile extends StatelessWidget {
  const _LanguageTile({
    required this.option,
    required this.isSelected,
    required this.onTap,
  });

  final _LanguageOption option;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semanticsId = 'language-option-${option.locale.languageCode}';

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: onTap,
        child: Semantics(
          identifier: semanticsId,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(option.displayName, style: AppTextStyles.title),
                ),
                if (isSelected)
                  Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguageOption {
  const _LanguageOption({required this.locale, required this.displayName});

  final Locale locale;
  final String displayName;
}
