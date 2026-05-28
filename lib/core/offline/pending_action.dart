// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'pending_action.freezed.dart';
part 'pending_action.g.dart';

/// Coarse classification of why a queued action last failed.
///
/// This is computed by [SyncErrorMapper.classifyCategory] at the moment a
/// drain attempt fails and stored on the action so the [PendingSyncSheet]
/// can pick the right CTA without re-classifying:
///
/// - [SyncErrorCategory.none] / [SyncErrorCategory.network] /
///   [SyncErrorCategory.transient] / [SyncErrorCategory.unknown] → retry is
///   meaningful; show "Tentar novamente". `unknown` is intentionally NOT
///   terminal — a genuinely unknown error class might be a one-off plugin
///   crash that retry resolves, and forcing "Dispensar" removes the user's
///   only recovery path. If the underlying issue is structural, the next
///   attempt will surface a more specific exception class that the mapper
///   routes to [structural].
/// - [SyncErrorCategory.structural] / [SyncErrorCategory.session] → retry
///   will not resolve it (FK violation, type-cast crash, expired session);
///   show "Dispensar" + branded copy directing the user to support
///   (BUG-008).
enum SyncErrorCategory {
  /// Default for items that have not failed yet.
  none,

  /// SocketException / TimeoutException / HttpException / NetworkException.
  network,

  /// Server-side issue likely to clear up (5xx, generic flake).
  transient,

  /// Client-side data shape problem — FK violation, type cast, RLS denial.
  /// Retrying without code changes won't help.
  structural,

  /// Authentication / token problem.
  session,

  /// Catch-all: an unexpected exception class. Treated as non-terminal —
  /// the user keeps a retry CTA. See doc comment above for rationale.
  unknown,
}

/// Discriminated union of actions that can be queued for offline sync.
///
/// Each variant carries raw JSON maps so we avoid serialisation issues
/// with typed models (e.g. `WorkoutExercise.exercise` is excluded from
/// `toJson`). The RPC and repository calls already accept these shapes.
///
/// **Dependency ordering (BUG-002):** every variant carries an optional
/// [dependsOn] list of parent action IDs. The drain holds an action back
/// until every ID in [dependsOn] has either been dequeued (parent
/// committed) or no longer exists in the queue (parent dismissed). Children
/// of the same parent batch (e.g. a `PendingUpsertRecords` whose `set_id`
/// references rows that the parent `PendingSaveWorkout` is about to insert)
/// MUST be enqueued with the parent's `id` in [dependsOn] — otherwise
/// replay can race the FK and we get `*_fkey` constraint violations.
///
/// **`lastError` is dev-facing only (BUG-042):** the field stores a raw
/// `.toString()` of the most recent failure for log inspection and Sentry
/// breadcrumbs. It MUST NOT be rendered in any UI. UI surfaces consume
/// errors via [SyncErrorMapper.toUserMessage] which produces a localized,
/// schema-free message keyed by exception class.
///
/// **`errorCategory` drives UI CTA selection (BUG-008):** populated by the
/// drain code via [SyncErrorMapper.classifyCategory] when an attempt fails.
/// The pending-sync sheet reads it to decide between retry and dismiss.
@Freezed(unionKey: 'type')
sealed class PendingAction with _$PendingAction {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory PendingAction.saveWorkout({
    required String id,
    required Map<String, dynamic> workoutJson,
    required List<Map<String, dynamic>> exercisesJson,
    required List<Map<String, dynamic>> setsJson,
    required String userId,
    required DateTime queuedAt,
    @Default(0) int retryCount,
    String? lastError,
    @Default(<String>[]) List<String> dependsOn,
    @Default(SyncErrorCategory.none) SyncErrorCategory errorCategory,
  }) = PendingSaveWorkout;

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory PendingAction.upsertRecords({
    required String id,
    required List<Map<String, dynamic>> recordsJson,
    @Default('') String userId,
    required DateTime queuedAt,
    @Default(0) int retryCount,
    String? lastError,
    @Default(<String>[]) List<String> dependsOn,
    @Default(SyncErrorCategory.none) SyncErrorCategory errorCategory,
  }) = PendingUpsertRecords;

  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory PendingAction.markRoutineComplete({
    required String id,
    required String planId,
    required String routineId,
    required String workoutId,
    required DateTime queuedAt,
    @Default(0) int retryCount,
    String? lastError,
    @Default(<String>[]) List<String> dependsOn,
    @Default(SyncErrorCategory.none) SyncErrorCategory errorCategory,
  }) = PendingMarkRoutineComplete;

  factory PendingAction.fromJson(Map<String, dynamic> json) =>
      _$PendingActionFromJson(json);
}
