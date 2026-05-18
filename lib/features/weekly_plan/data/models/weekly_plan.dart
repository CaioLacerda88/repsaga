// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'weekly_plan.freezed.dart';
part 'weekly_plan.g.dart';

/// A single routine entry in the weekly bucket.
@freezed
abstract class BucketRoutine with _$BucketRoutine {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory BucketRoutine({
    required String routineId,
    required int order,
    String? completedWorkoutId,
    DateTime? completedAt,
    @Default(false) bool isSpontaneous,
  }) = _BucketRoutine;

  factory BucketRoutine.fromJson(Map<String, dynamic> json) =>
      _$BucketRoutineFromJson(json);
}

/// The weekly plan for a given week.
@freezed
abstract class WeeklyPlan with _$WeeklyPlan {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory WeeklyPlan({
    required String id,
    required String userId,
    required DateTime weekStart,
    @Default(<BucketRoutine>[]) List<BucketRoutine> routines,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) = _WeeklyPlan;

  factory WeeklyPlan.fromJson(Map<String, dynamic> json) =>
      _$WeeklyPlanFromJson(json);
}
