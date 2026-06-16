import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/dialog_button_style.dart';
import '../../../../core/theme/radii.dart';
import '../../../../features/auth/providers/auth_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/profile.dart';
import '../../providers/profile_providers.dart';

/// Lowest birth-year offset (the wheel's TOP / max item). Structural ≥18
/// floor: there is no under-18 row to scroll to, so the signup 18+ gate is
/// never re-asked (Phase 38d locked decision #5 / WIP boundary inventory).
const int _minAgeOffset = 18;

/// Highest birth-year offset (the wheel's BOTTOM item).
const int _maxAgeOffset = 100;

/// Default resting offset — `currentYear − 35`. Skip == fallback: dismissing
/// the prompt or saving the default both land on the age-35 cardio baseline.
const int _defaultAgeOffset = 35;

/// Tappable row that displays the user's stored age (derived from
/// birth-year) and opens [AgeEditorSheet] to edit it.
///
/// Phase 38d — birth-year capture. The cardio XP path scores against
/// age-decade fitness norms; a NULL [Profile.dateOfBirth] falls back to the
/// age-35 baseline (a valid steady state — DOB never gates cardio XP).
///
/// Unlike [GenderRow] / [BodyweightRow] (LGPD Art. 11 sensitive → Hive
/// consent toggle), DOB is Art. 6 consent like avatars: the editor surfaces
/// a pure point-of-collection disclosure line, NOT a consent toggle.
///
/// The row renders the DERIVED AGE (e.g. "39" / "39 anos"), never the raw
/// stored `YYYY-01-01` date (data minimization).
class AgeRow extends StatelessWidget {
  const AgeRow({super.key, required this.profile});

  final Profile? profile;

