/// Shared helpers for Phase 18a RPG integration tests.
///
/// These tests require a running local Supabase instance:
///   `npx supabase start`
///
/// They are NOT run by the standard `flutter test` unit/widget suite.
/// Run them explicitly:
///   export PATH="/c/flutter/bin:$PATH"
///   flutter test test/integration/
///
/// Each test creates an isolated user via Supabase Admin Auth API, runs
/// the scenario, and deletes the user in tearDown. No shared state between
/// tests.
///
/// **Lint suppression:** This file deliberately uses `dynamic` for the
/// `ExerciseDef` argument to `seedMultiExerciseWorkout` to avoid an import
/// cycle between integration setup helpers and per-test fixtures. The cycle
/// avoidance is documented inline at the call site. Production code uses
/// `requireField` / typed casts everywhere; the lint stays enabled there.
library;

// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

// ---------------------------------------------------------------------------
// Local Supabase credentials (matches test/e2e/.env.local)
// ---------------------------------------------------------------------------

const String kSupabaseUrl = 'http://127.0.0.1:54321';
const String kSupabaseAnonKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9'
    '.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0';
const String kSupabaseServiceRoleKey =
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
    '.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImV4cCI6MTk4MzgxMjk5Nn0'
    '.EGIM96RAZx35lJzdJsyH-qQwv8Hdp7fsn3W0YpN81IU';

// ---------------------------------------------------------------------------
// Test user management
// ---------------------------------------------------------------------------

class TestUser {
  const TestUser({
    required this.userId,
    required this.email,
    required this.accessToken,
  });

  final String userId;
  final String email;
  final String accessToken;
}

/// Creates a temporary test user via the Supabase Admin Auth API.
/// Returns credentials needed for authenticated Supabase client calls.
Future<TestUser> createTestUser(String email) async {
  const password = 'TestPassword123!';

  // Create user via Admin API (service_role key bypasses email confirmation).
  final createRes = await http.post(
    Uri.parse('$kSupabaseUrl/auth/v1/admin/users'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $kSupabaseServiceRoleKey',
      'apikey': kSupabaseServiceRoleKey,
    },
    body: jsonEncode({
      'email': email,
      'password': password,
      'email_confirm': true,
    }),
  );

  if (createRes.statusCode != 200 && createRes.statusCode != 201) {
    throw Exception(
      'Failed to create test user $email: '
      '${createRes.statusCode} ${createRes.body}',
    );
  }

  final userId =
      (jsonDecode(createRes.body) as Map<String, dynamic>)['id'] as String;

  // Sign in to get an access token.
  final signInRes = await http.post(
    Uri.parse('$kSupabaseUrl/auth/v1/token?grant_type=password'),
    headers: {'Content-Type': 'application/json', 'apikey': kSupabaseAnonKey},
    body: jsonEncode({'email': email, 'password': password}),
  );

  if (signInRes.statusCode != 200) {
    throw Exception(
      'Failed to sign in test user $email: '
      '${signInRes.statusCode} ${signInRes.body}',
    );
  }

  final accessToken =
      (jsonDecode(signInRes.body) as Map<String, dynamic>)['access_token']
          as String;

  return TestUser(userId: userId, email: email, accessToken: accessToken);
}

/// Deletes a test user via the Admin API. Idempotent (ignores 404).
Future<void> deleteTestUser(String userId) async {
  final res = await http.delete(
    Uri.parse('$kSupabaseUrl/auth/v1/admin/users/$userId'),
    headers: {
      'Authorization': 'Bearer $kSupabaseServiceRoleKey',
      'apikey': kSupabaseServiceRoleKey,
    },
  );
  if (res.statusCode != 200 && res.statusCode != 204 && res.statusCode != 404) {
    // Silently log — don't throw in tearDown.
    // ignore: avoid_print
    print('Warning: deleteTestUser $userId returned ${res.statusCode}');
  }
}

/// Creates a [supabase.SupabaseClient] authenticated as [user].
///
/// The client is constructed with the accessToken setter so all API calls
/// include the user's JWT, satisfying the RLS policies on the RPG tables.
supabase.SupabaseClient authenticatedClient(TestUser user) {
  return supabase.SupabaseClient(
    kSupabaseUrl,
    kSupabaseAnonKey,
    accessToken: () async => user.accessToken,
  );
}

