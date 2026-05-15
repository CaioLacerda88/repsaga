// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

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
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}
