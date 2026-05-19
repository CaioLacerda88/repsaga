import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../../../core/data/base_repository.dart';
import 'models/weekly_plan.dart';

class WeeklyPlanRepository extends BaseRepository {
  WeeklyPlanRepository(this._client, {super.recoveryRecorder});

  final supabase.SupabaseClient _client;

  supabase.SupabaseQueryBuilder get _plans => _client.from('weekly_plans');

  /// Get the plan for a specific week (identified by Monday date).
  Future<WeeklyPlan?> getPlanForWeek(String userId, DateTime weekStart) {
    return mapException(() async {
      final mondayStr = _toDateString(weekStart);
      final data = await _plans
          .select()
          .eq('user_id', userId)
          .eq('week_start', mondayStr)
          .maybeSingle();
      if (data == null) return null;
      return WeeklyPlan.fromJson(data);
    });
  }

  /// Get the most recent plan before a given week (for auto-populate).
  Future<WeeklyPlan?> getPreviousWeekPlan(String userId, DateTime weekStart) {
    return mapException(() async {
      final mondayStr = _toDateString(weekStart);
      final data = await _plans
          .select()
          .eq('user_id', userId)
          .lt('week_start', mondayStr)
          .order('week_start', ascending: false)
          .limit(1)
          .maybeSingle();
      if (data == null) return null;
      return WeeklyPlan.fromJson(data);
    });
  }

  /// Create or update the plan for a given week.
  ///
  /// **`onConflict` is required** — `weekly_plans` has `UNIQUE (user_id,
  /// week_start)` (migration 00011). Without naming that constraint as the
  /// conflict target, PostgREST falls back to the primary key (`id`), which
  /// the payload does not include — so the upsert silently becomes a plain
  /// INSERT that violates the unique constraint on every save after the
  /// first one of the week. The first session works, subsequent edits all
  /// fail with "duplicate key", `AsyncValue.guard` catches the throw,
  /// state goes to AsyncError, and the editor's "saved" toast lies. Adding
  /// `onConflict: 'user_id,week_start'` makes PostgREST emit
  /// `ON CONFLICT (user_id, week_start) DO UPDATE` and the upsert behaves
  /// as advertised.
  Future<WeeklyPlan> upsertPlan({
    required String userId,
    required DateTime weekStart,
    required List<BucketRoutine> routines,
  }) {
    return mapException(() async {
      final data = await _plans
          .upsert({
            'user_id': userId,
            'week_start': _toDateString(weekStart),
            'routines': routines.map((r) => r.toJson()).toList(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'user_id,week_start')
          .select()
          .single();
      return WeeklyPlan.fromJson(data);
    });
  }

  // markRoutineComplete is gone (26e): the 00063 save_workout RPC owns
  // the bucket find-or-create entirely server-side. Callers `ref.invalidate
  // (weeklyPlanProvider)` after save; the next read fetches the row that
  // the RPC already updated in the same transaction as the workout insert.

  /// Delete a plan entirely (used for "Clear Week").
  Future<void> deletePlan(String planId) {
    return mapException(() async {
      await _plans.delete().eq('id', planId);
    });
  }

  /// Format a DateTime as a date-only string for Supabase DATE columns.
  static String _toDateString(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