/// Creates a service-role client (bypasses RLS — use only for test setup).
supabase.SupabaseClient serviceRoleClient() {
  return supabase.SupabaseClient(kSupabaseUrl, kSupabaseServiceRoleKey);
}

// ---------------------------------------------------------------------------
// Test data seeding helpers
// ---------------------------------------------------------------------------

/// Seed data returned by [seedExercisesAndWorkout].
class SeedResult {
  const SeedResult({
    required this.workoutId,
    required this.workoutExerciseId,
    required this.exerciseId,
    required this.setIds,
    required this.exerciseSlug,
  });

  final String workoutId;
  final String workoutExerciseId;
  final String exerciseId;
  final List<String> setIds;
  final String exerciseSlug;
}

/// Looks up an exercise by slug (must be a default exercise pre-seeded by
/// migration 00040).
Future<String> exerciseIdForSlug(
  supabase.SupabaseClient adminClient,
  String slug,
) async {
  final row = await adminClient
      .from('exercises')
      .select('id')
      .eq('slug', slug)
      .single();
  return row['id'] as String;
}

/// Looks up `exercises.difficulty_mult` for [slug]. Mirrors the per-set
/// `COALESCE(difficulty_mult, 1.0)` discipline used by `record_set_xp` /
/// `record_session_xp_batch` / `_rpg_backfill_chunk` (see migration 00054)
/// so the Dart-side parity helpers can pass the same value as the SQL side.
///
/// Phase 24a Phase F: integration tests previously hardcoded `1.0` for every
/// computeSetXp call site. Once Phase D shipped, the SQL chain reads real
/// curated values from `exercises.difficulty_mult`; the Dart side must mirror.
Future<double> difficultyMultForSlug(
  supabase.SupabaseClient adminClient,
  String slug,
) async {
  final row = await adminClient
      .from('exercises')
      .select('difficulty_mult')
      .eq('slug', slug)
      .single();
  // Defensive: column is NOT NULL DEFAULT 1.0 (migration 00053), but follow
  // the same COALESCE discipline as the SQL RPCs.
  final raw = row['difficulty_mult'];
  if (raw == null) return 1.0;
  return (raw as num).toDouble();
}

/// Inserts a completed workout with [sets] completed working sets of
/// [exerciseSlug], each at [weightKg] × [reps], for [user].
///
/// Uses the service-role client to bypass RLS for setup (the workout is
/// owned by [user.userId]).
///
/// Returns a [SeedResult] with the inserted IDs.
Future<SeedResult> seedWorkout({
  required supabase.SupabaseClient adminClient,
  required String userId,
  required String exerciseSlug,
  required double weightKg,
  required int reps,
  required int numSets,
  DateTime? startedAt,
}) async {
  final ts = (startedAt ?? DateTime.now()).toUtc();

  // Look up exercise.
  final exerciseId = await exerciseIdForSlug(adminClient, exerciseSlug);

  // Insert workout.
  final workoutId = _uuid();
  await adminClient.from('workouts').insert({
    'id': workoutId,
    'user_id': userId,
    'name': 'Integration Test Workout',
    'started_at': ts.toIso8601String(),
    'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
    'is_active': false,
  });

  // Insert workout_exercise.
  final weId = _uuid();
  await adminClient.from('workout_exercises').insert({
    'id': weId,
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'order': 1,
  });

  // Insert sets.
  final setIds = <String>[];
  for (var i = 1; i <= numSets; i++) {
    final setId = _uuid();
    setIds.add(setId);
    await adminClient.from('sets').insert({
      'id': setId,
      'workout_exercise_id': weId,
      'set_number': i,
      'reps': reps,
      'weight': weightKg,
      'is_completed': true,
      'set_type': 'working',
    });
  }

  return SeedResult(
    workoutId: workoutId,
    workoutExerciseId: weId,
    exerciseId: exerciseId,
    setIds: setIds,
    exerciseSlug: exerciseSlug,
  );
}

