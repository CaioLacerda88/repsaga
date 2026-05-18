// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../../core/theme/app_equipment_icons.dart';
import '../../../core/theme/app_icons.dart';
import '../../../core/theme/app_muscle_icons.dart';

part 'exercise.freezed.dart';
part 'exercise.g.dart';

/// High-level muscle group an exercise trains. Used both for filtering in the
/// browse list and as a chip label on detail/active sheets.
enum MuscleGroup {
  chest,
  back,
  legs,
  shoulders,
  arms,
  core,
  cardio;

  String get displayName => name[0].toUpperCase() + name.substring(1);

  /// Inline-SVG glyph surfaced alongside the muscle-group label across the
  /// app (filter chips, exercise detail sheet, active-workout preview sheet).
  ///
  /// These are structural enum metadata — a new muscle group ships with its
  /// glyph in the same commit as the enum value, so the pairing is enforced
  /// at compile time. Render via `AppIcons.render(group.svgIcon, ...)`.
  String get svgIcon => switch (this) {
    MuscleGroup.chest => AppMuscleIcons.chest,
    MuscleGroup.back => AppMuscleIcons.back,
    MuscleGroup.legs => AppMuscleIcons.legs,
    MuscleGroup.shoulders => AppMuscleIcons.shoulders,
    MuscleGroup.arms => AppMuscleIcons.arms,
    MuscleGroup.core => AppMuscleIcons.core,
    MuscleGroup.cardio => AppMuscleIcons.cardio,
  };

  static MuscleGroup fromString(String value) =>
      values.firstWhere((e) => e.name == value);
}

/// Equipment an exercise uses. Same UX surfaces as [MuscleGroup].
enum EquipmentType {
  barbell,
  dumbbell,
  cable,
  machine,
  bodyweight,
  bands,
  kettlebell;

  String get displayName => name[0].toUpperCase() + name.substring(1);

  /// Inline-SVG glyph surfaced alongside the equipment-type label across the
  /// app. See [MuscleGroup.svgIcon] for the same rationale.
  ///
  /// [EquipmentType.barbell] reuses `AppIcons.lift` — that asymmetric-plate
  /// barbell is the app's signature glyph; shipping a second barbell would
  /// fork visual vocabulary for zero benefit.
  String get svgIcon => switch (this) {
    EquipmentType.barbell => AppIcons.lift,
    EquipmentType.dumbbell => AppEquipmentIcons.dumbbell,
    EquipmentType.cable => AppEquipmentIcons.cable,
    EquipmentType.machine => AppEquipmentIcons.machine,
    EquipmentType.bodyweight => AppEquipmentIcons.bodyweight,
    EquipmentType.bands => AppEquipmentIcons.bands,
    EquipmentType.kettlebell => AppEquipmentIcons.kettlebell,
  };

  static EquipmentType fromString(String value) =>
      values.firstWhere((e) => e.name == value);
}

@freezed
abstract class Exercise with _$Exercise {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Exercise({
    required String id,
    required String name,
    required MuscleGroup muscleGroup,
    required EquipmentType equipmentType,
    @JsonKey(defaultValue: false) required bool isDefault,
    String? description,
    String? formTips,
    String? imageStartUrl,
    String? imageEndUrl,
    String? userId,
    DateTime? deletedAt,
    required DateTime createdAt,
    // Phase 24c — `true` for the 20 curated bodyweight exercises (pull-ups,
    // dips, push-ups, pistol squats, etc.) where `effective_load =
    // profile.bodyweight_kg + sets.weight`. `false` for every other exercise
    // (loaded barbell/dumbbell, isolation, cardio, isometrics) so the XP
    // calculator carries set weight through unchanged. Defaults to false so
    // legacy cache rows that pre-date this column deserialize safely; the
    // Hive cache version bump in HiveService forces a one-shot wipe so the
    // first post-upgrade fetch repopulates with authoritative server values.
    @Default(false) bool usesBodyweightLoad,
    // Phase 26e — per-body-part XP share for this exercise, e.g.
    // `{"chest": 0.70, "shoulders": 0.20, "arms": 0.10}`. Keys are
    // `BodyPart.dbValue` tokens; values sum to ~1.0 (server-side invariant).
    // Used by `primaryBodyPartsForSet` to decide which body parts a set
    // counts toward in the weekly Engajamento view. Nullable for legacy
    // rows + non-strength exercises; consumers fall back to
    // `muscle_group` when null.
    @JsonKey(name: 'xp_attribution') Map<String, num>? xpAttribution,
  }) = _Exercise;

  factory Exercise.fromJson(Map<String, dynamic> json) =>
      _$ExerciseFromJson(json);
}
