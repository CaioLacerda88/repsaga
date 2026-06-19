/// Integration tests for the Phase 18d Stage 1 `vitality-nightly` Edge Function.
///
/// What these tests pin:
///
/// 1. **EWMA trajectory** — over a four-week training history with a known
///    weekly volume profile, the nightly job's per-body-part `vitality_ewma`
///    must converge to within 5% of the closed-form expected value computed
///    from the same asymmetric α (`α_up=1-exp(-7/14)`, `α_down=1-exp(-7/42)`).
///
/// 2. **Peak monotonicity** — `vitality_peak` is the running maximum of
///    `vitality_ewma`. A late-cycle deload (low weekly volume) must NOT
///    regress peak.
///
/// 3. **Idempotency** — calling the recompute twice for the same UTC day is a
///    no-op the second time. As of migration 00082 the dedup authority is
///    `body_part_progress.last_vitality_date` (per-body-part, first-writer-
///    wins), NOT the `vitality_runs (user_id, run_date)` PK — `vitality_runs`
///    survives only as an advisory audit log. The contract pinned here is that
///    a second same-day step does NOT advance `vitality_ewma`.
///
/// 4. **Service-role auth gate** — anonymous and end-user JWTs are rejected
///    with 401. Only the project's service-role key is accepted.
///
/// How time is simulated: rather than waiting four real weeks, we drive
/// four sequential nightly runs back-to-back. Each iteration we:
///   a. WIPE prior `xp_events` for this user (so the prior week's volume
///      doesn't bleed into the current week's `weekly_volume` aggregation —
///      the function's window is `now() - 7d`, all of which is "today").
///   b. WIPE prior `vitality_runs` for this user (so the upcoming
///      invocation isn't dedup'd as "already ran today" — same calendar
///      day, but representing a different simulated week).
///   c. Seed one week's worth of xp_events at `occurred_at = now() - 1d`
///      (well within the 7d window).
///   d. Invoke the Edge Function. The PRIOR `(ewma, peak)` persisted on
///      `body_part_progress` IS the prior step's state — that's the
///      trajectory we're driving forward.
///   e. Read `body_part_progress`, assert against the expected EWMA.
///
/// This compresses 28 simulated days into one real-time second while still
/// pinning the asymmetric-α formula end-to-end (PG migration applies
/// numeric(14,4) precision; supabase-js stringifies `numeric` columns as
/// strings; the function parses them back to JS numbers — all real I/O).
///
/// Each test creates a fresh isolated user and tears it down at the end.
///
/// Run: flutter test --tags integration test/integration/rpg_vitality_nightly_test.dart
@Tags(['integration'])
library;

// Test helpers accept Supabase admin clients as `dynamic` to avoid leaking
// admin-vs-user client typing into the non-test typed surface. Production
// code uses the strongly-typed `SupabaseClient` API everywhere.
// ignore_for_file: avoid_dynamic_calls

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'rpg_integration_setup.dart';

// ---------------------------------------------------------------------------
// Constants — must mirror supabase/functions/vitality-nightly/index.ts
// ---------------------------------------------------------------------------
//
// We keep them inlined here (not imported) on purpose: the integration test
// is the contract pin. If the Edge Function silently changes its α, this
// test fails and forces a deliberate update on both sides.
const double kTauUpDays = 14.0;
const double kTauDownDays = 42.0;
const double kSamplePeriodDays = 7.0;
final double kAlphaUp = 1 - math.exp(-kSamplePeriodDays / kTauUpDays);
final double kAlphaDown = 1 - math.exp(-kSamplePeriodDays / kTauDownDays);

/// Edge Function URL on the local Supabase stack. `npx supabase start`
/// auto-serves all functions under this prefix.
const String kEdgeUrl = '$kSupabaseUrl/functions/v1/vitality-nightly';

/// Tolerance for EWMA assertions (relative). Spec §13.3 example reaches a
/// peak around 9850 with steady-state ewma ~8420 — 5% absolute is well
/// within the noise budget the UI four-state collapse can tolerate.
const double kRelTol = 0.05;