/// Seed a workout containing multiple exercises (1 set each per the
/// definitions in `exercises`). Used by the backfill fixture so a single
/// "session" is a single workout with all exercises sharing the same
/// novelty/weekly-volume context — matching the Python sim's notion of a
/// training day.
Future<SeedResult> seedMultiExerciseWorkout({
  required supabase.SupabaseClient adminClient,
  required String userId,
  required List<dynamic> exercises, // ExerciseDef (kept dynamic to avoid cycle)
  DateTime? startedAt,
}) async {
  final ts = (startedAt ?? DateTime.now()).toUtc();
  final workoutId = _uuid();
  await adminClient.from('workouts').insert({
    'id': workoutId,
    'user_id': userId,
    'name': 'Integration Test Workout',
    'started_at': ts.toIso8601String(),
    'finished_at': ts.add(const Duration(hours: 1)).toIso8601String(),
    'is_active': false,
  });

  final setIds = <String>[];
  String? firstWorkoutExerciseId;
  String? firstExerciseId;
  String? firstExerciseSlug;

  for (var i = 0; i < exercises.length; i++) {
    // Treat the dynamic argument as a duck-typed ExerciseDef
    // ({slug, weightKg, reps, ...}).
    final ex = exercises[i] as dynamic;
    final slug = ex.slug as String;
    final weight = ex.weightKg as double;
    final reps = ex.reps as int;

    final exerciseId = await exerciseIdForSlug(adminClient, slug);
    final weId = _uuid();
    await adminClient.from('workout_exercises').insert({
      'id': weId,
      'workout_id': workoutId,
      'exercise_id': exerciseId,
      'order': i + 1,
    });

    final setId = _uuid();
    setIds.add(setId);
    await adminClient.from('sets').insert({
      'id': setId,
      'workout_exercise_id': weId,
      'set_number': 1,
      'reps': reps,
      'weight': weight,
      'is_completed': true,
      'set_type': 'working',
    });

    firstWorkoutExerciseId ??= weId;
    firstExerciseId ??= exerciseId;
    firstExerciseSlug ??= slug;
  }

  return SeedResult(
    workoutId: workoutId,
    workoutExerciseId: firstWorkoutExerciseId!,
    exerciseId: firstExerciseId!,
    setIds: setIds,
    exerciseSlug: firstExerciseSlug!,
  );
}

/// Calls `save_workout` via RPC as the authenticated user, which triggers
/// `record_set_xp` per set inside the same transaction.
Future<Map<String, dynamic>> saveWorkoutRpc({
  required supabase.SupabaseClient userClient,
  required SeedResult seed,
  required String userId,
  required double weightKg,
  required int reps,
  required int numSets,
}) async {
  // Build the JSON payloads expected by save_workout.
  final ts = DateTime.now().toUtc();
  final workoutJson = {
    'id': seed.workoutId,
    'user_id': userId,
    'name': 'Integration Test Workout',
    'finished_at': ts.toIso8601String(),
    'duration_seconds': 3600,
    'notes': null,
  };

  final exercisesJson = [
    {
      'id': seed.workoutExerciseId,
      'workout_id': seed.workoutId,
      'exercise_id': seed.exerciseId,
      'order': 1,
      'rest_seconds': null,
    },
  ];

  final setsJson = <Map<String, dynamic>>[];
  for (var i = 0; i < numSets; i++) {
    setsJson.add({
      'id': seed.setIds[i],
      'workout_exercise_id': seed.workoutExerciseId,
      'set_number': i + 1,
      'reps': reps,
      'weight': weightKg,
      'rpe': null,
      'set_type': 'working',
      'notes': null,
      'is_completed': true,
    });
  }

  final result = await userClient.rpc(
    'save_workout',
    params: {
      'p_workout': workoutJson,
      'p_exercises': exercisesJson,
      'p_sets': setsJson,
    },
  );

  return result as Map<String, dynamic>;
}

// ---------------------------------------------------------------------------
// Backfill helpers (bypass RpgRepository which requires _client.auth)
// ---------------------------------------------------------------------------

