// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

// Hide the calculator's `VitalityState` data class — we only use the
// `percentage` static helper here. The four-state enum we *do* want
// already lives in `models/vitality_state.dart`. Renaming the data
// class would churn ~10 §8.1 call sites; the explicit `show` is safer.
import '../domain/vitality_calculator.dart' show VitalityCalculator;
import '../domain/vitality_state_mapper.dart';
import 'body_part.dart';
import 'body_part_progress.dart';
import 'character_class.dart';
import 'vitality_state.dart';

part 'character_sheet_state.freezed.dart';

/// Per-body-part roll-up consumed by the character sheet UI.
///
/// Composes the raw [BodyPartProgress] row with two derived display values:
///   * [vitalityState] — the four-state §8.4 visual collapse, computed from
///     `vitalityEwma` + `vitalityPeak` once at provider time so widgets don't
///     re-derive it per rebuild.
///   * [xpInRank] / [xpForNextRank] — slice of `total_xp` relative to the
///     current rank, used by the hairline progress marker. Zero on the
///     untrained state (rank 1, total_xp 0).
///
/// **Why a separate model from [BodyPartProgress]:** the row is the wire
/// shape persisted in `body_part_progress`; this is the UI shape. Keeping
/// them split lets the provider absorb the rank-curve lookup without bloating
/// the wire model with display-only fields, and the curve is free to change
/// in 18e without forcing a migration to the persisted row.
@freezed
abstract class BodyPartSheetEntry with _$BodyPartSheetEntry {
  const factory BodyPartSheetEntry({
    required BodyPart bodyPart,
    required int rank,
    required double vitalityEwma,
    required double vitalityPeak,
    required VitalityState vitalityState,
    required double xpInRank,
    required double xpForNextRank,
    required double totalXp,
  }) = _BodyPartSheetEntry;

  const BodyPartSheetEntry._();

  /// True when the body part has never been trained (peak == 0 and rank 1).
  /// The character-sheet UI compresses these rows into a thinner secondary
  /// zone per the §13.4 onboarding gate.
  bool get isUntrained => vitalityPeak <= 0 && rank <= 1 && totalXp <= 0;
}

/// Top-level state for the `/profile` (Saga) character sheet.
///
/// Consumers: [CharacterSheetScreen]. The screen renders header (level +
/// class + active title) → vitality radar → six body-part rows → dormant
/// cardio row → three codex nav rows. Each block reads exactly the fields
/// it needs from this state so a refresh of one body-part row doesn't tear
/// the rest.
///
/// `characterClass` is nullable because the upstream RPG progress provider
/// can be in `AsyncLoading` / `AsyncError` — the badge then renders the
/// day-1 placeholder copy ("The iron will name you."). Once `AsyncData`
/// lands, the resolver always returns a non-null variant (Initiate floor).
/// Real class derivation lives in [`ClassResolver`](../domain/class_resolver.dart)
/// per spec §9.2; the badge resolves the localized label via
/// `AppLocalizations` keyed by [CharacterClass.l10nKey].
@freezed
abstract class CharacterSheetState with _$CharacterSheetState {
  const factory CharacterSheetState({
    required int characterLevel,
    required double lifetimeXp,

    /// Denominator for the Phase 26b character XP bar. The numerator is
    /// [lifetimeXp] — the bar fill ratio is `lifetimeXp / xpForNextLevel`.
    /// See `xpForNextCharacterLevel()` in `domain/character_xp_calculator.dart`
    /// for the single-body-part approximation it uses. Invariant (enforced
    /// as a documented contract — Freezed factories can't host asserts):
    /// `xpForNextLevel >= lifetimeXp`.
    required double xpForNextLevel,
    required List<BodyPartSheetEntry> bodyPartProgress,
    String? activeTitle,
    CharacterClass? characterClass,
  }) = _CharacterSheetState;

  const CharacterSheetState._();

  /// Day-0 user (no XP earned, all body parts dormant). Drives the
  /// onboarding gate copy on the character sheet.
  bool get isZeroHistory => lifetimeXp <= 0;

  /// Mean Vitality **percentage** (0..1) across active body parts.
  ///
  /// "Active" = rank > 1 OR peak > 0 — at least one set has touched the
  /// body part. Per-body-part percentage is `clamp(ewma/peak, 0, 1)`; we
  /// average those percentages, NOT the raw EWMA values, because EWMAs
  /// across body parts are not commensurable (their natural scales depend
  /// on each body part's lifetime peak).
  ///
  /// The `Percent` suffix is load-bearing: this returns a 0..1 ratio, not
  /// a raw EWMA value (which is volume-derived and typically in the
  /// thousands). Reading "vitality" without the suffix has historically
  /// been a source of confusion — see the latent bug in the original
  /// `VitalityStateX.fromVitality` documented on `VitalityStateMapper`.
  ///
  /// Falls back to 0 when no body parts have been touched, which collapses
  /// the halo to Dormant.
  double get meanActiveVitalityPercent {
    final active = bodyPartProgress.where(
      (e) => e.vitalityPeak > 0 || e.rank > 1,
    );
    if (active.isEmpty) return 0;
    final total = active.fold<double>(
      0,
      (sum, e) =>
          sum +
          VitalityCalculator.percentage(
            ewma: e.vitalityEwma,
            peak: e.vitalityPeak,
          ),
    );
    return total / active.length;
  }

  /// Vitality state of the rune halo — derived from the mean Vitality
  /// **percentage** across active body parts. Day-0 collapses to
  /// [VitalityState.untested] (no body part has a recorded peak — the
  /// ratio is undefined); once any body part has a recorded peak, the
  /// halo state tracks the average ratio across active body parts via
  /// [VitalityStateMapper.fromPercent] (which never returns
  /// [VitalityState.untested] — that branch is reachable only through
  /// `fromVitality` when peak == 0).
  ///
  /// Visually, the halo treats untested and dormant identically (slow
  /// rotation, dim sigil, no glow ring) — see `RuneHalo` `_buildForState`.
  /// The semantic separation lives in the stats deep-dive readout where
  /// untested renders `—` and dormant renders `0%`.
  VitalityState get haloState {
    if (isZeroHistory) return VitalityState.untested;
    final hasAnyPeak = bodyPartProgress.any((e) => e.vitalityPeak > 0);
    if (!hasAnyPeak) return VitalityState.untested;
    return VitalityStateMapper.fromPercent(meanActiveVitalityPercent);
  }
}
