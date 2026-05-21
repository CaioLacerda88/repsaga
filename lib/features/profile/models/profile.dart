// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// User-declared gender. Phase 29 v2 Refinement #1 uses this to pick the
/// per-lift Symmetric Strength tier table (male tables = Symmetric Strength
/// reference data; female tables = strengthlevel.com snapshot 2026-05-20).
///
/// NULL on the [Profile] (`gender == null`) and [Gender.other] both fall
/// back to the male tier table — this is the documented backward-compat
/// path for users who haven't set their gender yet. Documented in
/// `docs/PROJECT.md` Phase 29 PR 2 inventory.
///
/// Serialized as the snake-case string token (`male` / `female` / `other`)
/// matching the SQL `profiles.gender` CHECK constraint.
enum Gender {
  @JsonValue('male')
  male,
  @JsonValue('female')
  female,
  @JsonValue('other')
  other,
}

@freezed
abstract class Profile with _$Profile {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Profile({
    required String id,
    String? displayName,
    String? fitnessLevel,
    @Default('kg') String weightUnit,
    @Default(3) int trainingFrequencyPerWeek,
    @Default('en') String locale,
    DateTime? createdAt,
    // Phase 24c — opt-in bodyweight (user-supplied via profile settings or
    // active-workout lazy prompt). Nullable: a missing value means the user
    // has not provided one yet, in which case `record_xp` falls back to a
    // bodyweight contribution of zero (entered weight only). Stored as kg
    // server-side regardless of `weightUnit` (UI layer handles conversion).
    double? bodyweightKg,
    // Phase 29 v2 — user-declared gender. Drives the per-lift Symmetric
    // Strength tier table selection (male = Symmetric Strength; female =
    // strengthlevel.com snapshot). NULL and [Gender.other] both fall back
    // to the male table — same backward-compat semantics as the Python
    // sim's `female=False` default. Settable from profile settings.
    Gender? gender,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
