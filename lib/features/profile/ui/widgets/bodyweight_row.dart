import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/format/number_format.dart';
import '../../../../core/format/weight_unit.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../core/theme/radii.dart';
import '../../../../features/auth/providers/auth_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/profile.dart';
import '../../providers/bodyweight_consent_provider.dart';
import '../../providers/profile_providers.dart';

/// Tappable row that displays the user's stored bodyweight and opens
/// [BodyweightEditorSheet] to edit it.
///
/// Phase 24c — bodyweight is the load multiplier for 20 curated bodyweight
/// exercises (pull-ups, dips, push-ups, pistol squats, etc.). When the user
/// hasn't set one, the SQL falls back to `COALESCE(bodyweight_kg, 0)` and the
/// XP for those exercises silently undercounts (treats the user as
/// weightless). This row is the primary surface for setting the value; the
/// active-workout lazy prompt (24c-8) reuses [BodyweightEditorSheet] verbatim.
class BodyweightRow extends StatelessWidget {
  const BodyweightRow({super.key, required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final unit = profile?.weightUnit ?? 'kg';
    final bodyweightKg = profile?.bodyweightKg;

    final subtitle = bodyweightKg == null
        ? l10n.profileBodyweightNotSet
        : AppNumberFormat.weightWithUnit(
            unit == 'lbs' ? kgToLb(bodyweightKg) : bodyweightKg,
            locale: locale,
            unit: unit,
          );

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => showBodyweightEditorSheet(context, profile: profile),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'profile-bodyweight-row',
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.profileBodyweightLabel,
                    style: AppTextStyles.title,
                  ),
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

/// Public entrypoint for the bodyweight editor bottom sheet.
///
/// Returns the saved bodyweight in **kg**, or null if the user cancelled or
/// dismissed the sheet without saving.
///
/// Callers may safely ignore the return value: the sheet's internal save
/// handler invalidates `profileProvider` on success, so any consumer
/// watching the profile re-renders automatically. The return value exists
/// for callers that need the value synchronously after the await (e.g., to
/// perform an immediate computation against it without re-reading the
/// provider).
///
/// Phase 24c-8 (active-workout lazy prompt) reuses this entrypoint without
/// duplicating the form logic.
Future<double?> showBodyweightEditorSheet(
  BuildContext context, {
  required Profile? profile,
}) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) => BodyweightEditorSheet(profile: profile),
  );
}

/// Bottom-sheet form for entering / editing the user's bodyweight.
///
/// Behaviour:
///   * Pre-fills the input with the current bodyweight (converted to the
///     user's preferred unit when `weight_unit == 'lbs'`).
///   * Validates the entry against the kg server bounds (25–250 kg). The
///     range is displayed in the user's preferred unit but the comparison
///     always happens in canonical kg so we never let a value through that
///     would later trip the `valid_profiles_bodyweight_kg` CHECK.
///   * On save: converts to kg if needed, writes via `upsertProfile`, then
///     invalidates `profileProvider` so the row + any other watchers
///     re-render. The sheet pops with the saved kg value as its result.
///   * On cancel/dismiss: returns null without touching the repository.
class BodyweightEditorSheet extends ConsumerStatefulWidget {
  const BodyweightEditorSheet({super.key, required this.profile});

  final Profile? profile;

  @override
  ConsumerState<BodyweightEditorSheet> createState() =>
      _BodyweightEditorSheetState();
}

class _BodyweightEditorSheetState extends ConsumerState<BodyweightEditorSheet> {
  late final TextEditingController _controller;
  String? _errorText;
  bool _saving = false;

  String get _unit => widget.profile?.weightUnit ?? 'kg';

