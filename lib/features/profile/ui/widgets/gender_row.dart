import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../core/theme/radii.dart';
import '../../../../features/auth/providers/auth_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/profile.dart';
import '../../providers/gender_consent_provider.dart';
import '../../providers/profile_providers.dart';

/// Tappable row that displays the user's stored gender and opens
/// [GenderEditorSheet] to edit it.
///
/// Cluster: `data-protection-compliance`. Gender is sensitive data
/// (LGPD Art. 11 / Privacy Policy §7) — the editor surfaces a one-time
/// disclosure banner the first time it's opened.
///
/// Behind the row, [Gender] is consumed by Phase 29 v2's per-lift tier
/// table selection (male tables = Symmetric Strength reference data;
/// female tables = strengthlevel.com 2026-05-20 snapshot). NULL and
/// [Gender.other] both fall back to the male tables — documented
/// backward-compat path.
class GenderRow extends StatelessWidget {
  const GenderRow({super.key, required this.profile});

  final Profile? profile;

  String _genderDisplay(AppLocalizations l10n, Gender? gender) {
    if (gender == null) return l10n.genderNotSet;
    switch (gender) {
      case Gender.male:
        return l10n.genderMale;
      case Gender.female:
        return l10n.genderFemale;
      case Gender.other:
        return l10n.genderOther;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final subtitle = _genderDisplay(l10n, profile?.gender);

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => showGenderEditorSheet(context, profile: profile),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'profile-gender-row',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.genderLabel, style: AppTextStyles.title),
                ),
                Text(
                  subtitle,
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
}

/// Public entrypoint for the gender editor bottom sheet.
///
/// Returns the picked [Gender] (or `null` if the user picked "Not set" /
/// cancelled). Callers can ignore the return value — the sheet's save
/// handler invalidates `profileProvider` so any consumer re-renders.
Future<Gender?> showGenderEditorSheet(
  BuildContext context, {
  required Profile? profile,
}) {
  return showModalBottomSheet<Gender?>(
    context: context,
    isScrollControlled: true,
    builder: (_) => GenderEditorSheet(profile: profile),
  );
}

/// Bottom-sheet form for picking the user's gender.
///
/// Surfaces a one-time disclosure banner above the options when
/// `genderConsentProvider == false` AND the current gender is NULL —
/// matches the Privacy Policy §7 sensitive-data disclosure requirement.
/// Picking any value flips the consent provider to `true` so the banner
/// self-extinguishes on subsequent opens.
class GenderEditorSheet extends ConsumerStatefulWidget {
  const GenderEditorSheet({super.key, required this.profile});

  final Profile? profile;

  @override
  ConsumerState<GenderEditorSheet> createState() => _GenderEditorSheetState();
}

class _GenderEditorSheetState extends ConsumerState<GenderEditorSheet> {
  bool _saving = false;

  Future<void> _onPick(Gender? value) async {
    if (_saving) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      // Any explicit tap on a tile — INCLUDING "Not set" — counts as an
      // affirmative, disclosed choice once the user has seen the banner.
      // Picking "Not set" after the disclosure is the user's deliberate
      // decline; flipping consent records that they made the choice so
      // the banner self-extinguishes on subsequent opens (PR #309 review
      // finding I1: without this flip, a user who deliberately declines
      // sees the disclosure banner forever).
      //
      // The flip happens BEFORE the network write so a transient failure
      // still marks the disclosure as seen — re-showing it after a retry
      // would be noise.
      if (!ref.read(genderConsentProvider)) {
        await ref.read(genderConsentProvider.notifier).setEnabled(true);
        if (!mounted) return;
      }
      await ref
          .read(profileRepositoryProvider)
          .upsertProfile(userId: user.id, gender: value);
      if (!mounted) return;
      ref.invalidate(profileProvider);
      Navigator.of(context).pop(value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Error surfacing left to the global recovery recorder hooked into
      // the repository — sheet stays open so the user can retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final currentGender = widget.profile?.gender;
    final showBanner =
        !ref.watch(genderConsentProvider) && currentGender == null;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'profile-gender-sheet',
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.genderLabel,
                style: AppTextStyles.title.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              if (showBanner) ...[
                Semantics(
                  container: true,
                  identifier: 'profile-gender-consent-banner',
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(
                          alpha: 0.30,
                        ),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: theme.colorScheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            l10n.genderConsentBanner,
                            style: AppTextStyles.body.copyWith(
                              color: theme.colorScheme.onSurface.withValues(
                                alpha: 0.85,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              _GenderTile(
                label: l10n.genderMale,
                selected: currentGender == Gender.male,
                onTap: () => _onPick(Gender.male),
                identifier: 'profile-gender-male',
              ),
              const SizedBox(height: 8),
              _GenderTile(
                label: l10n.genderFemale,
                selected: currentGender == Gender.female,
                onTap: () => _onPick(Gender.female),
                identifier: 'profile-gender-female',
              ),
              const SizedBox(height: 8),
              _GenderTile(
                label: l10n.genderOther,
                selected: currentGender == Gender.other,
                onTap: () => _onPick(Gender.other),
                identifier: 'profile-gender-other',
              ),
              const SizedBox(height: 8),
              _GenderTile(
                label: l10n.genderNotSet,
                selected: currentGender == null,
                onTap: () => _onPick(null),
                identifier: 'profile-gender-not-set',
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  style: dialogTextButtonStyle,
                  child: Text(l10n.cancel),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GenderTile extends StatelessWidget {
  const _GenderTile({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.identifier,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String identifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: identifier,
      button: true,
      child: Material(
        color: selected
            ? theme.colorScheme.primary.withValues(alpha: 0.16)
            : theme.cardTheme.color ?? theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: InkWell(
          borderRadius: BorderRadius.circular(kRadiusMd),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, style: AppTextStyles.body)),
                if (selected)
                  Icon(Icons.check, color: theme.colorScheme.primary, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
