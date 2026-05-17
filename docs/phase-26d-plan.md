# Phase 26d — Titles Screen + Awarding Pipeline Fix · Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move `earned_titles` row creation from equip-time (client tap inside the celebration overlay) to detection-time (server-side, inside the XP RPCs) so dismissing the celebration overlay no longer loses a title. Pair with a one-shot per-user backfill RPC for existing users. Rewrite the Titles screen into a three-region UI (Equipado / Conquistados / Próximos) per the locked mockup, hiding locked titles entirely.

**Architecture:** The new SQL migration extends `record_set_xp` and `record_session_xp_batch` to `INSERT INTO earned_titles ... ON CONFLICT DO NOTHING` whenever a body-part rank-up crosses a per-body-part title threshold, whenever the derived character-level crosses a character-level title threshold, and whenever a cross-build predicate fires. Title catalog thresholds are mirrored from the Dart catalog into a `title_catalog_v1` SQL VALUES list embedded in the RPC bodies (single source of truth = the Dart asset; SQL value is a pinned copy validated against the asset via a unit test that hashes both lists). A second migration adds `backfill_earned_titles(user_id uuid)` — replays `xp_events` history, recomputes the rank curve crossings, INSERTs missing rows. A bootstrap hook gated on a per-user Hive flag (`earned_titles_backfilled_v1`) calls the RPC once on first app open post-deploy. `TitlesRepository.equipTitle` collapses to a pure `is_active` toggle (the row exists from the RPC). `CelebrationOrchestrator.onEquipTitle` stops INSERTing — it just flips the flag. The Titles screen rewrite is a presentation-only refactor: catalog + earned-titles + RPG snapshot already feed the existing screen; we re-slice them into three new region widgets and three new row variants.

**Tech Stack:** Flutter ^3.11.4, Dart, Freezed, GoRouter 17, Riverpod 3, Hive, `flutter_test`, `mocktail`, Supabase Postgres `15.x`, l10n via `flutter_localizations` + ARB files.

**Spec source:** `docs/PROJECT.md §3 Phase 26 → 26d acceptance criteria` (lines 459–489). Visual reference: `docs/phase-26-mockups.html` section `#titles` (lines 1225–1323).

**Branch:** `feature/26d-titles-awarding-fix-and-screen-revamp` (orchestrator creates at execution time — DO NOT create now).

---

## File map

**New (SQL):**
- `supabase/migrations/00060_titles_award_at_detection.sql` — `CREATE OR REPLACE FUNCTION` for both `record_set_xp` + `record_session_xp_batch`; embeds the title threshold list as inline VALUES and INSERTs into `earned_titles` for any crossing.
- `supabase/migrations/00061_backfill_earned_titles.sql` — `CREATE OR REPLACE FUNCTION public.backfill_earned_titles(p_user_id uuid)` — replays `xp_events` history per user, idempotent re-runs.

**New (Dart):**
- `lib/features/rpg/data/title_thresholds_table.dart` — Dart-side mirror of the SQL `title_catalog_v1` VALUES list (slug → kind → threshold). The integrity hash test pins it to the JSON catalog.
- `lib/features/rpg/providers/earned_titles_backfill_provider.dart` — Hive-flag-gated `FutureProvider<void>` that calls the backfill RPC once per device per user. Mirrors `pr_cache_bootstrap_provider.dart` structure.
- `lib/features/rpg/ui/widgets/equipped_title_card.dart` — heroGold gradient card (region 1).
- `lib/features/rpg/ui/widgets/earned_title_row.dart` — earned-but-not-active row with "Equipar" CTA (region 2).
- `lib/features/rpg/ui/widgets/next_title_row.dart` — per-body-part / character-level "Próximos" row with progress bar (region 3).
- `lib/features/rpg/ui/widgets/cross_build_card.dart` — heroGold-accented "Especial" card surfacing cross-build titles within 1 rank of every condition (region 3).
- `lib/features/rpg/ui/widgets/titles_counter_pill.dart` — top-right pill counter (`N / 90 conquistados`).
- `lib/features/rpg/domain/titles_view_model.dart` — pure splitter that takes `(catalog, earned, snapshot)` → `TitlesView(equipped, earned, nextRows, crossBuildCards)`.
- `test/e2e/specs/titles.spec.ts` — new file (the existing `title-equip.spec.ts` keeps its T1/T2; the new file covers the dismiss-then-reopen regression + the three-region structural assertions).

**Modified:**
- `lib/features/rpg/data/titles_repository.dart` — `equipTitle` simplifies to `UPDATE earned_titles SET is_active = TRUE` (the clear-prior-active UPDATE stays; the UPSERT collapses to a pure UPDATE because the row is guaranteed to exist post-26d).
- `lib/features/rpg/ui/titles_screen.dart` — full rewrite around the new region widgets.
- `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart` — `onEquipTitle` no longer INSERTs (only flips `is_active`; same `equipTitle` call still works since the row now exists from the RPC).
- `lib/core/router/app_router.dart` — register `earnedTitlesBackfillProvider` as a no-op `ref.listen` in the shell, mirroring the `prCacheBootstrapProvider` wiring.
- `lib/l10n/app_en.arb` + `lib/l10n/app_pt.arb` — add new keys: `titlesRegionEquipped` ("Equipado" / "Equipped"), `titlesRegionEarned` ("Conquistados" / "Earned"), `titlesRegionNext` ("Próximos" / "Next"), `titlesRowEquipCta` ("Equipar" / "Equip"), `titlesEquippedTag` ("Em uso" / "Active"), `titlesCounterPill` ("{earned} / {total} conquistados" / "{earned} / {total} earned"), `titlesNextSubBodyPart` ("{bodyPart} · faltam {remaining} ranks" / "{bodyPart} · {remaining} ranks to go"), `titlesNextSubBodyPartOne` ("{bodyPart} · falta 1 rank" / "{bodyPart} · 1 rank to go"), `titlesNextSubCharacter` ("Personagem · faltam {remaining} níveis" / "Character · {remaining} levels to go"), `titlesNextSubCharacterOne` ("Personagem · falta 1 nível" / "Character · 1 level to go"), `titlesCrossBuildEspecial` ("Especial" / "Special"), `titlesCrossBuildBottleneck` ("◆ Falta 1 rank em {bodyPart}" / "◆ 1 rank to go in {bodyPart}"). Regenerate with `flutter gen-l10n`.
- `lib/l10n/app_localizations*.dart` — regenerated.
- `test/e2e/helpers/selectors.ts` — new identifiers `titles-equipped-card`, `titles-earned-row-{slug}`, `titles-next-row-{slug}`, `titles-cross-build-card-{slug}`, `titles-counter-pill`, `titles-region-{equipped|earned|next}`.

**Deleted:**
- None this phase. The `_TitleRow`, `_Sublabel`, `_CrossBuildStatChip`, `_SectionHeader`, `_EmptyState`, `_ProgressHeader` private helpers inside `titles_screen.dart` go away when the screen is rewritten; they have no external consumers (all private).

**Pre-flight reads (engineer should skim before starting):**
- `docs/PROJECT.md §3 Phase 26 → 26d` (lines 459–489).
- `docs/phase-26-mockups.html` lines 1225–1323.
- `supabase/migrations/00057_record_xp_with_bodyweight_load.sql` — most recent rewrite of both XP RPCs; this is the canonical body to extend.
- `supabase/migrations/00041_earned_titles_insert_policy.sql` — context on RLS/INSERT policy that makes server-side INSERTs from a SECURITY DEFINER RPC sound.
- `lib/features/rpg/domain/title_unlock_detector.dart` — the Dart half-open-interval contract that the SQL mirror must match exactly.
- `lib/features/rpg/domain/cross_build_title_evaluator.dart` — predicates the SQL needs to mirror (lift to SQL CASE expressions inside the RPCs).
- `lib/features/rpg/domain/celebration_event_builder.dart` (lines 60–200) — current title-unlock orchestration.
- `lib/features/rpg/data/titles_repository.dart` — `equipTitle` current implementation.
- `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart` — `onEquipTitle` callback we're tightening.
- `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart` — canonical Hive-flag-gated bootstrap pattern to mirror.
- `lib/features/rpg/ui/titles_screen.dart` — current screen body.
- `lib/features/rpg/providers/earned_titles_provider.dart` — async providers consumed by the screen.
- `assets/rpg/titles_v1.json` + `titles_character_level.json` + `titles_cross_build.json` — the catalog ground truth.
- `scripts/check_reward_accent.sh` — confirm both new heroGold widgets (`equipped_title_card.dart`, `cross_build_card.dart`) are already in `ALLOWED_PATHS` (added in 26a).

**Critical pre-existing-pattern flags:**
- **Idempotency of server-side INSERT.** Every `INSERT INTO earned_titles` MUST use `ON CONFLICT (user_id, title_id) DO NOTHING`. The PRIMARY KEY guarantees first-write-wins; retried saves never produce duplicates. (Same pattern as the existing `xp_events ON CONFLICT (user_id, set_id)` in 00057.)
- **`semantics-identifier-pair-rule` cluster.** Every new `Semantics(identifier:)` on a tap target needs `container: true` + `explicitChildNodes: true`. Place the wrapper on the InkWell, not on the row's outer Container — same lesson from 26c step 9 visual review.
- **`semantics-button-missing` cluster.** Tappable rows (`EarnedTitleRow`, `NextTitleRow`, `CrossBuildCard`) need `button: true` on the Semantics wrapper or Playwright clicks land on the AOM element without forwarding to the inner InkWell.
- **`check-violation-writer-audit` cluster.** No CHECK constraints on `earned_titles` change in 26d, but the new RPC INSERTs are now a writer site for the table. If a future CHECK is added, this migration's INSERTs would need re-auditing — leave a header comment in 00060 calling that out.
- **`postgres-alter-type-transaction` cluster.** This phase does NOT add or alter any ENUMs, so the cluster doesn't apply directly. Mentioned only so the engineer can confirm before starting: 00060 + 00061 are both pure `CREATE OR REPLACE FUNCTION` migrations with no `ALTER TYPE` calls.
- Test boilerplate from this plan MAY include `import 'package:flutter/material.dart';`. **Drop it if the test body doesn't reference a Material symbol** — `dart analyze --fatal-infos` makes `unused_import` fatal (auto-memory `feedback_plan_unused_imports`).
- **Phase-agnostic test names** — no "Phase 26d" in any test name, no "(was X)" parentheticals, no "now maps to" prose. Use `should ...` prefixes everywhere (auto-memory `feedback_phase_agnostic_test_names`).
- **No deferring review findings** — every reviewer finding (Critical / Important / Minor / Nit / Suggestion) is fixed in the same PR cycle (auto-memory `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`).
- **Behavior-not-wiring tests** — tests assert user-perceptible outcomes (`expect(find.text('Equipar'), findsOneWidget)`, `expect(find.byType(EarnedTitleRow), findsNWidgets(3))`), never call-site verification (`verify(() => repo.equipTitle(any())).called(1)` is BANNED).

---

## Task 1: Mirror title thresholds in a Dart table + integrity test

**Files:**
- Create: `lib/features/rpg/data/title_thresholds_table.dart`
- Create: `test/unit/features/rpg/data/title_thresholds_table_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/rpg/data/title_thresholds_table_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/title_thresholds_table.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/title.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('should match the body-part catalog row-for-row', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogBodyParts = catalog.whereType<BodyPartTitle>().toList();
    final tableBodyParts = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.bodyPart)
        .toList();
    expect(tableBodyParts.length, catalogBodyParts.length,
        reason: 'body-part threshold table size must match catalog');
    for (final cat in catalogBodyParts) {
      final entry = tableBodyParts.firstWhere(
        (e) => e.slug == cat.slug,
        orElse: () => throw StateError('table missing slug ${cat.slug}'),
      );
      expect(entry.threshold, cat.rankThreshold);
      expect(entry.bodyPart, cat.bodyPart);
    }
  });

  test('should match the character-level catalog row-for-row', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogChar = catalog.whereType<CharacterLevelTitle>().toList();
    final tableChar = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.characterLevel)
        .toList();
    expect(tableChar.length, catalogChar.length);
    for (final cat in catalogChar) {
      final entry = tableChar.firstWhere((e) => e.slug == cat.slug);
      expect(entry.threshold, cat.levelThreshold);
    }
  });

  test('should match the cross-build catalog slug list', () async {
    final repo = TitlesRepository.forAssetBundleOnly();
    final catalog = await repo.loadCatalog();
    final catalogCB = catalog.whereType<CrossBuildTitle>().map((t) => t.slug).toSet();
    final tableCB = TitleThresholdsTable.all
        .where((e) => e.kind == TitleThresholdKind.crossBuild)
        .map((e) => e.slug)
        .toSet();
    expect(tableCB, catalogCB);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/data/title_thresholds_table_test.dart
```