  /// Derive whole-years age from a birth date relative to [now]. Returns
  /// null when [dob] is null. Counts a birthday that hasn't occurred yet
  /// this year as the prior age (standard age arithmetic), though for the
  /// stored `YYYY-01-01` representation the month/day are always January 1
  /// so the result equals `now.year − dob.year` in practice.
  static int? deriveAge(DateTime? dob, {DateTime? now}) {
    if (dob == null) return null;
    final today = now ?? DateTime.now();
    var age = today.year - dob.year;
    final hadBirthday =
        today.month > dob.month ||
        (today.month == dob.month && today.day >= dob.day);
    if (!hadBirthday) age -= 1;
    return age;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final age = deriveAge(profile?.dateOfBirth);
    final subtitle = age == null ? l10n.ageNotSet : l10n.ageYears(age);

    return Material(
      color: theme.cardTheme.color ?? theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(kRadiusMd),
      child: InkWell(
        borderRadius: BorderRadius.circular(kRadiusMd),
        onTap: () => showAgeEditorSheet(context, profile: profile),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          identifier: 'profile-age-row',
          label: l10n.ageRowSemantics(subtitle),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(l10n.ageLabel, style: AppTextStyles.title),
                ),
                // Derived age renders in the Rajdhani numeric register when
                // set (mockup §2 `.rval.num`); "Not set" stays in the calm
                // dimmed body register shared with every other unset row.
                Text(
                  subtitle,
                  style: age == null
                      ? AppTextStyles.body.copyWith(
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.55,
                          ),
                        )
                      : AppTextStyles.numericSmall.copyWith(
                          fontSize: 16,
                          color: theme.colorScheme.onSurface.withValues(
                            alpha: 0.92,
                          ),
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

/// Public entrypoint for the age editor bottom sheet.
///
/// Returns the saved [DateTime] (`YYYY-01-01`), or null if the user
/// cancelled, dismissed, or picked "Prefer not to say". Callers may ignore
/// the return value — the sheet invalidates `profileProvider` on save/clear
/// so any consumer re-renders.
Future<DateTime?> showAgeEditorSheet(
  BuildContext context, {
  required Profile? profile,
}) {
  return showModalBottomSheet<DateTime?>(
    context: context,
    isScrollControlled: true,
    builder: (_) => AgeEditorSheet(profile: profile),
  );
}

/// Bottom-sheet form for picking the user's birth year via a branded wheel.
///
/// **Control:** a real [ListWheelScrollView] of years from `currentYear−18`
/// (top/max) down to `currentYear−100` (bottom). The ≥18 floor is
/// structural — the list literally starts at `currentYear−18`, so the
/// signup 18+ gate can never be re-asked.
///
/// **Save:** writes `upsertProfile(dateOfBirth: DateTime(year, 1, 1))` —
/// birth-YEAR granularity stored as `YYYY-01-01` (data minimization).
///
/// **Prefer not to say:** clears any stored value to NULL via the dedicated
/// [ProfileRepository.clearDateOfBirth] path and pops.
class AgeEditorSheet extends ConsumerStatefulWidget {
  const AgeEditorSheet({super.key, required this.profile});

  final Profile? profile;

  @override
  ConsumerState<AgeEditorSheet> createState() => _AgeEditorSheetState();
}

class _AgeEditorSheetState extends ConsumerState<AgeEditorSheet> {
  late final FixedExtentScrollController _wheelController;
  late final int _currentYear;
  late int _selectedYear;
  bool _saving = false;

  /// The number of selectable years (inclusive of both endpoints).
  int get _itemCount => _maxAgeOffset - _minAgeOffset + 1;

  /// Year for a wheel index. Index 0 == top == `currentYear − 18` (the
  /// youngest selectable, i.e. age 18); index increases downward toward
  /// older birth years.
  int _yearForIndex(int index) => _currentYear - _minAgeOffset - index;

  /// Inverse of [_yearForIndex]; clamps into range defensively.
  int _indexForYear(int year) {
    final index = _currentYear - _minAgeOffset - year;
    return index.clamp(0, _itemCount - 1);
  }

  @override
  void initState() {
    super.initState();
    _currentYear = DateTime.now().year;
    // Pre-select the stored birth year if any; otherwise rest on the
    // default (`currentYear − 35`) so skip == the age-35 fallback.
    final storedYear = widget.profile?.dateOfBirth?.year;
    final initialYear = storedYear != null
        ? storedYear.clamp(
            _currentYear - _maxAgeOffset,
            _currentYear - _minAgeOffset,
          )
        : _currentYear - _defaultAgeOffset;
    _selectedYear = initialYear;
    _wheelController = FixedExtentScrollController(
      initialItem: _indexForYear(initialYear),
    );
  }

  @override
  void dispose() {
    _wheelController.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    if (_saving) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      // Birth-YEAR granularity — store January 1 of the picked year
      // (`YYYY-01-01`). The cardio formula keys on age-decade, so the year
      // is the minimal stable representation (LGPD data minimization).
      final dob = DateTime(_selectedYear, 1, 1);
      await ref
          .read(profileRepositoryProvider)
          .upsertProfile(userId: user.id, dateOfBirth: dob);
      if (!mounted) return;
      ref.invalidate(profileProvider);
      Navigator.of(context).pop(dob);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      // Error surfacing left to the global recovery recorder hooked into
      // the repository — the sheet stays open so the user can retry.
    }
  }

  Future<void> _onPreferNotToSay() async {
    if (_saving) return;
    final user = ref.read(authRepositoryProvider).currentUser;
    if (user == null) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = true);
    try {
      // Explicit clear-to-NULL — the only writer that nulls the column.
      // upsertProfile omits null fields (won't clobber unrelated columns),
      // so a dedicated clear path is required to wipe a previously-set DOB.
      await ref.read(profileRepositoryProvider).clearDateOfBirth(user.id);
      if (!mounted) return;
      ref.invalidate(profileProvider);
      Navigator.of(context).pop(null);
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final age = _currentYear - _selectedYear;

    return Semantics(
      container: true,
      explicitChildNodes: true,
      identifier: 'profile-age-sheet',
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
                l10n.ageLabel,
                style: AppTextStyles.title.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 8),
              // Point-of-collection disclosure ONLY (DOB = LGPD Art. 6).
              // NOT a consent banner/toggle — see class doc.
              Text(
                l10n.ageSheetHelper,
                style: AppTextStyles.body.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 18),
              _BirthYearWheel(
                controller: _wheelController,
                itemCount: _itemCount,
                yearForIndex: _yearForIndex,
                currentYear: _currentYear,
                selectedYear: _selectedYear,
                ageTagLabel: l10n.ageWheelTag,
                semanticsLabel: l10n.ageWheelSemantics(_selectedYear, age),
                onYearChanged: (year) {
                  if (year != _selectedYear) {
                    setState(() => _selectedYear = year);
                  }
                },
              ),
              const SizedBox(height: 6),
              // Prefer-not-to-say ghost — clears to NULL + pops.
              Align(
                alignment: Alignment.centerLeft,
                child: Semantics(
                  container: true,
                  button: true,
                  identifier: 'profile-age-prefer-not-to-say',
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(kRadiusSm),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kRadiusSm),
                      onTap: _saving ? null : _onPreferNotToSay,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.close,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              l10n.agePreferNotToSay,
                              style: AppTextStyles.body.copyWith(
                                color: theme.colorScheme.onSurface.withValues(
                                  alpha: 0.72,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
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

/// The branded birth-year [ListWheelScrollView]. Center year large in the
/// Rajdhani numeric register, flanking years dim toward the edges, a violet
/// selection band marks the resting slot. A live derived-age tag confirms
/// the age as the user spins.
///
/// **Large-text safety:** the item extent scales off
/// `MediaQuery.textScalerOf(context)` so the center numeral can never clip
/// against the band edges; the visible item count drops (5 → 3) under heavy
/// scale via [ListWheelScrollView.useMagnifier] geometry + the taller
/// extent. The numerals route through [AppTextStyles.numeric], which carries
/// no explicit scale opt-out, so the scaler grows them naturally.
class _BirthYearWheel extends StatelessWidget {
  const _BirthYearWheel({
    required this.controller,
    required this.itemCount,
    required this.yearForIndex,
    required this.currentYear,
    required this.selectedYear,
    required this.ageTagLabel,
    required this.semanticsLabel,
    required this.onYearChanged,
  });

  final FixedExtentScrollController controller;
  final int itemCount;
  final int Function(int index) yearForIndex;
  final int currentYear;
  final int selectedYear;
  final String ageTagLabel;
  final String semanticsLabel;
  final ValueChanged<int> onYearChanged;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    // Base item extent at 1.0 scale = 52dp (mockup `.wheel .yr` height).
    // Scale it off the text metric so the center numeral never clips; the
    // taller extent at large scale also reduces the visible item count
    // (5 → 3), matching the locked large-text mockup frame.
    final itemExtent = scale.scale(52.0);
    // Wheel height holds ~4 rows at base scale (mockup 208dp); grow with
    // the extent so the band + flanking rows stay proportional under scale.
    final wheelHeight = itemExtent * 4;
    final bandHeight = itemExtent + 4;

    return Semantics(
      container: true,
      identifier: 'profile-age-wheel',
      label: semanticsLabel,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Container(
          height: wheelHeight,
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border.all(color: AppColors.hair),
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Violet selection band — the resting slot.
              IgnorePointer(
                child: Container(
                  height: bandHeight,
                  decoration: BoxDecoration(
                    color: AppColors.hotViolet.withValues(alpha: 0.10),
                    border: Border(
                      top: BorderSide(
                        color: AppColors.hotViolet.withValues(alpha: 0.45),
                      ),
                      bottom: BorderSide(
                        color: AppColors.hotViolet.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                ),
              ),
              ListWheelScrollView.useDelegate(
                controller: controller,
                itemExtent: itemExtent,
                physics: const FixedExtentScrollPhysics(),
                perspective: 0.003,
                onSelectedItemChanged: (index) =>
                    onYearChanged(yearForIndex(index)),
                childDelegate: ListWheelChildBuilderDelegate(
                  childCount: itemCount,
                  builder: (context, index) {
                    final year = yearForIndex(index);
                    final isCenter = year == selectedYear;
                    return Center(
                      child: Text(
                        '$year',
                        style: AppTextStyles.numeric.copyWith(
                          fontSize: isCenter ? 34 : 24,
                          color: isCenter
                              ? AppColors.textCream
                              : AppColors.textCream.withValues(alpha: 0.42),
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Live derived-age tag, right-aligned in the band.
              Positioned(
                right: 14,
                child: IgnorePointer(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        ageTagLabel.toUpperCase(),
                        style: AppTextStyles.label.copyWith(
                          color: AppColors.hotViolet,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        '${currentYear - selectedYear}',
                        style: AppTextStyles.numericSmall.copyWith(
                          fontSize: 17,
                          color: AppColors.hotViolet,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