/// Run `backfill_rpg_v1` in a loop until complete, calling RPC directly on the
/// authenticated client.
///
/// The [RpgRepository] cannot be used in integration tests because it calls
/// `_client.auth.currentUser`, which throws when the client is constructed with
/// the `accessToken:` option (the pattern required for isolated test users that
/// bypass the Flutter singleton).
///
/// Returns total sets processed.
Future<int> runBackfillDirect({
  required supabase.SupabaseClient userClient,
  required String userId,
  int chunkSize = 500,
}) async {
  var totalProcessed = 0;
  const maxIterations = 5000;
  for (var i = 0; i < maxIterations; i++) {
    final result = await userClient.rpc(
      'backfill_rpg_v1',
      params: {'p_user_id': userId, 'p_chunk_size': chunkSize},
    );
    final row = _firstBackfillRow(result);
    final isComplete = (row['out_is_complete'] as bool?) ?? false;
    totalProcessed = (row['out_total_processed'] as num?)?.toInt() ?? 0;
    if (isComplete) {
      return totalProcessed;
    }
  }
  throw Exception('backfill_rpg_v1 did not converge');
}

/// Read `backfill_progress` row directly (no RpgRepository).
Future<Map<String, dynamic>?> getBackfillProgressDirect({
  required supabase.SupabaseClient userClient,
}) async {
  final row = await userClient.from('backfill_progress').select().maybeSingle();
  if (row == null) return null;
  return Map<String, dynamic>.from(row);
}

Map<String, dynamic> _firstBackfillRow(dynamic result) {
  if (result is List && result.isNotEmpty) {
    return Map<String, dynamic>.from(result.first as Map);
  }
  if (result is Map) {
    return Map<String, dynamic>.from(result);
  }
  throw Exception('Unexpected backfill RPC result shape: $result');
}

// ---------------------------------------------------------------------------
// UUID helper
// ---------------------------------------------------------------------------
//
// We use a SEQUENTIAL uuid (timestamp-prefixed counter) instead of a random
// v4 because the PG backfill chunk fetch orders sets by `(w.started_at,
// s.id)`, and the Dart reference processes them in fixture insertion order.
// Random v4 ids would tie-break differently from insertion order, breaking
// PG/Dart parity on body parts shared across exercises within a single
// workout (arms shared by bench + lat_pulldown was the visible case).
//
// Format: 8-byte timestamp (ms since epoch) || 4-byte counter || 4 random
// bytes. Mangled to look like a real RFC-4122 v4 (version + variant bits)
// so PG's `uuid` type accepts it. Sort order is monotonically increasing
// within a process for distinct calls.

int _uuidCounter = 0;

String _uuid() {
  _uuidCounter++;
  final ts = DateTime.now().toUtc().millisecondsSinceEpoch;
  final b = List<int>.filled(16, 0);
  // bytes 0-5: timestamp big-endian (48 bits — ample for current time)
  b[0] = (ts >> 40) & 0xff;
  b[1] = (ts >> 32) & 0xff;
  b[2] = (ts >> 24) & 0xff;
  b[3] = (ts >> 16) & 0xff;
  b[4] = (ts >> 8) & 0xff;
  b[5] = ts & 0xff;
  // bytes 6-7: counter (12 bits actual; high nibble forced to v4 = 0x4)
  b[6] = 0x40 | ((_uuidCounter >> 8) & 0x0f);
  b[7] = _uuidCounter & 0xff;
  // bytes 8-9: variant + counter high
  b[8] = 0x80 | ((_uuidCounter >> 16) & 0x3f);
  b[9] = (_uuidCounter >> 24) & 0xff;
  // bytes 10-15: random for uniqueness across parallel processes
  for (var i = 10; i < 16; i++) {
    b[i] = _rng.nextInt(256);
  }
  final hex = b.map((e) => e.toRadixString(16).padLeft(2, '0')).toList();
  return '${hex.sublist(0, 4).join()}-'
      '${hex.sublist(4, 6).join()}-'
      '${hex.sublist(6, 8).join()}-'
      '${hex.sublist(8, 10).join()}-'
      '${hex.sublist(10, 16).join()}';
}

final _rng = math.Random(DateTime.now().millisecondsSinceEpoch);