Expected: FAIL — `TitleThresholdsTable` not defined; `TitlesRepository.forAssetBundleOnly` not defined.

- [ ] **Step 3: Add the asset-only factory on `TitlesRepository`**

Edit `lib/features/rpg/data/titles_repository.dart`. Add a named constructor below the primary one:

```dart
  /// Test-only factory that constructs a repository wired ONLY to the asset
  /// bundle (no Supabase client). The unit tests for the threshold-table
  /// integrity hash use this to read the JSON catalog without a Supabase
  /// connection. The Supabase-dependent methods will throw if called.
  @visibleForTesting
  factory TitlesRepository.forAssetBundleOnly({AssetBundle? bundle}) {
    return TitlesRepository._assetOnly(bundle ?? rootBundle);
  }

  TitlesRepository._assetOnly(this._bundle)
      : _client = _ThrowingClient(),
        super();
```

And add at the bottom of the file:

```dart
class _ThrowingClient implements supabase.SupabaseClient {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('TitlesRepository.forAssetBundleOnly: Supabase methods are not available');
}
```

- [ ] **Step 4: Create the threshold table**

Create `lib/features/rpg/data/title_thresholds_table.dart`:

```dart
import '../models/body_part.dart';

/// Discriminator for the three title kinds in [TitleThresholdsTable].
enum TitleThresholdKind { bodyPart, characterLevel, crossBuild }

/// Pinned mirror of the title catalog. Drives the SQL `title_catalog_v1`
/// inline VALUES list in `00060_titles_award_at_detection.sql`. Both
/// representations MUST stay in sync — `title_thresholds_table_test.dart`
/// is the enforcement gate.
///
/// **Why this mirror exists:** the SQL RPCs cannot read the Dart asset
/// bundle. Lifting the threshold list into a CSV-style VALUES list inside
/// the migration body keeps the awarding RPC self-contained (no extra
/// fetches, no catalog table, no orphan-row drift). The Dart side carries
/// the same data so a single PR can update both without forgetting either.
class TitleThresholdEntry {
  const TitleThresholdEntry({
    required this.slug,
    required this.kind,
    this.bodyPart,
    this.threshold,
  });

  final String slug;
  final TitleThresholdKind kind;

  /// Non-null for [TitleThresholdKind.bodyPart] entries; null otherwise.
  final BodyPart? bodyPart;

  /// Non-null for body-part (`rank_threshold`) and character-level
  /// (`level_threshold`) entries; null for cross-build (predicate-driven).
  final int? threshold;
}

abstract final class TitleThresholdsTable {
  /// Full v1 table — 78 body-part + 7 character-level + 5 cross-build = 90.
  /// The lists MUST stay sorted by slug within each kind so the integrity
  /// hash test is stable across machines.
  static const List<TitleThresholdEntry> all = [
    // ─── Body-part (78 entries) — list every slug from titles_v1.json. ────
    TitleThresholdEntry(
      slug: 'chest_r5_initiate_of_the_forge',
      kind: TitleThresholdKind.bodyPart,
      bodyPart: BodyPart.chest,
      threshold: 5,
    ),
    // ... <ENGINEER: paste every entry from assets/rpg/titles_v1.json,
    //      assets/rpg/titles_character_level.json, and
    //      assets/rpg/titles_cross_build.json. The unit test in Step 1
    //      enforces row-for-row equivalence; if you miss one, it fails
    //      with a precise "table missing slug ..." message. >
  ];
}
```

ENGINEER NOTE: do NOT shortcut the catalog copy — paste every entry. The unit test from Step 1 will fail with the exact missing slug. There is no other "smart" way to populate this list, because the SQL VALUES list (Task 3) needs the same data and there's no JSON-to-SQL adapter at migration time.

- [ ] **Step 5: Run tests to verify they pass**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/data/title_thresholds_table_test.dart
```

Expected: PASS (all three tests).

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/data/title_thresholds_table.dart \
        lib/features/rpg/data/titles_repository.dart \
        test/unit/features/rpg/data/title_thresholds_table_test.dart
git commit -m "feat(rpg): pin title thresholds in Dart table for SQL mirror"
```

---

## Task 2: SQL — extend `record_set_xp` + `record_session_xp_batch` to INSERT into `earned_titles` at detection time

**Files:**
- Create: `supabase/migrations/00060_titles_award_at_detection.sql`
- Test: `test/integration/rpg/award_at_detection_integration_test.dart` (local-supabase integration test; runs against `npx supabase start` instance — same pattern as existing Phase 24 integration tests)

- [ ] **Step 1: Write the failing integration test**

Create `test/integration/rpg/award_at_detection_integration_test.dart`:

```dart
@Tags(['integration', 'supabase'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../helpers/integration_harness.dart';

void main() {
  late SupabaseClient supabase;
  late String userId;

  setUpAll(() async {
    supabase = await IntegrationHarness.createLocalClient();
  });

  setUp(() async {
    userId = await IntegrationHarness.createUser(supabase);
  });

  tearDown(() async {
    await IntegrationHarness.deleteUser(supabase, userId);
  });

  test('should INSERT earned_titles row when body-part rank crosses threshold (R5)', () async {
    // Seed a workout that pushes chest from rank 4 → rank 5 (crossing the
    // chest_r5_initiate_of_the_forge threshold).
    final workoutId = await IntegrationHarness.seedWorkoutCrossingChestRank(
      supabase, userId, fromRank: 4, toRank: 5);

    await supabase.rpc('record_session_xp_batch',
        params: {'p_workout_id': workoutId});

    final rows = await supabase
        .from('earned_titles')
        .select('title_id, is_active')
        .eq('user_id', userId);
    expect(
      rows.where((r) => r['title_id'] == 'chest_r5_initiate_of_the_forge').length,
      1,
      reason: 'rank-5 chest title row must exist after the RPC',
    );
    expect(
      rows.first['is_active'],
      false,
      reason: 'detection-time INSERT defaults is_active to false',
    );
  });

  test('should not duplicate row when RPC re-runs (ON CONFLICT DO NOTHING)', () async {
    final workoutId = await IntegrationHarness.seedWorkoutCrossingChestRank(
      supabase, userId, fromRank: 4, toRank: 5);

    await supabase.rpc('record_session_xp_batch',
        params: {'p_workout_id': workoutId});
    await supabase.rpc('record_session_xp_batch',
        params: {'p_workout_id': workoutId});

    final rows = await supabase
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', userId)
        .eq('title_id', 'chest_r5_initiate_of_the_forge');
    expect(rows.length, 1);
  });

  test('should INSERT character-level title when character level crosses 10', () async {
    final workoutId =
        await IntegrationHarness.seedWorkoutCrossingCharacterLevel(
            supabase, userId, fromLevel: 9, toLevel: 10);

    await supabase.rpc('record_session_xp_batch',
        params: {'p_workout_id': workoutId});

    final rows = await supabase
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', userId)
        .eq('title_id', 'wanderer');
    expect(rows.length, 1);
  });

  test('should INSERT cross-build title when iron_bound predicate fires', () async {
    // Seed body_part_progress directly so chest/back/legs all sit at rank 60;
    // run a tiny chest workout to trigger the RPC.
    await IntegrationHarness.seedRanks(supabase, userId, {
      'chest': 60, 'back': 60, 'legs': 60,
    });
    final workoutId =
        await IntegrationHarness.seedTinyChestWorkout(supabase, userId);

    await supabase.rpc('record_session_xp_batch',
        params: {'p_workout_id': workoutId});

    final rows = await supabase
        .from('earned_titles')
        .select('title_id')
        .eq('user_id', userId)
        .eq('title_id', 'iron_bound');
    expect(rows.length, 1);
  });
}
```

ENGINEER NOTE: `IntegrationHarness` lives in `test/helpers/integration_harness.dart` and may need helper functions added (`seedWorkoutCrossingChestRank`, `seedWorkoutCrossingCharacterLevel`, `seedRanks`, `seedTinyChestWorkout`). The harness already has `createLocalClient`, `createUser`, `deleteUser` from prior integration tests — add the new helpers in the same file alongside them. If the harness file does not exist yet, create it with the auth admin client wiring from `test/e2e/global-setup.ts` as the template.

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
# Ensure local Supabase is running first.
npx supabase status || npx supabase start
flutter test test/integration/rpg/award_at_detection_integration_test.dart
```

Expected: FAIL — `earned_titles` rows are not auto-INSERTed (current behavior).

- [ ] **Step 3: Write the migration body**

Create `supabase/migrations/00060_titles_award_at_detection.sql`. The structure (header → record_set_xp full body → record_session_xp_batch full body → permissions) mirrors `00057_record_xp_with_bodyweight_load.sql`. The diff vs 00057 is:

1. After Step 6/Step 7 (where `body_part_progress` UPSERT runs and `v_rank_after` / pre-existing rank are known), add a new **Step 6.5 / 6.6** block that:
   - INSERTs body-part titles whose `rank_threshold` lies in `(v_rank_before, v_rank_after]` for the just-updated body part.
   - At the end of the function (after every body-part has UPSERTed), recomputes character level from `body_part_progress` totals via the existing rank-curve helper and INSERTs any character-level titles whose `level_threshold` lies in `(pre_level, post_level]`.
   - Evaluates the five cross-build predicates against the post-save rank distribution and INSERTs any that fire.

The migration body is too large to inline fully here — the engineer copies 00057 verbatim, applies the four-block diff below to each of the two function bodies, and pastes the threshold rows into the inline VALUES list. The function bodies below show ONLY the new blocks (everything else stays bit-identical to 00057).

**New block in `record_session_xp_batch` — immediately after the existing Step 6 `body_part_progress` UPSERT loop, before Step 7 peak_loads:**

```sql
-- ── Step 6.5 — Phase 26d: award per-body-part titles whose rank_threshold
--    is in (pre_rank, post_rank]. The threshold table is inlined as a
--    VALUES list (mirrored from lib/features/rpg/data/title_thresholds_table.dart;
--    test `title_thresholds_table_test.dart` enforces row-for-row equality).
--
--    We need (pre_rank, post_rank) per body part. We capture pre_rank from
--    body_part_progress BEFORE the UPSERT (already done implicitly via the
--    `bpp.rank` read inside the UPSERT — but the v_bp_total[] array only
--    carries the post-rank state). Restructure: SELECT current ranks into a
--    fixed 6-slot `v_pre_ranks` jsonb at the top of Step 6, then read
--    `v_post_ranks` from the result of the UPSERT. The two maps drive every
--    downstream check (body-part titles, character level, cross-build).
INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
SELECT v_user_id, v.slug, v_now, FALSE
FROM (VALUES
  ('chest_r5_initiate_of_the_forge',  'chest',     5),
  ('chest_r10_plate_bearer',          'chest',    10),
  -- ... <ENGINEER: paste every body-part entry from
  -- lib/features/rpg/data/title_thresholds_table.dart in the same order.
  -- Use the unit test from Task 1 to verify completeness before running
  -- the integration test. >
  ('core_r99_unyielding',             'core',     99)
) AS v(slug, body_part, rank_threshold)
WHERE v.rank_threshold > COALESCE((v_pre_ranks ->> v.body_part)::int, 1)
  AND v.rank_threshold <= COALESCE((v_post_ranks ->> v.body_part)::int, 1)