  @override
  void initState() {
    super.initState();
    final initial = widget.profile?.bodyweightKg;
    final initialDisplay = initial == null
        ? ''
        // Locale-independent text; the input is a numeric field. Users in
        // pt locales can still type with a comma — _parseInput accepts both.
        : (_unit == 'lbs' ? kgToLb(initial) : initial).toStringAsFixed(1);
    _controller = TextEditingController(text: initialDisplay);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Accepts both `,` and `.` as decimal separators (pt-BR users on the
  /// numeric keyboard naturally produce `80,5`).
  double? _parseInput(String text) {
    final normalised = text.trim().replaceAll(',', '.');
    if (normalised.isEmpty) return null;
    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed.isNaN || parsed.isInfinite) return null;
    return parsed;
  }

  /// Returns the entered value converted to canonical kg, or null when the
  /// input is unparseable / out-of-range. Sets [_errorText] as a side effect
  /// so the UI re-renders with the inline message.
  double? _validateAndConvertToKg(AppLocalizations l10n) {
    final parsed = _parseInput(_controller.text);
    if (parsed == null) {
      setState(() {
        _errorText = l10n.profileBodyweightInvalidRange(
          _unit == 'lbs'
              ? bodyweightMinLb.round().toString()
              : bodyweightMinKg.round().toString(),
          _unit == 'lbs'
              ? bodyweightMaxLb.round().toString()
              : bodyweightMaxKg.round().toString(),
          _unit,
        );
      });
      return null;
    }
    final kg = _unit == 'lbs' ? lbToKg(parsed) : parsed;
    if (!isBodyweightInRange(kg)) {
      setState(() {
        _errorText = l10n.profileBodyweightInvalidRange(
          _unit == 'lbs'
              ? bodyweightMinLb.round().toString()
              : bodyweightMinKg.round().toString(),
          _unit == 'lbs'
              ? bodyweightMaxLb.round().toString()
              : bodyweightMaxKg.round().toString(),
          _unit,
        );
      });
      return null;
    }
    return kg;
  }

  Future<void> _onSave() async {
    final l10n = AppLocalizations.of(context);
    final kg = _validateAndConvertToKg(l10n);
    if (kg == null) return;

    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      return;
    }

    // Cluster: data-protection-compliance — body weight is sensitive
    // health data under LGPD Art. 11 / Privacy Policy §7. Before the
    // FIRST save we surface a consent dialog; the user must explicitly
    // accept ("Save with consent") or cancel. Subsequent saves (consent
    // already granted) bypass the dialog. The withdrawal mechanism lives
    // in Profile → Settings → Privacy as `BodyweightConsentToggle`.
    final hasConsent = ref.read(bodyweightConsentProvider);
    if (!hasConsent) {
      final accepted = await _showConsentDialog(l10n);
      if (!mounted) return;
      if (accepted != true) return;
      await ref.read(bodyweightConsentProvider.notifier).setEnabled(true);
      if (!mounted) return;
    }

    setState(() => _saving = true);
    try {
      await ref
          .read(profileRepositoryProvider)
          .upsertProfile(userId: user.id, bodyweightKg: kg);
      if (!mounted) return;
      ref.invalidate(profileProvider);
      Navigator.of(context).pop(kg);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Error surfacing left to the global recovery recorder hooked into the
      // repository — the sheet stays open so the user can retry.
    }
  }

  /// Surfaces the consent dialog. Returns `true` when the user taps
  /// "Save with consent", `false`/`null` on cancel or dismiss.
  ///
  /// Kept inside the State so it can read `context` and `l10n` without
  /// threading them through the call site. The dialog uses
  /// `dialogTextButtonStyle` / `dialogFilledButtonStyle` for parity with
  /// other in-sheet dialogs.
  Future<bool?> _showConsentDialog(AppLocalizations l10n) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        final theme = Theme.of(dialogCtx);
        return AlertDialog(
          backgroundColor: theme.cardTheme.color,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(l10n.bodyweightConsentTitle),
          content: Text(l10n.bodyweightConsentBody),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              style: dialogTextButtonStyle,
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogCtx).pop(true),
              style: dialogFilledButtonStyle,
              child: Text(l10n.bodyweightConsentAccept),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'profile-bodyweight-sheet',
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
                l10n.profileBodyweightLabel,
                style: AppTextStyles.title.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.profileBodyweightHelper,
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                container: true,
                explicitChildNodes: true,
                identifier: 'profile-bodyweight-input',
                child: TextField(
                  controller: _controller,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    // Allow digits + a single decimal separator (`.` or `,`).
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    suffixText: _unit,
                    errorText: _errorText,
                  ),
                  onChanged: (_) {
                    if (_errorText != null) {
                      setState(() => _errorText = null);
                    }
                  },
                  onSubmitted: (_) => _saving ? null : _onSave(),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: dialogTextButtonStyle,
                    child: Text(l10n.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _saving ? null : _onSave,
                    style: dialogFilledButtonStyle,
                    child: Text(l10n.save),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