void main() {
  final runId = DateTime.now().millisecondsSinceEpoch;
  var testIdx = 0;

  TestUser? currentUser;

  Future<TestUser> freshUser() async {
    final idx = testIdx++;
    final u = await createTestUser('rpg-vit-$runId-$idx@test.local');
    currentUser = u;
    return u;
  }

  tearDown(() async {
    if (currentUser != null) {
      await deleteTestUser(currentUser!.userId);
      currentUser = null;
    }
  });

  // -------------------------------------------------------------------------
  // 1. Service-role auth gate
  // -------------------------------------------------------------------------

  group('vitality-nightly auth gate', () {
    test('anonymous request returns 401', () async {
      final res = await http.post(
        Uri.parse(kEdgeUrl),
        headers: {'Content-Type': 'application/json'},
        body: '{}',
      );
      expect(
        res.statusCode,
        401,
        reason:
            'Edge Function must reject unauthenticated POST. '
            'Got ${res.statusCode}: ${res.body}',
      );
    });

    test('anon-key request (not service-role) returns 401', () async {
      final res = await http.post(
        Uri.parse(kEdgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kSupabaseAnonKey',
        },
        body: '{}',
      );
      expect(res.statusCode, 401);
    });

    test('end-user JWT (not service-role) returns 401', () async {
      // A real signed-in user's access token must be rejected — the nightly
      // job is a server-only operation and must not be triggerable by any
      // authenticated client.
      final user = await freshUser();
      final res = await http.post(
        Uri.parse(kEdgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${user.accessToken}',
        },
        body: '{}',
      );
      expect(
        res.statusCode,
        401,
        reason:
            'End-user JWT must be rejected (not service-role). '
            'Got ${res.statusCode}: ${res.body}',
      );
    });

    test('service-role key is accepted (200)', () async {
      // No active users → empty run, but still 2xx.
      final res = await http.post(
        Uri.parse(kEdgeUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $kSupabaseServiceRoleKey',
        },
        body: jsonEncode({'source': 'integration_test'}),
      );
      expect(
        res.statusCode,
        200,
        reason: 'service-role must be authorized. Body: ${res.body}',
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      expect(body['ok'], true);
    });
  });

  // -------------------------------------------------------------------------
  // 2. EWMA trajectory: rebuild → steady-state → deload
  // -------------------------------------------------------------------------

  group('vitality-nightly EWMA trajectory', () {
    /// Four-week trajectory:
    ///   Week 1 (oldest): 1000 chest XP   — building from zero
    ///   Week 2:          1000 chest XP   — same
    ///   Week 3:          1000 chest XP   — same
    ///   Week 4 (newest): 1000 chest XP   — same
    ///
    /// Closed-form (α_up applies because each weekly_volume >= prior_ewma):
    ///   E0=0, P0=0
    ///   E1 = α_up * 1000 + (1-α_up) * 0       ≈ 393.47
    ///   E2 = α_up * 1000 + (1-α_up) * E1      ≈ 632.12
    ///   E3 = α_up * 1000 + (1-α_up) * E2      ≈ 776.87
    ///   E4 = α_up * 1000 + (1-α_up) * E3      ≈ 864.66
    ///   Peak after week 4 ≈ 864.66 (== E4, monotone since each step is up).
    ///
    /// Critically, week N's snapshot only sees week N's xp_events because
    /// the Edge Function pulls `xp_events WHERE occurred_at >= now()-7d`.
    /// We backdate occurred_at so each weekly run sees exactly that week.
    test(
      'rebuild trajectory: 4 weeks of steady chest training converges to closed-form EWMA',
      () async {
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        const weeklyChestXp = 1000.0;
        var expectedEwma = 0.0;
        var expectedPeak = 0.0;

        for (var week = 1; week <= 4; week++) {
          // Clear the per-bp guard (00082) so the upcoming invocation isn't
          // deduped as "already stepped today". We drive 4 simulated weekly
          // runs back-to-back on the same real calendar day; the production
          // guard is `body_part_progress.last_vitality_date`, so we reset it
          // each iteration to advance the trajectory. (vitality_runs is now
          // an advisory audit log, not the dedup authority — wiping it is no
          // longer what unblocks a re-step, but we clear it too to keep the
          // audit table clean across simulated days.)
          await _clearVitalityGuard(adminClient, user.userId);
          await adminClient
              .from('vitality_runs')
              .delete()
              .eq('user_id', user.userId);
          // Wipe xp_events so this week's volume doesn't include prior
          // weeks' attribution.
          await adminClient
              .from('xp_events')
              .delete()
              .eq('user_id', user.userId);

          // Seed this week's event INSIDE the 7-day aggregation window.
          await _seedXpEvent(
            adminClient: adminClient,
            userId: user.userId,
            occurredAt: DateTime.now().toUtc().subtract(
              const Duration(days: 1),
            ),
            attribution: {'chest': weeklyChestXp},
          );

          // Invoke nightly.
          final res = await _invokeNightly();
          expect(res.statusCode, 200, reason: 'week $week: ${res.body}');

          // Compute the expected EWMA for this step. Since weeklyVolume
          // (1000) >= priorEwma in every step of a monotone rebuild, α_up
          // applies throughout.
          final newEwma =
              kAlphaUp * weeklyChestXp + (1 - kAlphaUp) * expectedEwma;
          expectedEwma = newEwma;
          expectedPeak = math.max(expectedPeak, newEwma);

          // Read the actual chest row.
          final actualEwma = await _readVitalityEwma(
            adminClient,
            user.userId,
            'chest',
          );
          final actualPeak = await _readVitalityPeak(
            adminClient,
            user.userId,
            'chest',
          );

          expect(
            (actualEwma - expectedEwma).abs() / math.max(expectedEwma, 1e-9),
            lessThan(kRelTol),
            reason:
                'Week $week: chest ewma actual=$actualEwma '
                'expected=$expectedEwma (rel '
                '${((actualEwma - expectedEwma).abs() / expectedEwma * 100).toStringAsFixed(2)}%)',
          );
          expect(
            (actualPeak - expectedPeak).abs() / math.max(expectedPeak, 1e-9),
            lessThan(kRelTol),
            reason:
                'Week $week: chest peak actual=$actualPeak '
                'expected=$expectedPeak',
          );
        }

        // After 4 weeks of steady 1000-volume rebuild, EWMA should sit
        // around 864.66 — the asymptotic approach to the true mean (1000)
        // discounted by τ_up=14d at weekly samples.
        expect(
          expectedEwma,
          greaterThan(800),
          reason: 'sanity check on closed-form math',
        );
        expect(expectedEwma, lessThan(900));
      },
    );

    /// Deload at the end: 3 weeks of high volume, then 1 week of zero
    /// volume (no events). EWMA must DROP per α_down; peak must NOT regress.
    test(
      'deload preserves peak even as ewma decays',
      () async {
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        // Three rebuild weeks, then one deload week.
        final weeklyVolumes = [1000.0, 1000.0, 1000.0, 0.0];

        var expectedEwma = 0.0;
        var expectedPeak = 0.0;
        var peakAtEndOfWeek3 = 0.0;

        for (var i = 0; i < weeklyVolumes.length; i++) {
          final volume = weeklyVolumes[i];

          // Reset the per-bp guard (00082) to advance to the next simulated
          // day; clear the advisory audit log too.
          await _clearVitalityGuard(adminClient, user.userId);
          await adminClient
              .from('vitality_runs')
              .delete()
              .eq('user_id', user.userId);
          await adminClient
              .from('xp_events')
              .delete()
              .eq('user_id', user.userId);

          // Only seed an event when the week has volume — a "deload week"
          // means zero xp_events, which the function aggregates as 0.
          if (volume > 0) {
            await _seedXpEvent(
              adminClient: adminClient,
              userId: user.userId,
              occurredAt: DateTime.now().toUtc().subtract(
                const Duration(days: 1),
              ),
              attribution: {'chest': volume},
            );
          }

          final res = await _invokeNightly();
          expect(res.statusCode, 200, reason: 'week ${i + 1}: ${res.body}');

          // Closed-form: α_up when volume >= ewma, α_down otherwise.
          final alpha = volume >= expectedEwma ? kAlphaUp : kAlphaDown;
          expectedEwma = alpha * volume + (1 - alpha) * expectedEwma;
          expectedPeak = math.max(expectedPeak, expectedEwma);

          if (i == 2) {
            peakAtEndOfWeek3 = expectedPeak;
          }
        }

        // After deload, ewma must have dropped from week 3's peak but
        // peak itself must remain pinned to week 3.
        final actualEwma = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        final actualPeak = await _readVitalityPeak(
          adminClient,
          user.userId,
          'chest',
        );

        expect(
          actualEwma,
          lessThan(peakAtEndOfWeek3),
          reason:
              'After deload, ewma ($actualEwma) must be lower than peak '
              '($peakAtEndOfWeek3)',
        );
        expect(
          (actualPeak - peakAtEndOfWeek3).abs() / peakAtEndOfWeek3,
          lessThan(kRelTol),
          reason:
              'Peak must NOT regress on deload. Expected ~$peakAtEndOfWeek3, '
              'got $actualPeak',
        );
        expect(
          (actualEwma - expectedEwma).abs() / math.max(expectedEwma, 1e-9),
          lessThan(kRelTol),
          reason:
              'Ewma trajectory drifted: expected=$expectedEwma actual=$actualEwma',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  // -------------------------------------------------------------------------
  // 3. Deload-week active-pool fix (UNION decay branch)
  //
  // Acceptance check from WIP Stage 1 architectural fix:
  //   "active-users pool now UNIONs xp_events past 7d with
  //    body_part_progress.vitality_ewma > 0 so deload weeks still get
  //    decay applied (spec §8.2 compliance)."
  //
  // This test exercises the DECAY-ONLY branch of the UNION: the user has
  // vitality_ewma > 0 on body_part_progress but ZERO xp_events in the
  // past 7d. If the Edge Function only queries xp_events for its user list,
  // this user is invisible and their EWMA freezes instead of decaying.
  // -------------------------------------------------------------------------

  group('vitality-nightly deload-week decay (UNION pool fix)', () {
    test(
      'user with vitality_ewma > 0 but no xp_events past 7d still gets α_down decay',
      () async {
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        // Directly seed a body_part_progress row with a non-zero EWMA and
        // peak — simulating a user who trained previously but has had no
        // xp_events in the past 7 days (deload week / full layoff).
        const priorEwma = 800.0;
        const priorPeak = 900.0;
        await adminClient.from('body_part_progress').upsert({
          'user_id': user.userId,
          'body_part': 'legs',
          'vitality_ewma': priorEwma,
          'vitality_peak': priorPeak,
          'total_xp': 0,
          'rank': 1,
        }, onConflict: 'user_id,body_part');

        // No xp_events seeded — this user must still be picked up via the
        // body_part_progress.vitality_ewma > 0 branch of the UNION.

        final res = await _invokeNightly();
        expect(
          res.statusCode,
          200,
          reason: 'nightly should succeed: ${res.body}',
        );

        final actualEwma = await _readVitalityEwma(
          adminClient,
          user.userId,
          'legs',
        );
        final actualPeak = await _readVitalityPeak(
          adminClient,
          user.userId,
          'legs',
        );

        // With weekly_volume = 0 and prior_ewma = 800, α_down applies:
        //   new_ewma = α_down * 0 + (1 - α_down) * 800 = (1 - α_down) * 800
        final expectedEwma = (1 - kAlphaDown) * priorEwma;

        // EWMA must have decayed (not frozen at priorEwma).
        expect(
          actualEwma,
          lessThan(priorEwma),
          reason:
              'EWMA must decay for a deload week. Expected ~$expectedEwma, '
              'got $actualEwma (prior was $priorEwma). '
              'If EWMA did not change, the user was not found via the '
              'vitality_ewma > 0 pool — the UNION fix is missing.',
        );

        // Decay must be within 5% of the closed-form α_down value.
        expect(
          (actualEwma - expectedEwma).abs() / expectedEwma,
          lessThan(kRelTol),
          reason:
              'Decay magnitude wrong: expected=$expectedEwma actual=$actualEwma',
        );

        // Peak must NOT regress on a deload week.
        expect(
          (actualPeak - priorPeak).abs(),
          lessThan(0.01),
          reason:
              'Peak must be preserved on deload. '
              'Expected $priorPeak, got $actualPeak',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  });

  // -------------------------------------------------------------------------
  // 4. Idempotency
  // -------------------------------------------------------------------------

  group('vitality-nightly idempotency', () {
    test(
      'second same-day recompute does NOT double-step vitality_ewma',
      () async {
        // The 00082 contract: the per-body-part `last_vitality_date` guard
        // makes a second same-UTC-day step a no-op. This pins the EWMA-stable
        // behavior directly (NOT the old "one vitality_runs row" proxy) —
        // exactly what a save-then-nightly collision on the same day must
        // guarantee.
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        // Seed one week of activity in the past 7 days.
        await _seedXpEvent(
          adminClient: adminClient,
          userId: user.userId,
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          attribution: {'chest': 500.0},
        );

        // First invocation — steps chest.
        final r1 = await _invokeNightly();
        expect(r1.statusCode, 200);
        final body1 = jsonDecode(r1.body) as Map<String, dynamic>;
        expect(body1['processed'], greaterThanOrEqualTo(1));

        final ewmaAfterFirst = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        expect(
          ewmaAfterFirst,
          greaterThan(0),
          reason: 'First invocation must populate ewma',
        );

        // Second invocation immediately — same UTC date, guard NOT cleared.
        final r2 = await _invokeNightly();
        expect(r2.statusCode, 200);

        // EWMA must be identical (no double-application) — the per-bp guard
        // short-circuited the second step.
        final ewmaAfterSecond = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        expect(
          (ewmaAfterSecond - ewmaAfterFirst).abs(),
          lessThan(0.001),
          reason:
              'Same-day re-step must not change ewma (per-bp last_vitality_date '
              'guard). first=$ewmaAfterFirst second=$ewmaAfterSecond',
        );
      },
    );

    test(
      'vitality_runs survives as an advisory audit log — one row per (user, day)',
      () async {
        // vitality_runs is no longer the dedup authority (00082), but the
        // nightly job still records ONE advisory audit row per user per UTC
        // day (ON CONFLICT DO NOTHING). This pins that the audit log is still
        // written and de-duplicated by its PK.
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        await _seedXpEvent(
          adminClient: adminClient,
          userId: user.userId,
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          attribution: {'back': 200.0},
        );

        // Two back-to-back invocations.
        await _invokeNightly();
        await _invokeNightly();

        // vitality_runs row count must be exactly 1 for this user.
        final rows = await adminClient
            .from('vitality_runs')
            .select('user_id, run_date')
            .eq('user_id', user.userId);
        expect(
          (rows as List).length,
          1,
          reason:
              'Exactly one advisory vitality_runs row per (user, day). Got '
              '${rows.length}.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // 5. Save-time recompute (00082) — vitality moves IMMEDIATELY at save, and
  //    the nightly job then SKIPS the parts the save already stepped today
  //    (first-writer-wins at body-part granularity).
  // -------------------------------------------------------------------------

  group('vitality save-time recompute', () {
    test(
      'recompute_vitality_for_user moves vitality immediately for touched bps',
      () async {
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        // Day-0 user, no body_part_progress rows. Seed this session's volume.
        await _seedXpEvent(
          adminClient: adminClient,
          userId: user.userId,
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          attribution: {'chest': 600.0},
        );

        final before = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        expect(before, 0.0, reason: 'no chest row yet → ewma reads 0');

        // The save path PERFORMs exactly this with the session-touched bps.
        await adminClient.rpc(
          'recompute_vitality_for_user',
          params: {
            'p_user': user.userId,
            'p_body_parts': ['chest'],
          },
        );

        final after = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        final expected = kAlphaUp * 600.0; // prior 0 → α_up rebuild
        expect(
          after,
          greaterThan(0),
          reason: 'save-time recompute must move chest vitality immediately',
        );
        expect(
          (after - expected).abs() / expected,
          lessThan(kRelTol),
          reason:
              'save-time ewma must match closed-form: '
              'expected≈$expected got=$after',
        );
      },
    );

    test(
      'nightly skips a bp already stepped today by a save (first-writer-wins)',
      () async {
        final user = await freshUser();
        final adminClient = serviceRoleClient();

        await _seedXpEvent(
          adminClient: adminClient,
          userId: user.userId,
          occurredAt: DateTime.now().toUtc().subtract(const Duration(days: 1)),
          attribution: {'chest': 600.0, 'back': 300.0},
        );

        // Save path steps ONLY chest (the session's touched bp).
        await adminClient.rpc(
          'recompute_vitality_for_user',
          params: {
            'p_user': user.userId,
            'p_body_parts': ['chest'],
          },
        );
        final chestAfterSave = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        expect(chestAfterSave, greaterThan(0));

        // Nightly runs (NULL bps → all active parts). It must SKIP chest
        // (last_vitality_date already today) but still step back.
        final res = await _invokeNightly();
        expect(res.statusCode, 200, reason: res.body);

        final chestAfterNightly = await _readVitalityEwma(
          adminClient,
          user.userId,
          'chest',
        );
        expect(
          (chestAfterNightly - chestAfterSave).abs(),
          lessThan(0.001),
          reason:
              'chest already stepped at save time → nightly must not '
              'double-step it. save=$chestAfterSave nightly=$chestAfterNightly',
        );

        final backAfterNightly = await _readVitalityEwma(
          adminClient,
          user.userId,
          'back',
        );
        expect(
          backAfterNightly,
          greaterThan(0),
          reason:
              'back was NOT stepped at save time → nightly must step it now',
        );
      },
    );
  });
}

/// Nulls `body_part_progress.last_vitality_date` for every row of [userId] so
/// the next recompute treats each bp as "not yet stepped today". The 00082
/// guard is per-bp UTC-date; the trajectory tests drive several simulated
/// days within one real day, so we reset the guard between them.
Future<void> _clearVitalityGuard(dynamic adminClient, String userId) async {
  await (adminClient as dynamic)
      .from('body_part_progress')
      .update({'last_vitality_date': null})
      .eq('user_id', userId);
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Future<http.Response> _invokeNightly({Map<String, dynamic>? body}) {
  return http.post(
    Uri.parse(kEdgeUrl),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $kSupabaseServiceRoleKey',
    },
    body: jsonEncode(body ?? {'source': 'integration_test'}),
  );
}

/// Inserts a single xp_events row with the given attribution payload.
///
/// We seed xp_events directly (bypassing record_set_xp) because the
/// trajectory we want to assert is the EWMA over weekly_volume; the volume
/// signal is read from xp_events.attribution and the upstream record_set_xp
/// path is already covered by `rpg_record_set_xp_test.dart`. Decoupling the
/// nightly test from XP calculation keeps it focused on the EWMA contract.
///
/// We pick `event_type='cardio_session'` (a valid v2 enum value) to
/// sidestep the `xp_events_set_event_has_fks` CHECK constraint that
/// requires set_id+session_id when event_type='set'. The vitality-nightly
/// worker doesn't filter by event_type — it aggregates `attribution`
/// across all of a user's events in the past 7 days.
Future<void> _seedXpEvent({
  required dynamic adminClient,
  required String userId,
  required DateTime occurredAt,
  required Map<String, double> attribution,
}) async {
  final totalXp = attribution.values.fold<double>(0, (a, b) => a + b);
  await (adminClient as dynamic).from('xp_events').insert({
    'user_id': userId,
    'event_type': 'cardio_session',
    'set_id': null,
    'session_id': null,
    'occurred_at': occurredAt.toIso8601String(),
    'total_xp': totalXp,
    'attribution': attribution,
    'payload': {'synthetic': true, 'source': 'vitality_nightly_test'},
  });
}

Future<double> _readVitalityEwma(
  dynamic adminClient,
  String userId,
  String bodyPart,
) async {
  final row = await (adminClient as dynamic)
      .from('body_part_progress')
      .select('vitality_ewma')
      .eq('user_id', userId)
      .eq('body_part', bodyPart)
      .maybeSingle();
  if (row == null) return 0.0;
  return ((row as Map<String, dynamic>)['vitality_ewma'] as num).toDouble();
}

Future<double> _readVitalityPeak(
  dynamic adminClient,
  String userId,
  String bodyPart,
) async {
  final row = await (adminClient as dynamic)
      .from('body_part_progress')
      .select('vitality_peak')
      .eq('user_id', userId)
      .eq('body_part', bodyPart)
      .maybeSingle();
  if (row == null) return 0.0;
  return ((row as Map<String, dynamic>)['vitality_peak'] as num).toDouble();
}