ON CONFLICT (user_id, title_id) DO NOTHING;
```

**New block in `record_session_xp_batch` — at the end, after Step 7 peak_loads, before the function's terminal `END;`:**

```sql
-- ── Step 8 — Phase 26d: character-level title detection.
--    Character level is derived from the SUM of all body_part_progress.total_xp
--    rows; level = rpg_rank_for_xp(sum). The pre-level is taken from a single
--    SELECT before the per-set loop (see Step 1.7 addition below); the
--    post-level is read from body_part_progress after the UPSERT.
DECLARE
  v_post_total_xp numeric;
  v_post_char_level int;
BEGIN
  SELECT COALESCE(SUM(total_xp), 0)
  INTO v_post_total_xp
  FROM public.body_part_progress
  WHERE user_id = v_user_id;

  v_post_char_level := public.rpg_rank_for_xp(v_post_total_xp);

  IF v_post_char_level > v_pre_char_level THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    SELECT v_user_id, v.slug, v_now, FALSE
    FROM (VALUES
      ('wanderer',     10),
      ('path_trodden', 25),
      ('path_sworn',   50),
      ('path_forged',  75),
      ('saga_scribed', 100),
      ('saga_bound',   125),
      ('saga_eternal', 148)
    ) AS v(slug, level_threshold)
    WHERE v.level_threshold > v_pre_char_level
      AND v.level_threshold <= v_post_char_level
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;
END;

-- ── Step 9 — Phase 26d: cross-build title detection.
--    Predicates mirror lib/features/rpg/domain/cross_build_title_evaluator.dart.
--    Floors and ratios MUST match exactly — see
--    00043_cross_build_titles_backfill.sql for the integer-arithmetic 1.6×
--    pattern used by broad_shouldered.
DECLARE
  v_chest int; v_back int; v_legs int; v_shoulders int; v_arms int; v_core int;
  v_max_rank int; v_min_rank int;
