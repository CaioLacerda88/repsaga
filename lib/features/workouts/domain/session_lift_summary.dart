// ignore_for_file: invalid_annotation_target

import 'package:freezed_annotation/freezed_annotation.dart';

import '../../rpg/models/body_part.dart';

part 'session_lift_summary.freezed.dart';

/// One row of the S2 Mission Debrief lift table (Phase 31 Pass 1).
///
/// Pure data — pre-resolved for display. The screen layer consumes a
/// `List<SessionLiftSummary>` from `PostSessionState.topLifts` (top 4 by
/// XP contribution, ranking + truncation logic lives in the controller).
///
/// **Decoupling Rule 1 (pure data).** No widgets, no `BuildContext`, no
/// Riverpod. Composed once by `PostSessionController._buildInitial()` from
/// the in-progress workout's exercises + sets, then read by widget trees.
///
/// **Why a Freezed model and not a record:** the projection ships to widget
/// tests that pin the visible field set; structural typing on records makes
/// adding `isPR` later a silent API change. Freezed-generated `==` /
/// `copyWith` also make controller-level mutation tests trivial.
///
/// Field rationale:
///   * [exerciseId] — stable join key. Used by widget tests to match
///     against a specific exercise without relying on display-name
///     localization (matches the [`slug-rendered-as-display-name`] cluster's
///     forever-stable-key rule).
///   * [exerciseName] — pre-resolved localized name (pt-BR / en). The
///     widget renders this verbatim — no further resolution at paint time
///     (`feedback_widget_l10n_parameterization`).
///   * [bodyPart] — the exercise's dominant body part. Drives the hue dot
///     + the lift row's accent. Resolved via `xpAttribution` max-share or
///     fallback to `MuscleGroup → BodyPart` mapping (see controller).
///   * [peakWeightKg] / [peakReps] — the best set's weight × reps. Selection
///     mirrors the [`prScore`] hero-PR rule (`weight × reps`) so the
///     debrief row's peak matches the share-card PR detail when both
///     surface the same exercise.
///   * [xpContribution] — the exercise's share of session XP, used as the
///     sort key. Pass 1 ships this as a VOLUME proxy (sum of
///     `weight × reps × dominantBpShare`) since per-exercise XP is not
///     directly attributed at finish time. Volume preserves relative
///     ranking (the only thing the field drives in Pass 3); a precise
///     per-exercise XP attribution can swap in later without changing the
///     model contract.
///   * [isPR] — true when the exercise contributed at least one new
///     personal record this session. Drives the heroGold PR flag on the
///     row (mockup §S2 PR session edge case).
@freezed
abstract class SessionLiftSummary with _$SessionLiftSummary {
  const factory SessionLiftSummary({
    required String exerciseId,
    required String exerciseName,
    required BodyPart bodyPart,
    required double peakWeightKg,
    required int peakReps,
    required int xpContribution,
    required bool isPR,
  }) = _SessionLiftSummary;
}