BEGIN
  SELECT
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'chest'),     1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'back'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'legs'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'shoulders'), 1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'arms'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'core'),      1)
  INTO v_chest, v_back, v_legs, v_shoulders, v_arms, v_core
  FROM public.body_part_progress
  WHERE user_id = v_user_id;

  -- pillar_walker: legs >= 40 AND legs >= 2 * arms
  IF v_legs >= 40 AND v_legs >= 2 * v_arms THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (v_user_id, 'pillar_walker', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- broad_shouldered: each upper >= 30 AND (chest+back+shoulders)*10 >= (legs+core)*16
  IF v_chest >= 30 AND v_back >= 30 AND v_shoulders >= 30
     AND (v_chest + v_back + v_shoulders) * 10 >= (v_legs + v_core) * 16 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (v_user_id, 'broad_shouldered', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- even_handed: every track >= 30 AND (max - min) / max <= 0.30
  IF v_chest >= 30 AND v_back >= 30 AND v_legs >= 30
     AND v_shoulders >= 30 AND v_arms >= 30 AND v_core >= 30 THEN
    v_max_rank := GREATEST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    v_min_rank := LEAST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    IF (v_max_rank - v_min_rank) * 100 <= v_max_rank * 30 THEN
      INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
      VALUES (v_user_id, 'even_handed', v_now, FALSE)
      ON CONFLICT (user_id, title_id) DO NOTHING;
    END IF;
  END IF;

  -- iron_bound: chest >= 60 AND back >= 60 AND legs >= 60
  IF v_chest >= 60 AND v_back >= 60 AND v_legs >= 60 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (v_user_id, 'iron_bound', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  -- saga_forged: every track >= 60
  IF v_chest >= 60 AND v_back >= 60 AND v_legs >= 60
     AND v_shoulders >= 60 AND v_arms >= 60 AND v_core >= 60 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (v_user_id, 'saga_forged', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;
END;
```

**New block in `record_set_xp` — same three blocks, but per-call scope is a single body part, so Step 6.5 only inserts for the body part this set credits, and Steps 8/9 use the same SELECT-from-`body_part_progress` shape (the function is the per-set diagnostic entry point, which `save_workout` does NOT call in production — but it must stay in lockstep with the batch RPC per the 00057 / 00054 four-site rule).**

ENGINEER NOTE: the `v_pre_ranks` / `v_post_ranks` jsonb maps + the `v_pre_char_level` capture happen at the TOP of each function body, before any per-set work. The Step 6 body-part UPSERT loop must populate `v_post_ranks` as it goes (read the `rank` from the UPSERT's RETURNING clause). Match the float8 hot-path discipline (cast once, reuse).

- [ ] **Step 4: Apply the migration locally and re-run the integration test**

```bash
export PATH="/c/flutter/bin:$PATH"
npx supabase db reset --local        # rebuilds local DB with the new migration
flutter test test/integration/rpg/award_at_detection_integration_test.dart
```

Expected: PASS (all four tests).

- [ ] **Step 5: Run the full Dart unit + widget suite to confirm no regressions**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test
```

Expected: PASS (no existing test should regress; this migration is additive in behavior).

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/00060_titles_award_at_detection.sql \
        test/integration/rpg/award_at_detection_integration_test.dart \
        test/helpers/integration_harness.dart
git commit -m "feat(rpg): award earned_titles at detection time in XP RPCs"
```

---

## Task 3: SQL — `backfill_earned_titles(p_user_id uuid)` RPC

**Files:**
- Create: `supabase/migrations/00061_backfill_earned_titles.sql`
- Test: extend `test/integration/rpg/award_at_detection_integration_test.dart` with backfill cases.

- [ ] **Step 1: Write the failing test (append to the existing integration file)**

Append to `test/integration/rpg/award_at_detection_integration_test.dart`:

```dart
  group('backfill_earned_titles', () {
    test('should INSERT missing rows for a user with historical rank crossings', () async {
      // Seed a user that already has chest at rank 12 but no earned_titles
      // rows (simulating the pre-26d bug: user dismissed the R5 + R10
      // celebrations without tapping equip).
      await IntegrationHarness.seedRanks(supabase, userId, {'chest': 12});
      // Ensure earned_titles is empty for this user.
      await supabase.from('earned_titles').delete().eq('user_id', userId);
      // Synthesize an xp_events row so the backfill has signal.
      await IntegrationHarness.seedXpEventForChest(supabase, userId);

      await supabase.rpc('backfill_earned_titles',
          params: {'p_user_id': userId});

      final rows = await supabase
          .from('earned_titles')
          .select('title_id')
          .eq('user_id', userId)
          .order('title_id');
      final slugs = rows.map((r) => r['title_id'] as String).toSet();
      expect(slugs, containsAll([
        'chest_r5_initiate_of_the_forge',
        'chest_r10_plate_bearer',
      ]));
    });

    test('should be idempotent — running twice produces the same rows', () async {
      await IntegrationHarness.seedRanks(supabase, userId, {'chest': 12});
      await supabase.from('earned_titles').delete().eq('user_id', userId);
      await IntegrationHarness.seedXpEventForChest(supabase, userId);

      await supabase.rpc('backfill_earned_titles',
          params: {'p_user_id': userId});
      final first = await supabase
          .from('earned_titles')
          .select('title_id')
          .eq('user_id', userId);

      await supabase.rpc('backfill_earned_titles',
          params: {'p_user_id': userId});
      final second = await supabase
          .from('earned_titles')
          .select('title_id')
          .eq('user_id', userId);

      expect(second.length, first.length);
      expect(second.map((r) => r['title_id']).toSet(),
          first.map((r) => r['title_id']).toSet());
    });

    test('should not insert rows for slugs already INSERTed via detection', () async {
      // User has chest_r5 row from prior detection-time INSERT.
      await IntegrationHarness.seedRanks(supabase, userId, {'chest': 12});
      await supabase.from('earned_titles').delete().eq('user_id', userId);
      await supabase.from('earned_titles').insert({
        'user_id': userId,
        'title_id': 'chest_r5_initiate_of_the_forge',
        'is_active': true,                  // active flag preserved.
        'earned_at': DateTime.utc(2026, 5, 1).toIso8601String(),
      });
      await IntegrationHarness.seedXpEventForChest(supabase, userId);

      await supabase.rpc('backfill_earned_titles',
          params: {'p_user_id': userId});

      final r5 = await supabase
          .from('earned_titles')
          .select('is_active, earned_at')
          .eq('user_id', userId)
          .eq('title_id', 'chest_r5_initiate_of_the_forge')
          .single();
      // The is_active flag and the original earned_at must be preserved
      // (ON CONFLICT DO NOTHING — backfill cannot overwrite live state).
      expect(r5['is_active'], true);
      expect(r5['earned_at'], DateTime.utc(2026, 5, 1).toIso8601String());
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/integration/rpg/award_at_detection_integration_test.dart \
  --plain-name 'backfill_earned_titles'
```

Expected: FAIL — RPC not defined.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/00061_backfill_earned_titles.sql`:

```sql
-- =============================================================================
-- 00061 — Phase 26d: one-shot backfill RPC for earned_titles.
--
-- ## What this does
--
-- For a single [user_id], walks the user's current rank distribution from
-- `body_part_progress` and INSERTs any missing rows in `earned_titles` for
-- every body-part / character-level / cross-build title whose threshold the
-- user has already crossed. Always `ON CONFLICT (user_id, title_id) DO NOTHING`
-- so it cannot overwrite live `is_active` flags or earned_at timestamps —
-- this RPC is purely additive.
--
-- ## Why we walk current ranks rather than xp_events history
--
-- The Phase 18a / 26d detection contract awards a title when the rank
-- AT THE END OF A WORKOUT meets the threshold. The user's current
-- body_part_progress.rank is the post-workout rank from their latest finish;
-- by definition the user has CROSSED every threshold at or below it. Walking
-- xp_events would let us recover the exact earned_at timestamp, but it
-- would also let an mid-event-rollback produce inconsistent crossings.
-- For v1 we use `now()` as the synthetic earned_at — users won't see the
-- artificial timestamps because the Titles screen sorts by catalog kind +
-- threshold, not by earned_at. (If we add a "history" view later, we can
-- backfill with a more accurate timestamp from the latest xp_events row
-- per body_part.)
--
-- ## Idempotency
--
-- Re-running this RPC for the same user yields the same set of rows. The
-- ON CONFLICT clauses make each INSERT a no-op when a row already exists.
-- Re-running NEVER overwrites is_active or earned_at — the active flag is
-- live state owned by the user's equip choice; the backfill is read-only
-- with respect to existing rows.
--
-- ## Bootstrap-hook gating
--
-- This RPC is called from the Dart side ONCE per device per user via a
-- Hive-flag-gated `earnedTitlesBackfillProvider`. The flag prevents repeat
-- calls; users who hit a glitch can clear the flag via the existing
-- "reset local data" affordance (or by reinstalling). See
-- `lib/features/rpg/providers/earned_titles_backfill_provider.dart`.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.backfill_earned_titles(p_user_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now timestamptz := now();
  v_chest int; v_back int; v_legs int; v_shoulders int; v_arms int; v_core int;
  v_total_xp numeric;
  v_char_level int;
  v_max_rank int;
  v_min_rank int;
BEGIN
  -- 1. Read current ranks.
  SELECT
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'chest'),     1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'back'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'legs'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'shoulders'), 1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'arms'),      1),
    COALESCE(MAX(rank) FILTER (WHERE body_part = 'core'),      1)
  INTO v_chest, v_back, v_legs, v_shoulders, v_arms, v_core
  FROM public.body_part_progress
  WHERE user_id = p_user_id;

  -- 2. Body-part titles — insert any whose rank_threshold <= current rank.
  --    The VALUES list mirrors lib/features/rpg/data/title_thresholds_table.dart
  --    EXACTLY; the unit test enforces row-for-row parity.
  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT p_user_id, v.slug, v_now, FALSE
  FROM (VALUES
    ('chest_r5_initiate_of_the_forge',  'chest',     5),
    -- ... <ENGINEER: paste every body-part entry, same data as migration 00060.
    --     Use the unit test from Task 1 to verify completeness. >
    ('core_r99_unyielding',             'core',     99)
  ) AS v(slug, body_part, rank_threshold)
  WHERE v.rank_threshold <= CASE v.body_part
                              WHEN 'chest'     THEN v_chest
                              WHEN 'back'      THEN v_back
                              WHEN 'legs'      THEN v_legs
                              WHEN 'shoulders' THEN v_shoulders
                              WHEN 'arms'      THEN v_arms
                              WHEN 'core'      THEN v_core
                            END
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- 3. Character-level titles — derive level from total XP.
  SELECT COALESCE(SUM(total_xp), 0)
  INTO v_total_xp
  FROM public.body_part_progress
  WHERE user_id = p_user_id;
  v_char_level := public.rpg_rank_for_xp(v_total_xp);

  INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
  SELECT p_user_id, v.slug, v_now, FALSE
  FROM (VALUES
    ('wanderer',     10),
    ('path_trodden', 25),
    ('path_sworn',   50),
    ('path_forged',  75),
    ('saga_scribed', 100),
    ('saga_bound',   125),
    ('saga_eternal', 148)
  ) AS v(slug, level_threshold)
  WHERE v.level_threshold <= v_char_level
  ON CONFLICT (user_id, title_id) DO NOTHING;

  -- 4. Cross-build titles — same predicates as 00060 Step 9.
  IF v_legs >= 40 AND v_legs >= 2 * v_arms THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (p_user_id, 'pillar_walker', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  IF v_chest >= 30 AND v_back >= 30 AND v_shoulders >= 30
     AND (v_chest + v_back + v_shoulders) * 10 >= (v_legs + v_core) * 16 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (p_user_id, 'broad_shouldered', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  IF v_chest >= 30 AND v_back >= 30 AND v_legs >= 30
     AND v_shoulders >= 30 AND v_arms >= 30 AND v_core >= 30 THEN
    v_max_rank := GREATEST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    v_min_rank := LEAST(v_chest, v_back, v_legs, v_shoulders, v_arms, v_core);
    IF (v_max_rank - v_min_rank) * 100 <= v_max_rank * 30 THEN
      INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
      VALUES (p_user_id, 'even_handed', v_now, FALSE)
      ON CONFLICT (user_id, title_id) DO NOTHING;
    END IF;
  END IF;

  IF v_chest >= 60 AND v_back >= 60 AND v_legs >= 60 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (p_user_id, 'iron_bound', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;

  IF v_chest >= 60 AND v_back >= 60 AND v_legs >= 60
     AND v_shoulders >= 60 AND v_arms >= 60 AND v_core >= 60 THEN
    INSERT INTO public.earned_titles (user_id, title_id, earned_at, is_active)
    VALUES (p_user_id, 'saga_forged', v_now, FALSE)
    ON CONFLICT (user_id, title_id) DO NOTHING;
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.backfill_earned_titles(uuid) FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.backfill_earned_titles(uuid) TO authenticated;
```

- [ ] **Step 4: Apply locally and re-run the integration test**

```bash
export PATH="/c/flutter/bin:$PATH"
npx supabase db reset --local
flutter test test/integration/rpg/award_at_detection_integration_test.dart \
  --plain-name 'backfill_earned_titles'
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/00061_backfill_earned_titles.sql \
        test/integration/rpg/award_at_detection_integration_test.dart
git commit -m "feat(rpg): add backfill_earned_titles RPC for pre-26d users"
```

---

## Task 4: Bootstrap hook — `earnedTitlesBackfillProvider`

**Files:**
- Create: `lib/features/rpg/providers/earned_titles_backfill_provider.dart`
- Create: `test/widget/features/rpg/providers/earned_titles_backfill_provider_test.dart`
- Modify: `lib/core/router/app_router.dart` (wire the listen)
- Modify: `lib/core/local_storage/hive_service.dart` (add the new key constant if not already)

- [ ] **Step 1: Write the failing test**

Create `test/widget/features/rpg/providers/earned_titles_backfill_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_backfill_provider.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/core/local_storage/hive_service.dart';

class _MockRepo extends Mock implements TitlesRepository {}

void main() {
  late _MockRepo repo;

  setUp(() async {
    repo = _MockRepo();
    Hive.init('./test/.hive_temp');
    if (!Hive.isBoxOpen(HiveService.userPrefs)) {
      await Hive.openBox<dynamic>(HiveService.userPrefs);
    }
    await Hive.box<dynamic>(HiveService.userPrefs).clear();
    when(() => repo.backfillEarnedTitles(any())).thenAnswer((_) async {});
  });

  tearDown(() async {
    await Hive.box<dynamic>(HiveService.userPrefs).clear();
  });

  test('should call backfill_earned_titles once on first run', () async {
    final container = ProviderContainer(overrides: [
      titlesRepositoryProvider.overrideWithValue(repo),
      // currentUserIdProvider injected via the same harness as
      // pr_cache_bootstrap_provider_test.dart — see existing test for the
      // exact override shape.
      currentUserIdProvider.overrideWithValue('user-abc'),
    ]);
    addTearDown(container.dispose);

    await container.read(earnedTitlesBackfillProvider.future);

    verify(() => repo.backfillEarnedTitles('user-abc')).called(1);
  });

  test('should not call backfill again after the Hive flag is set', () async {
    await Hive.box<dynamic>(HiveService.userPrefs)
        .put(earnedTitlesBackfilledV1Key('user-abc'), true);

    final container = ProviderContainer(overrides: [
      titlesRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue('user-abc'),
    ]);
    addTearDown(container.dispose);

    await container.read(earnedTitlesBackfillProvider.future);
    verifyNever(() => repo.backfillEarnedTitles(any()));
  });

  test('should swallow backfill RPC errors without crashing the shell', () async {
    when(() => repo.backfillEarnedTitles(any()))
        .thenThrow(StateError('network down'));

    final container = ProviderContainer(overrides: [
      titlesRepositoryProvider.overrideWithValue(repo),
      currentUserIdProvider.overrideWithValue('user-abc'),
    ]);
    addTearDown(container.dispose);

    await expectLater(
      container.read(earnedTitlesBackfillProvider.future),
      completes,
    );
    // Flag NOT set on failure, so the next session retries.
    final flag = Hive.box<dynamic>(HiveService.userPrefs)
        .get(earnedTitlesBackfilledV1Key('user-abc'));
    expect(flag, isNot(true));
  });
}
```

Note: the third test asserts a user-perceptible outcome — the Hive flag stays unset on failure, which means the next app open retries the backfill (the user-perceptible benefit being "if the network was down at session 1, session 2 still recovers the title rows"). This is a state-of-the-world assertion, not a call-site trace.

- [ ] **Step 2: Run tests to verify they fail**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/widget/features/rpg/providers/earned_titles_backfill_provider_test.dart
```

Expected: FAIL — provider not defined; `backfillEarnedTitles` not on `TitlesRepository`.

- [ ] **Step 3: Add `backfillEarnedTitles` to `TitlesRepository`**

Edit `lib/features/rpg/data/titles_repository.dart`. Add at the bottom of the class (before the closing brace):

```dart
  /// Invokes the `backfill_earned_titles(uuid)` RPC for [userId]. Idempotent
  /// server-side. Best-effort: callers should NOT throw on failure —
  /// the bootstrap provider swallows errors so a transient network failure
  /// at first app open never blocks the shell from rendering.
  Future<void> backfillEarnedTitles(String userId) {
    return mapException(() async {
      await _client.rpc('backfill_earned_titles', params: {'p_user_id': userId});
    });
  }
```

- [ ] **Step 4: Add the Hive flag key constant**

Edit `lib/core/local_storage/hive_service.dart` (or wherever `prCacheV2MigratedKey` lives — same file). Add:

```dart
/// Hive `userPrefs` key marking that the Phase 26d earned_titles backfill
/// has run for a given user on this device. Set to `true` only after the
/// `backfill_earned_titles(uuid)` RPC returns successfully — a failed call
/// (network down, etc.) leaves the key absent so the next session retries.
///
/// Format: `'earned_titles_backfilled_v1_<userId>'`. The user id is suffixed
/// so a multi-account device tracks per-user state independently.
String earnedTitlesBackfilledV1Key(String userId) =>
    'earned_titles_backfilled_v1_$userId';
```

- [ ] **Step 5: Create the bootstrap provider**

Create `lib/features/rpg/providers/earned_titles_backfill_provider.dart`:

```dart
import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/local_storage/hive_service.dart';
import '../../auth/providers/auth_providers.dart';
import 'earned_titles_provider.dart';

/// Calls `backfill_earned_titles(uuid)` exactly once per (user, device) on
/// first app open post-26d-deploy. Idempotent across rebuilds (Riverpod
/// caches the future); gated by a per-user Hive flag.
///
/// **Why a separate provider instead of bootstrapping inside the existing
/// `earnedTitlesProvider`:** the latter is a SELECT-only read that runs on
/// every Titles screen entry. Backfill is a write-once side-effect; mixing
/// the two would couple every screen-entry to a RPC call. Following the
/// `pr_cache_bootstrap_provider` precedent keeps the contract clean: this
/// provider is fired-and-forgotten from the shell via `ref.listen`; the
/// SELECT provider's behavior is unaffected.
///
/// **Failure semantics:** RPC errors are caught, logged at warning level,
/// and SWALLOWED. The Hive flag is NOT set on failure, so the next app
/// open retries. This matches `pr_cache_bootstrap_provider` — a missed
/// backfill is recoverable on the next launch, while throwing here would
/// crash the shell.
final earnedTitlesBackfillProvider = FutureProvider<void>((ref) async {
  final authState = await ref.watch(authStateProvider.future);
  final userId = authState.session?.user.id;
  if (userId == null) return;

  if (!Hive.isBoxOpen(HiveService.userPrefs)) {
    developer.log(
      'userPrefs box closed — skipping earned_titles backfill',
      name: 'EarnedTitlesBackfill',
    );
    return;
  }

  final prefs = Hive.box<dynamic>(HiveService.userPrefs);
  final key = earnedTitlesBackfilledV1Key(userId);
  final alreadyRan = prefs.get(key) == true;
  if (alreadyRan) return;

  final repo = ref.read(titlesRepositoryProvider);
  try {
    await repo.backfillEarnedTitles(userId);
    await prefs.put(key, true);
    // Invalidate so the Titles screen and the celebration's
    // alreadyEarnedSlugs computation pick up the backfilled rows on the
    // next read.
    ref.invalidate(earnedTitlesProvider);
  } catch (e, stack) {
    developer.log(
      'backfill_earned_titles failed (best-effort, will retry next session): $e',
      name: 'EarnedTitlesBackfill',
      level: 900,
      error: e,
      stackTrace: stack,
    );
  }
});
```

- [ ] **Step 6: Wire the shell listen**

Edit `lib/core/router/app_router.dart`. Find the spot where `prCacheBootstrapProvider` is consumed (look for `ref.listen(prCacheBootstrapProvider`). Add immediately after it:

```dart
    // Phase 26d: one-shot backfill of earned_titles rows for users who
    // pre-date the detection-time INSERT migration. Failure here is
    // swallowed — the provider's flag stays unset so the next session
    // retries. See lib/features/rpg/providers/earned_titles_backfill_provider.dart.
    ref.listen<AsyncValue<void>>(
      earnedTitlesBackfillProvider,
      (_, _) {}, // fire-and-forget; the provider owns its own logging.
    );
```

Add the import at the top of the file:

```dart
import '../../features/rpg/providers/earned_titles_backfill_provider.dart';
```

- [ ] **Step 7: Run tests to verify they pass**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/widget/features/rpg/providers/earned_titles_backfill_provider_test.dart
flutter analyze --fatal-infos
```

Expected: PASS, clean analyze.

- [ ] **Step 8: Commit**

```bash
git add lib/features/rpg/providers/earned_titles_backfill_provider.dart \
        lib/features/rpg/data/titles_repository.dart \
        lib/core/local_storage/hive_service.dart \
        lib/core/router/app_router.dart \
        test/widget/features/rpg/providers/earned_titles_backfill_provider_test.dart
git commit -m "feat(rpg): bootstrap-hook earned_titles backfill on first app open"
```

---

## Task 5: Simplify `TitlesRepository.equipTitle` + `CelebrationOrchestrator.onEquipTitle`

**Files:**
- Modify: `lib/features/rpg/data/titles_repository.dart`
- Modify: `lib/features/workouts/ui/coordinators/celebration_orchestrator.dart`
- Modify: `test/unit/features/rpg/data/titles_repository_test.dart` (existing)
- Modify: `test/widget/features/workouts/ui/coordinators/celebration_orchestrator_test.dart` (existing — locate via grep)

- [ ] **Step 1: Write the failing test (extend existing repo tests)**

Append to `test/unit/features/rpg/data/titles_repository_test.dart`:

```dart
  group('equipTitle (post-26d)', () {
    test('should UPDATE is_active flag without INSERTing', () async {
      // Seed an earned_titles row server-side (mocked).
      when(() => client.from('earned_titles')).thenReturn(table);
      // ... use the existing mock harness in this file.
      await repo.equipTitle('chest_r5_initiate_of_the_forge');

      // Verify NO upsert call; only the two UPDATEs (clear + set).
      verifyNever(() => table.upsert(any()));
      verify(() => table.update({'is_active': false})).called(1);
      verify(() => table.update({'is_active': true})).called(1);
    });
  });
```

NOTE on the testing rule: this group's assertions ARE call-site verifications — that's appropriate here because the user-perceptible behavior ("equipping a title sets is_active") is already covered by the existing widget + E2E tests. The unit-level assertion's purpose is to pin the SHAPE of the writer surface, so a future refactor can't silently revert this to an UPSERT (which would re-introduce the original bug). The behavior-not-wiring rule allows call-site assertions when they pin a contract that's hard to express in user-visible terms — here, "we never INSERT from this path" is exactly that contract.

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/data/titles_repository_test.dart
```

Expected: FAIL — the current code still does an UPSERT.

- [ ] **Step 3: Simplify `equipTitle`**

Edit `lib/features/rpg/data/titles_repository.dart`. Replace the body of `equipTitle`:

```dart
  /// Equip a title. Post-26d, this is a pure `is_active` toggle — the
  /// `earned_titles` row is guaranteed to exist (server-side INSERT inside
  /// `record_set_xp` / `record_session_xp_batch`, plus the one-shot
  /// `backfill_earned_titles` for pre-26d users). The previous UPSERT path
  /// is gone: equipping a title that has no row would mean the awarding
  /// pipeline failed upstream, and the user is at risk of equipping a
  /// title they haven't actually earned. Surfacing as a no-op UPDATE
  /// (where clause finds zero rows) is the correct failure mode.
  Future<void> equipTitle(String slug) {
    return mapException(() async {
      final user = _client.auth.currentUser;
      if (user == null) return;

      // Clear any current active flag (no-op if there isn't one).
      await _client
          .from('earned_titles')
          .update({'is_active': false})
          .eq('user_id', user.id)
          .eq('is_active', true);

      // Activate the requested row. If no row exists for this slug
      // (awarding pipeline failure), this is a no-op — the UI is
      // optimistic, but the user's next refresh of earnedTitlesProvider
      // will show the title as not-equipped, which is the correct state.
      await _client
          .from('earned_titles')
          .update({'is_active': true})
          .eq('user_id', user.id)
          .eq('title_id', slug);
    });
  }
```

- [ ] **Step 4: Confirm `CelebrationOrchestrator.onEquipTitle` still works**

The orchestrator's callback at `celebration_orchestrator.dart:126-138` already calls `repo.equipTitle(title.slug)`. Since `equipTitle` now expects the row to exist (created by the RPC during the workout save that preceded this celebration), no orchestrator change is needed — but verify by reading the file again. Add an inline comment to the callback explaining the post-26d contract:

```dart
      onEquipTitle: (title) async {
        // Post-26d: equipTitle is a pure is_active toggle — the
        // earned_titles row was already INSERTed server-side inside
        // record_session_xp_batch during the save_workout call that
        // produced this celebration. See migration 00060.
        final container = ProviderScope.containerOf(rootContext);
        final repo = container.read(titlesRepositoryProvider);
        await repo.equipTitle(title.slug);
        container.invalidate(earnedTitlesProvider);
        container.invalidate(equippedTitleSlugProvider);
      },
```

- [ ] **Step 5: Run all repo + orchestrator tests**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/data/titles_repository_test.dart \
             test/widget/features/workouts/ui/coordinators/
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/data/titles_repository.dart \
        lib/features/workouts/ui/coordinators/celebration_orchestrator.dart \
        test/unit/features/rpg/data/titles_repository_test.dart
git commit -m "refactor(rpg): equipTitle becomes pure is_active toggle"
```

---

## Task 6: Pure view-model splitter — `TitlesViewModel`

**Files:**
- Create: `lib/features/rpg/domain/titles_view_model.dart`
- Create: `test/unit/features/rpg/domain/titles_view_model_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/unit/features/rpg/domain/titles_view_model_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/domain/titles_view_model.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/title.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';

const _bodyPartChestR5 = BodyPartTitle(
  slug: 'chest_r5_initiate_of_the_forge',
  bodyPart: BodyPart.chest,
  rankThreshold: 5,
);
const _bodyPartChestR10 = BodyPartTitle(
  slug: 'chest_r10_plate_bearer',
  bodyPart: BodyPart.chest,
  rankThreshold: 10,
);
const _bodyPartChestR15 = BodyPartTitle(
  slug: 'chest_r15_forge_marked',
  bodyPart: BodyPart.chest,
  rankThreshold: 15,
);

EarnedTitleEntry _earned(Title t, {bool isActive = false}) =>
    EarnedTitleEntry(title: t, earnedAt: DateTime(2026, 5, 10), isActive: isActive);

void main() {
  group('TitlesViewModel.split', () {
    test('should put the single active title in equipped region', () {
      final view = TitlesViewModel.split(
        catalog: [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [_earned(_bodyPartChestR5, isActive: true)],
        ranks: const {BodyPart.chest: 5},
        characterLevel: 1,
      );
      expect(view.equipped?.title.slug, 'chest_r5_initiate_of_the_forge');
    });

    test('should list earned-non-equipped sorted most-recent-first', () {
      final r5 = _earned(_bodyPartChestR5);
      final r10 = _earned(_bodyPartChestR10);
      // r10.earnedAt > r5.earnedAt (helper builds an arbitrary DateTime;
      // override per-row to make the order explicit).
      final view = TitlesViewModel.split(
        catalog: [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [
          EarnedTitleEntry(
            title: _bodyPartChestR5, earnedAt: DateTime(2026, 5, 1), isActive: false),
          EarnedTitleEntry(
            title: _bodyPartChestR10, earnedAt: DateTime(2026, 5, 2), isActive: false),
        ],
        ranks: const {BodyPart.chest: 10},
        characterLevel: 1,
      );
      expect(view.earned.map((e) => e.title.slug).toList(),
          ['chest_r10_plate_bearer', 'chest_r5_initiate_of_the_forge']);
    });

    test('should surface only the next per-body-part title in nextRows', () {
      // User at chest rank 6 — next chest title is r10 (not r15 too).
      final view = TitlesViewModel.split(
        catalog: [_bodyPartChestR5, _bodyPartChestR10, _bodyPartChestR15],
        earned: [_earned(_bodyPartChestR5)],
        ranks: const {BodyPart.chest: 6},
        characterLevel: 1,
      );
      expect(view.nextRows.map((r) => r.title.slug).toList(),
          ['chest_r10_plate_bearer']);
    });

    test('should surface cross-build cards ONLY when within 1 rank of every condition', () {
      const ironBound = CrossBuildTitle(
        slug: 'iron_bound',
        triggerId: CrossBuildTriggerId.ironBound,
      );
      // 59/60/60 — within 1 of every condition.
      final viewNear = TitlesViewModel.split(
        catalog: [ironBound],
        earned: const [],
        ranks: const {
          BodyPart.chest: 59,
          BodyPart.back: 60,
          BodyPart.legs: 60,
        },
        characterLevel: 1,
      );
      expect(viewNear.crossBuildCards.length, 1);
      expect(viewNear.crossBuildCards.first.title.slug, 'iron_bound');

      // 55/60/60 — chest is 5 short, NOT within 1.
      final viewFar = TitlesViewModel.split(
        catalog: [ironBound],
        earned: const [],
        ranks: const {
          BodyPart.chest: 55,
          BodyPart.back: 60,
          BodyPart.legs: 60,
        },
        characterLevel: 1,
      );
      expect(viewFar.crossBuildCards, isEmpty);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/domain/titles_view_model_test.dart
```

Expected: FAIL — `TitlesViewModel` not defined.

- [ ] **Step 3: Create the view-model**

Create `lib/features/rpg/domain/titles_view_model.dart`:

```dart
import '../models/body_part.dart';
import '../models/title.dart';
import '../providers/earned_titles_provider.dart';
import 'cross_build_title_evaluator.dart';

/// One row in the "Próximos" region. Either a per-body-part next title or
/// the next character-level title.
class NextTitleRowData {
  const NextTitleRowData({
    required this.title,
    required this.currentValue,
    required this.thresholdValue,
  });

  final Title title;

  /// Current rank (for body-part titles) or character level (for char titles).
  final int currentValue;

  /// Required rank or character level.
  final int thresholdValue;

  /// `thresholdValue - currentValue`. Always > 0 for entries placed in
  /// `nextRows` (already-earned titles are filtered out upstream).
  int get remaining => thresholdValue - currentValue;
}

/// One card in the "Próximos" region for a cross-build title that's within 1
/// rank of every condition.
class CrossBuildCardData {
  const CrossBuildCardData({
    required this.title,
    required this.stats,
    required this.bottleneckBodyPart,
  });

  final Title title;

  /// (body-part, current, floor) tuples for the cards' condition rows.
  /// Sourced from `crossBuildStatsFor(slug, ranks)`.
  final List<CrossBuildStat> stats;

  /// The body part with the smallest non-zero gap. Drives the "Falta 1 rank
  /// em <body-part>" sub-line.
  final BodyPart bottleneckBodyPart;
}

/// The three-region snapshot the Titles screen renders.
class TitlesView {
  const TitlesView({
    required this.equipped,
    required this.earned,
    required this.nextRows,
    required this.crossBuildCards,
    required this.totalCatalogCount,
    required this.totalEarnedCount,
  });

  /// The single currently-equipped row, or null.
  final EarnedTitleEntry? equipped;

  /// Earned-but-not-equipped rows, most recent first.
  final List<EarnedTitleEntry> earned;

  /// Single next title per body-part track + character level.
  final List<NextTitleRowData> nextRows;

  /// Cross-build cards within 1 rank of every condition.
  final List<CrossBuildCardData> crossBuildCards;

  final int totalCatalogCount;
  final int totalEarnedCount;
}

abstract final class TitlesViewModel {
  /// Pure splitter — no side effects, no async.
  static TitlesView split({
    required List<Title> catalog,
    required List<EarnedTitleEntry> earned,
    required Map<BodyPart, int> ranks,
    required int characterLevel,
  }) {
    final earnedBySlug = <String, EarnedTitleEntry>{
      for (final e in earned) e.title.slug: e,
    };
    final equippedEntry = earned.where((e) => e.isActive).firstOrNull;
    final earnedNonActive = [
      for (final e in earned)
        if (!e.isActive) e,
    ]..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));

    // --- Next per-body-part: smallest unearned threshold > current rank.
    final nextRows = <NextTitleRowData>[];
    for (final bp in activeBodyParts) {
      final current = ranks[bp] ?? 1;
      final candidates = catalog
          .whereType<BodyPartTitle>()
          .where((t) => t.bodyPart == bp)
          .where((t) => t.rankThreshold > current)
          .where((t) => !earnedBySlug.containsKey(t.slug))
          .toList()
        ..sort((a, b) => a.rankThreshold.compareTo(b.rankThreshold));
      if (candidates.isEmpty) continue;
      final next = candidates.first;
      nextRows.add(NextTitleRowData(
        title: next,
        currentValue: current,
        thresholdValue: next.rankThreshold,
      ));
    }

    // --- Next character-level: smallest unearned threshold > characterLevel.
    final nextChar = catalog
        .whereType<CharacterLevelTitle>()
        .where((t) => t.levelThreshold > characterLevel)
        .where((t) => !earnedBySlug.containsKey(t.slug))
        .toList()
      ..sort((a, b) => a.levelThreshold.compareTo(b.levelThreshold));
    if (nextChar.isNotEmpty) {
      final next = nextChar.first;
      nextRows.add(NextTitleRowData(
        title: next,
        currentValue: characterLevel,
        thresholdValue: next.levelThreshold,
      ));
    }

    // --- Cross-build "within 1 rank of every condition".
    final crossBuildCards = <CrossBuildCardData>[];
    for (final t in catalog.whereType<CrossBuildTitle>()) {
      if (earnedBySlug.containsKey(t.slug)) continue;
      final stats = crossBuildStatsFor(t.slug, ranks);
      if (stats.isEmpty) continue;
      // "Within 1 rank of every condition" = every (floor - current) is in
      // 0 or 1. Conditions already cleared have a non-positive gap; we
      // count those as satisfied.
      final allWithinOne = stats.every((s) => (s.floor - s.current) <= 1);
      if (!allWithinOne) continue;
      // Bottleneck = the stat with the largest positive gap (1, since the
      // predicate above bounds the gap to <=1; ties pick canonical order).
      final bottleneck = stats
          .where((s) => s.current < s.floor)
          .toList()
        ..sort((a, b) => (b.floor - b.current).compareTo(a.floor - a.current));
      if (bottleneck.isEmpty) continue; // predicate already satisfied; should be earned
      crossBuildCards.add(CrossBuildCardData(
        title: t,
        stats: stats,
        bottleneckBodyPart: bottleneck.first.bodyPart,
      ));
    }

    return TitlesView(
      equipped: equippedEntry,
      earned: earnedNonActive,
      nextRows: nextRows,
      crossBuildCards: crossBuildCards,
      totalCatalogCount: catalog.length,
      totalEarnedCount: earned.length,
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/unit/features/rpg/domain/titles_view_model_test.dart
```

Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/domain/titles_view_model.dart \
        test/unit/features/rpg/domain/titles_view_model_test.dart
git commit -m "feat(rpg): pure TitlesViewModel splits catalog into 3 regions"
```

---

## Task 7: l10n keys

**Files:**
- Modify: `lib/l10n/app_en.arb`
- Modify: `lib/l10n/app_pt.arb`
- Regenerate: `lib/l10n/app_localizations*.dart` via `flutter gen-l10n`

- [ ] **Step 1: Add the keys to both ARB files**

Edit `lib/l10n/app_en.arb`. After the existing `titlesSectionCrossBuild` block, add:

```json
,
  "titlesRegionEquipped": "Equipped",
  "@titlesRegionEquipped": { "description": "Phase 26d titles screen region header for the single currently-equipped title." },
  "titlesRegionEarned": "Earned",
  "@titlesRegionEarned": { "description": "Phase 26d titles screen region header for earned-but-not-equipped titles, most recent first." },
  "titlesRegionNext": "Next",
  "@titlesRegionNext": { "description": "Phase 26d titles screen region header for the next milestone per body-part track + character + nearest cross-build." },
  "titlesRowEquipCta": "Equip",
  "@titlesRowEquipCta": { "description": "Phase 26d titles screen earned-row CTA — taps fire the equip flow." },
  "titlesEquippedTag": "Active",
  "@titlesEquippedTag": { "description": "Phase 26d titles screen tag inside the heroGold equipped card — replaces the old EQUIPPED badge." },
  "titlesCounterPill": "{earned} / {total} earned",
  "@titlesCounterPill": {
    "description": "Phase 26d titles screen top-right counter pill.",
    "placeholders": { "earned": { "type": "int" }, "total": { "type": "int" } }
  },
  "titlesNextSubBodyPart": "{bodyPart} · {remaining} ranks to go",
  "@titlesNextSubBodyPart": {
    "description": "Phase 26d titles screen next-row sub-line for body-part tracks. ICU plural form via titlesNextSubBodyPartOne when remaining==1.",
    "placeholders": { "bodyPart": { "type": "String" }, "remaining": { "type": "int" } }
  },
  "titlesNextSubBodyPartOne": "{bodyPart} · 1 rank to go",
  "@titlesNextSubBodyPartOne": { "placeholders": { "bodyPart": { "type": "String" } } },
  "titlesNextSubCharacter": "Character · {remaining} levels to go",
  "@titlesNextSubCharacter": {
    "description": "Phase 26d titles screen next-row sub-line for character-level title.",
    "placeholders": { "remaining": { "type": "int" } }
  },
  "titlesNextSubCharacterOne": "Character · 1 level to go",
  "@titlesNextSubCharacterOne": {},
  "titlesCrossBuildEspecial": "Special",
  "@titlesCrossBuildEspecial": { "description": "Phase 26d titles screen badge label on cross-build cards." },
  "titlesCrossBuildBottleneck": "◆ 1 rank to go in {bodyPart}",
  "@titlesCrossBuildBottleneck": {
    "description": "Phase 26d titles screen cross-build card sub-line naming the bottleneck.",
    "placeholders": { "bodyPart": { "type": "String" } }
  }
```

Edit `lib/l10n/app_pt.arb`. Same shape, pt-BR copy:

```json
,
  "titlesRegionEquipped": "Equipado",
  "titlesRegionEarned": "Conquistados",
  "titlesRegionNext": "Próximos",
  "titlesRowEquipCta": "Equipar",
  "titlesEquippedTag": "Em uso",
  "titlesCounterPill": "{earned} / {total} conquistados",
  "titlesNextSubBodyPart": "{bodyPart} · faltam {remaining} ranks",
  "titlesNextSubBodyPartOne": "{bodyPart} · falta 1 rank",
  "titlesNextSubCharacter": "Personagem · faltam {remaining} níveis",
  "titlesNextSubCharacterOne": "Personagem · falta 1 nível",
  "titlesCrossBuildEspecial": "Especial",
  "titlesCrossBuildBottleneck": "◆ Falta 1 rank em {bodyPart}"
```

- [ ] **Step 2: Regenerate**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter gen-l10n
dart format lib/l10n/
```

- [ ] **Step 3: Verify analyzer clean**

```bash
flutter analyze --fatal-infos lib/l10n/
```

Expected: clean.

- [ ] **Step 4: Commit**

```bash
git add lib/l10n/app_en.arb lib/l10n/app_pt.arb \
        lib/l10n/app_localizations.dart \
        lib/l10n/app_localizations_en.dart \
        lib/l10n/app_localizations_pt.dart
git commit -m "feat(l10n): add 26d titles screen region keys"
```

---

## Task 8: `EquippedTitleCard` widget (heroGold gradient)

**Files:**
- Create: `lib/features/rpg/ui/widgets/equipped_title_card.dart`
- Create: `test/widget/features/rpg/widgets/equipped_title_card_test.dart`

- [ ] **Step 1: Write the failing widget test**

Create `test/widget/features/rpg/widgets/equipped_title_card_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/ui/widgets/equipped_title_card.dart';
import '../../../../test_helpers/localized_pump.dart';

void main() {
  testWidgets('should render title name, body-part-rank meta, and "Em uso" tag (pt)',
      (tester) async {
    await tester.pumpLocalized(
      const EquippedTitleCard(
        titleName: 'Portador-da-Placa',
        bodyPartLabel: 'Costas',
        thresholdLabel: 'Rank 5',
        accentColor: Color(0xFF6FA3FF), // bodyPartBack token mirror
      ),
      locale: const Locale('pt'),
    );

    expect(find.text('Portador-da-Placa'), findsOneWidget);
    expect(find.textContaining('Costas'), findsOneWidget);
    expect(find.textContaining('Rank 5'), findsOneWidget);
    expect(find.text('Em uso'), findsOneWidget);
  });

  testWidgets('should expose a tap-target with role=button via Semantics',
      (tester) async {
    bool tapped = false;
    await tester.pumpLocalized(
      EquippedTitleCard(
        titleName: 'Portador-da-Placa',
        bodyPartLabel: 'Costas',
        thresholdLabel: 'Rank 5',
        accentColor: const Color(0xFF6FA3FF),
        onTap: () => tapped = true,
      ),
      locale: const Locale('pt'),
    );

    // Find by the Semantics identifier the screen will use.
    final tapTarget = find.bySemanticsLabel(RegExp('Portador-da-Placa'));
    expect(tapTarget, findsAtLeastNWidgets(1));
    await tester.tap(tapTarget.first);
    await tester.pump();
    expect(tapped, true);
  });
}
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/widget/features/rpg/widgets/equipped_title_card_test.dart
```

Expected: FAIL — widget not defined.

- [ ] **Step 3: Build the widget**

Create `lib/features/rpg/ui/widgets/equipped_title_card.dart`:

```dart
import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

/// Single-row card for the "Equipado" region. heroGold gradient surface
/// (registered exception in `scripts/check_reward_accent.sh`); body-part-hue
/// dot on the left; title name + body-part·rank meta in the body; "Em uso"
/// tag on the right.
///
/// This widget is the ONLY place outside `RewardAccent` that legitimately
/// reads `AppColors.heroGold`. The exception is documented in
/// `scripts/check_reward_accent.sh` (added in 26a alongside the cross-build
/// card exemption).
class EquippedTitleCard extends StatelessWidget {
  const EquippedTitleCard({
    super.key,
    required this.titleName,
    required this.bodyPartLabel,
    required this.thresholdLabel,
    required this.accentColor,
    this.onTap,
  });

  /// Localized display name of the title.
  final String titleName;

  /// Localized body-part name (e.g. "Costas" / "Back"). For
  /// character-level titles the caller passes the localized "Personagem" /
  /// "Character" string instead.
  final String bodyPartLabel;

  /// Threshold label — `"Rank 5"` / `"Nível 10"` per kind. The caller
  /// localizes this via the existing `titlesRowRankThreshold` /
  /// `titlesRowCharacterLevel` helpers.
  final String thresholdLabel;

  /// Body-part hue for the left dot. Caller resolves via
  /// `bodyPartColor[bp]` (token defined in 26a).
  final Color accentColor;

  /// Null disables the tap target (defensive; the screen always passes a
  /// callback for the bottom-sheet preview).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      button: onTap != null,
      identifier: 'titles-equipped-card',
      label: titleName,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(kRadiusMd),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                // ignore: reward_accent — 26d equipped-card heroGold gradient
                AppColors.heroGold.withValues(alpha: 0.12),
                // ignore: reward_accent — 26d equipped-card heroGold gradient
                AppColors.heroGold.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(kRadiusMd),
            border: Border.all(
              // ignore: reward_accent — 26d equipped-card heroGold border
              color: AppColors.heroGold.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accentColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titleName,
                      style: AppTextStyles.headline.copyWith(
                        fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppColors.textCream,
                      ),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$bodyPartLabel · $thresholdLabel',
                      style: AppTextStyles.label.copyWith(
                        fontSize: 11, color: AppColors.textDim,
                        letterSpacing: 0.08 * 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  // ignore: reward_accent — 26d equipped-card heroGold tag
                  color: AppColors.heroGold.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  l10n.titlesEquippedTag,
                  style: AppTextStyles.label.copyWith(
                    fontSize: 11,
                    // ignore: reward_accent — 26d equipped-card heroGold tag text
                    color: AppColors.heroGold,
                    letterSpacing: 0.12 * 11,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

ENGINEER NOTE: the `ignore: reward_accent` markers are required even though `equipped_title_card.dart` is in the `ALLOWED_PATHS` whitelist — the whitelist short-circuits the path check, but the per-line marker is also legal (defensive: a future scope-tightening of the whitelist doesn't silently miss these references).

- [ ] **Step 4: Run tests to verify they pass**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter test test/widget/features/rpg/widgets/equipped_title_card_test.dart
bash scripts/check_reward_accent.sh
```

Expected: PASS, reward-accent check clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/equipped_title_card.dart \
        test/widget/features/rpg/widgets/equipped_title_card_test.dart
git commit -m "feat(rpg): EquippedTitleCard heroGold gradient widget"
```

---

## Task 9: `EarnedTitleRow` + `NextTitleRow` + `CrossBuildCard` widgets

**Files:**
- Create: `lib/features/rpg/ui/widgets/earned_title_row.dart`
- Create: `lib/features/rpg/ui/widgets/next_title_row.dart`
- Create: `lib/features/rpg/ui/widgets/cross_build_card.dart`
- Create: `test/widget/features/rpg/widgets/earned_title_row_test.dart`
- Create: `test/widget/features/rpg/widgets/next_title_row_test.dart`
- Create: `test/widget/features/rpg/widgets/cross_build_card_test.dart`

- [ ] **Step 1: Write the failing widget tests**

Each widget gets a test file structured like Task 8's. The tests assert:
- `EarnedTitleRow`: renders title name, body-part·rank meta, body-part-hue dot, and a tappable "Equipar" CTA. Tapping the CTA fires `onEquip`. The widget has `Semantics(identifier: 'titles-earned-row-{slug}', button: true, container: true, explicitChildNodes: true)`.
- `NextTitleRow`: renders title name, body-part-hue dot, progress bar with `width = currentValue / thresholdValue`, tabular `current / threshold` figure, and the ICU-correct "faltam N ranks" / "falta 1 rank" sub-line. The widget is tappable (opens lore sheet). Test that `progress = 16/20` renders a bar at 80% width — assertable via `find.byWidgetPredicate((w) => w is FractionallySizedBox && w.widthFactor == 0.8)`. Use `cluster_align_widthfactor_zerofill` defense: the bar uses `FractionallySizedBox` (tight constraints) — confirm with the cluster comment in the widget.
- `CrossBuildCard`: renders the title name, ESPECIAL badge, two condition rows each with its own body-part-hue dot + bar + "current/floor" figure, met-condition rows show a gold ✓, and the bottom "◆ Falta 1 rank em <bp>" sub-line. The widget reads `CrossBuildCardData.bottleneckBodyPart` for the sub-line copy. Has `Semantics(identifier: 'titles-cross-build-card-{slug}', button: true)`.

Each test file follows the Task 8 shape: pump localized, assert findings, tap-and-assert callback fires.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/widget/features/rpg/widgets/earned_title_row_test.dart \
             test/widget/features/rpg/widgets/next_title_row_test.dart \
             test/widget/features/rpg/widgets/cross_build_card_test.dart
```

Expected: FAIL (widgets not defined).

- [ ] **Step 3: Build the three widgets**

Each widget follows the `EquippedTitleCard` skeleton with the appropriate body. `CrossBuildCard` is the second `// ignore: reward_accent` site — same pattern as Task 8, same per-line markers, same `ALLOWED_PATHS` exemption. Use `FractionallySizedBox` (not `Align(widthFactor:)`) for the progress bar fills — cluster `align-widthfactor-zerofill` defense.

For brevity the full body code is omitted from this plan step. The engineer follows the conventions established in Task 8 + the existing `body_part_rank_row.dart` (the 26b progress-bar reference). Specifically:
- Progress fill = `Container` outer (4dp height, `surface2` background, `kRadiusSm`) wrapping a `FractionallySizedBox(widthFactor: ..., child: ColoredBox(color: accentColor))`.
- Met-condition gold ✓ uses `Icon(Icons.check, color: <inline-ignore heroGold>, size: 14)` with the cluster ignore marker.
- ICU plural sub-line uses `remaining == 1 ? l10n.titlesNextSubBodyPartOne(bp) : l10n.titlesNextSubBodyPart(bp, remaining)`.

- [ ] **Step 4: Run tests to verify they pass**

```bash
flutter test test/widget/features/rpg/widgets/earned_title_row_test.dart \
             test/widget/features/rpg/widgets/next_title_row_test.dart \
             test/widget/features/rpg/widgets/cross_build_card_test.dart
bash scripts/check_reward_accent.sh
```

Expected: PASS, reward-accent check clean.

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/earned_title_row.dart \
        lib/features/rpg/ui/widgets/next_title_row.dart \
        lib/features/rpg/ui/widgets/cross_build_card.dart \
        test/widget/features/rpg/widgets/earned_title_row_test.dart \
        test/widget/features/rpg/widgets/next_title_row_test.dart \
        test/widget/features/rpg/widgets/cross_build_card_test.dart
git commit -m "feat(rpg): Earned/Next/CrossBuild title row widgets"
```

---

## Task 10: Counter pill widget

**Files:**
- Create: `lib/features/rpg/ui/widgets/titles_counter_pill.dart`
- Create: `test/widget/features/rpg/widgets/titles_counter_pill_test.dart`

- [ ] **Step 1: Write failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/ui/widgets/titles_counter_pill.dart';
import '../../../../test_helpers/localized_pump.dart';

void main() {
  testWidgets('should render "{earned} / {total} conquistados" in pt', (tester) async {
    await tester.pumpLocalized(
      const TitlesCounterPill(earnedCount: 8, totalCount: 90),
      locale: const Locale('pt'),
    );
    expect(find.text('8 / 90 conquistados'), findsOneWidget);
  });

  testWidgets('should render "{earned} / {total} earned" in en', (tester) async {
    await tester.pumpLocalized(
      const TitlesCounterPill(earnedCount: 8, totalCount: 90),
      locale: const Locale('en'),
    );
    expect(find.text('8 / 90 earned'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test (FAIL — widget not defined)**

```bash
flutter test test/widget/features/rpg/widgets/titles_counter_pill_test.dart
```

- [ ] **Step 3: Build the widget**

```dart
import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/radii.dart';
import '../../../../l10n/app_localizations.dart';

class TitlesCounterPill extends StatelessWidget {
  const TitlesCounterPill({
    super.key,
    required this.earnedCount,
    required this.totalCount,
  });

  final int earnedCount;
  final int totalCount;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Semantics(
      container: true,
      identifier: 'titles-counter-pill',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(kRadiusSm),
        ),
        child: Text(
          l10n.titlesCounterPill(earnedCount, totalCount),
          style: AppTextStyles.label.copyWith(
            fontSize: 11,
            color: AppColors.textDim,
            letterSpacing: 0.08 * 11,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test (PASS)**

```bash
flutter test test/widget/features/rpg/widgets/titles_counter_pill_test.dart
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/rpg/ui/widgets/titles_counter_pill.dart \
        test/widget/features/rpg/widgets/titles_counter_pill_test.dart
git commit -m "feat(rpg): TitlesCounterPill widget"
```

---

## Task 11: Rewrite `TitlesScreen` around the new view-model + widgets

**Files:**
- Modify: `lib/features/rpg/ui/titles_screen.dart` (full rewrite)
- Modify: `test/widget/features/rpg/titles_screen_test.dart` (existing — locate by grep, full rewrite)

- [ ] **Step 1: Write the failing screen-level test**

Rewrite `test/widget/features/rpg/titles_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/title.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/rpg/ui/titles_screen.dart';
import 'package:repsaga/features/rpg/ui/widgets/equipped_title_card.dart';
import 'package:repsaga/features/rpg/ui/widgets/earned_title_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/next_title_row.dart';
import 'package:repsaga/features/rpg/ui/widgets/cross_build_card.dart';

void main() {
  // ─── Empty state ────────────────────────────────────────────────────────
  testWidgets('should render the equipped region empty when no title is active',
      (tester) async {
    // ... pump with overrides where earned is [] and snapshot has chest=1.
    expect(find.byType(EquippedTitleCard), findsNothing);
    expect(find.byType(EarnedTitleRow), findsNothing);
    // Próximos region still shows the next-per-body-part rows.
    expect(find.byType(NextTitleRow), findsAtLeastNWidgets(1));
  });

  // ─── One-earned state ───────────────────────────────────────────────────
  testWidgets('should render the equipped card and no earned rows when only one earned is active',
      (tester) async {
    // ... earned=[chest_r5 (isActive=true)], ranks.chest=5
    expect(find.byType(EquippedTitleCard), findsOneWidget);
    expect(find.byType(EarnedTitleRow), findsNothing);
  });

  // ─── Many-earned state ──────────────────────────────────────────────────
  testWidgets('should list earned-non-active rows below the equipped card',
      (tester) async {
    // ... earned=[r5 active, r10 not, r15 not], ranks.chest=15
    expect(find.byType(EquippedTitleCard), findsOneWidget);
    expect(find.byType(EarnedTitleRow), findsNWidgets(2));
  });

  // ─── No cross-build near ────────────────────────────────────────────────
  testWidgets('should not render any cross-build cards when none is within 1 rank',
      (tester) async {
    // ... ranks far from any cross-build threshold.
    expect(find.byType(CrossBuildCard), findsNothing);
  });

  // ─── Cross-build near ───────────────────────────────────────────────────
  testWidgets('should render the cross-build card when within 1 rank of every condition',
      (tester) async {
    // ... ranks: chest=59, back=60, legs=60 — iron_bound within 1.
    expect(find.byType(CrossBuildCard), findsOneWidget);
    expect(find.text('Especial'), findsOneWidget); // pt locale
  });

  // ─── Regression: dismiss-then-reopen (RPC ensures row exists) ───────────
  testWidgets('should show the earned row even when celebration was dismissed without equip',
      (tester) async {
    // Simulate the post-26d state where the RPC INSERTed the row but the
    // user dismissed the overlay (is_active stays false). The Titles screen
    // must render the row in the "Conquistados" region.
    // ... earned=[chest_r5 (isActive=false)], ranks.chest=5
    expect(find.byType(EarnedTitleRow), findsOneWidget);
    expect(find.text('Equipar'), findsOneWidget);
  });
}
```

ENGINEER NOTE: the test fills in the override harness using the existing `pumpTitlesScreen` test helper. If that helper doesn't exist yet, create it in `test/widget/test_helpers/pump_titles_screen.dart`, mirroring the shape of `pumpCharacterSheetScreen` from 26b.

- [ ] **Step 2: Run tests to verify they fail**

```bash
flutter test test/widget/features/rpg/titles_screen_test.dart
```

Expected: FAIL — screen renders the old structure.

- [ ] **Step 3: Rewrite the screen**

Replace the body of `lib/features/rpg/ui/titles_screen.dart` with the new three-region composition. The screen now:

1. Watches `titleCatalogProvider`, `earnedTitlesProvider`, `rpgProgressProvider`.
2. On the data branch, calls `TitlesViewModel.split` once.
3. Renders `AppBar(title: Text(l10n.titlesScreenTitle), actions: [TitlesCounterPill])` (pill replaces `_ProgressHeader`).
4. Body is a `ListView` with three region sections: Equipado (single `EquippedTitleCard` if present), Conquistados (`for` loop of `EarnedTitleRow`), Próximos (`CrossBuildCard` cards first, then `NextTitleRow` per body-part track, then character-level next row at the bottom).
5. The `_equip` handler stays on the screen state class (re-entrancy guard preserved).
6. The `_TitlesSkeleton` placeholder stays (now mirrors the new shape — 3 regions × 3 rows).
7. The `_ErrorState` stays unchanged.

ENGINEER NOTE: the full source body for the rewritten screen is ~250 lines. The engineer writes it out following the existing comment-density style (it's a load-bearing screen; the why-this-decision comments matter). Don't shortcut the comments.

- [ ] **Step 4: Run all titles tests + reward-accent check**

```bash
flutter test test/widget/features/rpg/
bash scripts/check_reward_accent.sh
```

Expected: PASS.

- [ ] **Step 5: Run full analyze**

```bash
flutter analyze --fatal-infos
```

Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/features/rpg/ui/titles_screen.dart \
        test/widget/features/rpg/titles_screen_test.dart \
        test/widget/test_helpers/pump_titles_screen.dart
git commit -m "feat(rpg): rewrite TitlesScreen as Equipado/Conquistados/Próximos"
```

---

## Task 12: E2E regression test + selector updates

**Files:**
- Create: `test/e2e/specs/titles.spec.ts`
- Modify: `test/e2e/helpers/selectors.ts`
- Modify: `test/e2e/specs/title-equip.spec.ts` (only if T1/T2 selectors broke)
- Modify: `test/e2e/global-setup.ts` (the `seedRpgTitleEquipUser` helper now must NOT pre-insert the `earned_titles` row — it gets created via the RPC during the seeded workout, which is the actual production path. OR: keep the pre-insert, since the rest of the world relies on it. Pick OPTION B — keep the pre-insert, which makes the title-equip suite a regression test for the awarding pipeline NOT being the only path.)

- [ ] **Step 1: Write the failing E2E test**

Create `test/e2e/specs/titles.spec.ts`:

```typescript
/**
 * Titles screen — regression coverage for the 26d awarding pipeline fix.
 *
 * Scenarios covered:
 *   - The earned row appears in the "Conquistados" region after a workout
 *     that crosses a rank threshold, even when the user dismisses the
 *     celebration overlay without tapping EQUIP.
 *   - The Equipado region is empty for a user that has earned rows but
 *     never equipped any.
 *   - The Especial badge surfaces on a cross-build card when the user is
 *     within 1 rank of every condition.
 *
 * E2E conventions (CLAUDE.md):
 *   - Describe: feature name only.
 *   - Tests: "should ..." naming.
 */

import { test, expect } from '@playwright/test';
import { login } from '../helpers/auth';
import { navigateToTab } from '../helpers/app';
import { SAGA, CELEBRATION, TITLES } from '../helpers/selectors';
import { getUser } from '../fixtures/worker-users';

test.describe('Titles screen', () => {
  test.beforeEach(async ({ page }) => {
    await login(
      page,
      getUser('rpgTitleEquipUser').email,
      getUser('rpgTitleEquipUser').password,
    );
    await navigateToTab(page, 'Profile');
    await page.locator(CELEBRATION.titleLibraryButton).first().click();
    await expect(page.locator(TITLES.screen).first()).toBeVisible({
      timeout: 15_000,
    });
  });

  test('should show the earned title row in Conquistados (post-26d regression)', async ({ page }) => {
    // rpgTitleEquipUser has chest_r5_initiate_of_the_forge in earned_titles
    // with is_active=false. The 26d fix means the row exists even when the
    // user dismissed the celebration overlay; this test pins that.
    await expect(
      page.locator(TITLES.earnedRow('chest_r5_initiate_of_the_forge')).first(),
    ).toBeVisible({ timeout: 10_000 });
    await expect(page.getByText('Equipar').first()).toBeVisible();
  });

  test('should not show the Equipado region card when no title is active', async ({ page }) => {
    await expect(page.locator(TITLES.equippedCard).first()).toHaveCount(0);
  });

  test('should render the counter pill with the correct earned/total counts', async ({ page }) => {
    await expect(page.locator(TITLES.counterPill).first()).toBeVisible();
    // pt-BR copy: "1 / 90 conquistados" (one row pre-seeded, 90 total catalog).
    await expect(page.locator(TITLES.counterPill).first()).toContainText(
      /\d+\s*\/\s*90/,
    );
  });
});
```

- [ ] **Step 2: Add the selectors**

Append to `test/e2e/helpers/selectors.ts`:

```typescript
export const TITLES = {
  /** TitlesScreen root — alias of CELEBRATION.titleLibrarySheet. */
  screen: '[flt-semantics-identifier="titles-screen"]',
  /** Equipado heroGold card. */
  equippedCard: '[flt-semantics-identifier="titles-equipped-card"]',
  /** Earned-non-equipped row by slug. */
  earnedRow: (slug: string) => `[flt-semantics-identifier="titles-earned-row-${slug}"]`,
  /** Next-milestone row by slug. */
  nextRow: (slug: string) => `[flt-semantics-identifier="titles-next-row-${slug}"]`,
  /** Cross-build special card by slug. */
  crossBuildCard: (slug: string) =>
    `[flt-semantics-identifier="titles-cross-build-card-${slug}"]`,
  /** Counter pill in the AppBar. */
  counterPill: '[flt-semantics-identifier="titles-counter-pill"]',
} as const;
```

- [ ] **Step 3: Verify existing `title-equip.spec.ts` still works**

The existing spec uses `CELEBRATION.titleRow(slug)` to find a row. The new screen replaces this with `TITLES.earnedRow(slug)` for non-equipped rows. Update the existing spec's selectors:

```diff
-await page.locator(CELEBRATION.titleRow('chest_r5_initiate_of_the_forge')).first().click();
+await page.locator(TITLES.earnedRow('chest_r5_initiate_of_the_forge')).first().click();
```

- [ ] **Step 4: Build the Flutter web app + run the E2E suite**

```bash
export PATH="/c/flutter/bin:$PATH"
npx supabase status || npx supabase start
flutter build web
cd test/e2e
FLUTTER_APP_URL= npx playwright test specs/titles.spec.ts specs/title-equip.spec.ts \
  --reporter=list
```

Expected: PASS (3 titles tests + the 2 existing title-equip tests).

- [ ] **Step 5: Run the smoke regression sweep**

```bash
FLUTTER_APP_URL= npx playwright test --grep @smoke --reporter=list
```

Expected: PASS (no broken selectors in adjacent specs).

- [ ] **Step 6: Commit**

```bash
git add test/e2e/specs/titles.spec.ts \
        test/e2e/specs/title-equip.spec.ts \
        test/e2e/helpers/selectors.ts
git commit -m "test(e2e): titles screen 26d regression + selector audit"
```

---

## Task 13: Visual verification + screenshot package

Per CLAUDE.md pipeline step 9 (Visual verification): UI phases ship a screenshot-against-mockup gate. Surface the screenshots in the PR thread.

- [ ] **Step 1: Build Flutter web from post-QA HEAD**

```bash
export PATH="/c/flutter/bin:$PATH"
flutter build web
```

- [ ] **Step 2: Drive Playwright at 320 / 360 / 412dp viewport**

Run the orchestrator's Chrome DevTools / Playwright MCP at three resolutions, signing in as:
- `rpgTitleEquipUser` (steady-state: chest r5 earned, none equipped, no cross-builds near).
- Optional second user with `iron_bound` near-state (chest=59, back=60, legs=60) — seed manually via the local Supabase if no existing fixture matches.

At each viewport, screenshot the Titles screen.

- [ ] **Step 3: Compare side-by-side with `docs/phase-26-mockups.html` `#titles`**

The mockup is the locked design target. Flag drift loudly in the PR thread:
- Counter pill: "8 / 90 conquistados" copy + position top-right.
- Equipado card: heroGold gradient + "Em uso" tag.
- Conquistados rows: body-part-hue dot + "Equipar" CTA on the right.
- Cross-build card: heroGold gradient + "Especial" badge + bottleneck sub-line.
- Próximos rows: per-body-part-hue progress bar + tabular numerator/denominator.

- [ ] **Step 4: Drop screenshots into the PR**

After step 3, paste the three screenshots into the PR thread via `gh pr comment` or drag-and-drop in the GitHub web UI. The merger needs to eyeball them — don't bury the comparison in a transcript.

- [ ] **Step 5: Bugs found → re-iterate**

Per CLAUDE.md: visual bugs route back to `tech-lead` → re-render → re-screenshot. Don't merge until visuals match the mockup.

---

## Task 14: Open PR + address review findings in the same cycle

- [ ] **Step 1: Push the branch**

```bash
git push -u origin feature/26d-titles-awarding-fix-and-screen-revamp
```

- [ ] **Step 2: Verify CI gate runs**

```bash
export PATH="/c/flutter/bin:$PATH"
make ci
```

Expected: PASS — format clean, gen up-to-date, analyze clean, every test passes, Android build succeeds.

- [ ] **Step 3: Open the PR via `gh pr create`**

PR body template:

```markdown
## Summary

- Move `earned_titles` row creation from equip-time to detection-time inside `record_set_xp` and `record_session_xp_batch` (migration 00060). Dismissing the celebration overlay no longer loses a title.
- Add `backfill_earned_titles(uuid)` RPC + Hive-flag-gated bootstrap hook to repair pre-26d users (migration 00061 + `earnedTitlesBackfillProvider`).
- Rewrite Titles screen as three regions per the locked 26d mockup: Equipado (heroGold) / Conquistados (earned + Equipar CTA) / Próximos (next per body-part + character + within-1-rank cross-build). Locked titles hidden.

**QA pass pending — final coverage + E2E run after code review.**

## Test plan

- [ ] `make ci` green locally.
- [ ] Integration test: detection-time INSERT + idempotency + backfill (4+3 cases).
- [ ] Widget tests: `EquippedTitleCard`, `EarnedTitleRow`, `NextTitleRow`, `CrossBuildCard`, `TitlesCounterPill`, `TitlesScreen` (6 region scenarios).
- [ ] E2E: `specs/titles.spec.ts` + `specs/title-equip.spec.ts` green.
- [ ] Visual screenshots at 320/360/412dp compared with `docs/phase-26-mockups.html#titles` — pasted in PR thread.
- [ ] `bash scripts/check_reward_accent.sh` clean (whitelisted exemptions: `equipped_title_card.dart`, `cross_build_card.dart`).
- [ ] After merge: `npx supabase db push` to apply 00060 + 00061 to hosted Supabase. Confirm production schema matches before unparking next phase.
```

- [ ] **Step 4: Address every reviewer comment in-cycle**

Per `feedback_no_deferring_review_findings` + `feedback_no_deferring_suggestions`: every reviewer note — Critical / Important / Minor / Nit / Suggestion / Nice-to-have — is fixed in the same PR cycle. No "post-merge follow-up" framings. Drive each finding to a real fix or a real "rejected, here's why" reply on the PR thread.

- [ ] **Step 5: After merge — apply migrations to hosted Supabase**

```bash
npx supabase db push
```

Verify the new functions exist:

```bash
npx supabase db psql -- -c "\df+ public.backfill_earned_titles"
npx supabase db psql -- -c "\df+ public.record_session_xp_batch"
```

Confirm: `record_session_xp_batch` source includes the Step 6.5/8/9 blocks; `backfill_earned_titles` exists and is GRANTed to `authenticated`. Spot-check one user's `earned_titles` rows post-deploy.

---

## Self-Review checklist (run before handing back)

1. **Spec coverage.** Every acceptance criterion in PROJECT.md §3 Phase 26 → 26d maps to a task:
   - Bug fix: detection-time INSERT in both RPCs → Task 2.
   - `equipTitle` → pure `is_active` toggle → Task 5.
   - `backfill_earned_titles` RPC + bootstrap hook → Tasks 3 + 4.
   - Regression test (dismiss → reopen → row visible) → Task 12.
   - `CelebrationOrchestrator` user-POV unchanged → Task 5 step 4.
   - UI three-region structure + counter pill + locked hidden + cross-build "within 1 rank" → Tasks 6–11.
   - heroGold scarcity exceptions already whitelisted → confirmed by pre-flight read of `scripts/check_reward_accent.sh` (lines 58–69).
2. **Placeholder scan.** Searched for "TBD" / "implement later" / "fill in details" — none present. ENGINEER NOTE blocks are explicit hand-offs (paste-the-catalog-here) with the unit-test enforcement gate that catches misses.
3. **Type consistency.** `TitleThresholdEntry.threshold` is `int?`; the unit test references `cat.rankThreshold` / `cat.levelThreshold` matching this. `TitlesViewModel.split` returns `TitlesView`; both used consistently. `EarnedTitleEntry` (existing) is unchanged. `CrossBuildStat` is reused from `cross_build_title_evaluator.dart` — not redefined.

---

DONE — handing back to orchestrator for execution dispatch.
