# Pre-Launch Audit (Phase 33)

> Findings doc assembled from 5 parallel read-only audit agents.
> Each finding has a stable `finding-NNN (X)` identifier across all sections.
> Triage gate (Stage 2) stamps each `→ PR 33x` or `→ PARKED`.
> This doc is deleted in the final Phase 33 cleanup PR.

**Status:** Stage 2 (Triage) complete — 2026-06-01. 21 IMPORTANT findings stamped → fix wave; 11 NICE-TO-HAVE folded; 33 PARKED (revisit-conditions in PROJECT.md §2 → Phase 33 audit deferrals).

## Severity summary

| Section | CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK | Total |
|---|---|---|---|---|---|
| §A — Code review | 0 | 10 | 11 | 4 | 25 |
| §B — Security | 0 | 4 | 4 | 2 | 10 |
| §C — Wiring-trace test candidates | 0 | 0 | 0 | 0 | 0 |
| §D — E2E gap matrix | 0 | 11 | 14 | 1 | 26 |
| §E — Deletion candidates | 0 | 0 | 4 | 0 | 4 |
| **TOTAL** | **0** | **25** | **33** | **7** | **65** |

§E also contains one verification-only entry (`finding-065 (E)` — Phase 29.5 cleanup verified complete) that is not counted toward severity buckets.

**Orchestrator note (cross-section gap):** A5 §E sweep underdelivered relative to scope bullet #6 (orphan files in `lib/`). It missed `lib/features/rpg/ui/saga_stub_screen.dart` (an orphan widget with no import path) which A1's `finding-004 (A)` captures at IMPORTANT severity. A1's `finding-003 (A)` also has the RPE l10n keys at IMPORTANT (not NICE-TO-HAVE as §E rates them) and at a different line count (6 keys vs §E's 4 keys) — triage should consult `finding-003 (A)` as the canonical entry for that cluster. §D's per-block severity for `finding-D-13` (now `finding-042 (D)` — Post-session B3 PR cut) is IMPORTANT per the block contents, contradicting the agent's own summary-table placement of it in NICE-TO-HAVE; orchestrator trusts the block-level severity. Re-dispatch of A5 not warranted because A1's overlap already surfaces the gaps.

## Triage stamps (Stage 2 outcome — 2026-06-01)

Per Phase 33 spec, each finding stamped → PR 33x (fix-wave home) or → PARKED (revisit-condition in PROJECT.md §2 Phase 33 audit deferrals). Triage walk-through: 3 chunks of CRITICAL+IMPORTANT (none CRITICAL, 25 IMPORTANT) + 1 batch of 33 NICE-TO-HAVE. 4 IMPORTANTs downgraded to PARK during walk-through (non-goals "no refactor-for-refactor's-sake" + 32g platform-untestable note). 11 NICE-TO-HAVEs folded into adjacent fix PRs at near-zero marginal cost.

### Fix wave shape

| Fix PR | IMPORTANT | Folded NICE-TO-HAVE | Total items |
|---|---|---|---|
| **PR 33a — Security** | 4 (finding-026, 027, 028, 029) | 3 (finding-030, 031, 033) | 7 |
| **PR 33b — Dead-code + developer.log batch** | 4 (finding-001, 003, 004, 010) | 3 (finding-012, 014, 021) | 7 |
| **PR 33c — Workout-flow** | 9 (finding-005, 009, 036, 037, 038, 039, 041, 044, 046) | 3 (finding-011, 013, 059) | 12 |
| **PR 33d — RPG / share** | 3 (finding-042, 043, 045) | 1 (finding-055) | 4 |
| **PR 33e — Auth / profile** | 1 (finding-002) | 1 (finding-056) | 2 |
| **PR 33f — Residual** | **CLOSED** — both flagged findings (finding-006, 008) parked | — | 0 |
| **Total** | 21 | 11 | 32 |

### IMPORTANT dispositions (21)

| Finding | Title (one-liner) | → Home |
|---|---|---|
| finding-001 (A) | `developer.log` in 5 core files | → PR 33b |
| finding-002 (A) | `CodexNavRow` Semantics pair-rule miss | → PR 33e |
| finding-003 (A) | RPE l10n keys (Phase 25 drop) | → PR 33b |
| finding-004 (A) | `SagaStubScreen` orphan widget | → PR 33b |
| finding-005 (A) | `bpProgressFractionPre` unused (TODO 30b) | → PR 33c |
| finding-009 (A) | `_flushDebouncedSave` missing mounted/error handling | → PR 33c |
| finding-010 (A) | `_syncToRemote` developer.log + .catchError | → PR 33b (moved from 33e — same cluster as -001) |
| finding-026 (B) | `validate-purchase` body field length cap + UUID | → PR 33a |
| finding-027 (B) | `validate-purchase` JWT verify ordering | → PR 33a |
| finding-028 (B) | Edge Fn JSON body size cap (32KB) | → PR 33a |
| finding-029 (B) | `ws` CVE in test/e2e | → PR 33a |
| finding-036 (D) | Onboarding 4 tests skip (global-setup) | → PR 33c |
| finding-037 (D) | Sign-up happy path E2E | → PR 33c |
| finding-038 (D) | Active workout banner tap E2E | → PR 33c |
| finding-039 (D) | Workout detail content E2E | → PR 33c |
| finding-041 (D) | CONTINUAR CTA E2E | → PR 33c |
| finding-042 (D) | Post-session B3 PR cut E2E | → PR 33d |
| finding-043 (D) | Exercise retirement E2E | → PR 33d |
| finding-044 (D) | `/records` in-app nav E2E | → PR 33c |
| finding-045 (D) | Weight unit toggle E2E | → PR 33d |
| finding-046 (D) | Week-complete review 4 tests skip (global-setup) | → PR 33c |

### Folded NICE-TO-HAVE dispositions (11)

| Finding | Parent IMPORTANT | → Home | Fold rationale |
|---|---|---|---|
| finding-011 (A) | finding-005 | → PR 33c | Inline `_emptyBpFractions()` cleanup during -005 fix |
| finding-012 (A) | finding-004 | → PR 33b | `make gen` regen already needed after -004 delete |
| finding-013 (A) | finding-005 | → PR 33c | Doc comment on `bpProgressFractionPre` |
| finding-014 (A) | finding-001 | → PR 33b | Drop `dart:developer` import after migration |
| finding-021 (A) | finding-001 | → PR 33b | Same file (`pending_sync_provider.dart`) already in batch |
| finding-030 (B) | finding-027 | → PR 33a | `delete-user` same JWT-verify ordering shape |
| finding-031 (B) | finding-027 (size-cap batch) | → PR 33a | `delete-user` platform/version allowlist (~10 lines) |
| finding-033 (B) | finding-028 | → PR 33a | `rtdn-webhook` base64 cap fits size-cap pattern |
| finding-055 (D) | (post-session surface) | → PR 33d | Unskip overflow-card tap; stale Path-A note |
| finding-056 (D) | finding-002 | → PR 33e | Unskip 26-tap-routing-e2e; content-visibility assertion |
| finding-059 (D) | finding-037 | → PR 33c | Extend `auth.spec.ts:276` full-journey w/ Records row |

### Downgrades during triage (4 originally-IMPORTANT → PARKED)

| Finding | One-liner | Park rationale (revisit-condition in PROJECT.md §2) |
|---|---|---|
| finding-006 (A) | `week_plan_screen.dart` 566-line build method | Non-goals "no refactor-for-refactor's-sake"; v1.1 polish |
| finding-007 (A) | `set_row.dart` 4 build methods > 200 lines | Same |
| finding-008 (A) | `progress_chart_section.dart` build methods | Same |
| finding-040 (D) | Empty-session guard sheet E2E | 32g triaged as platform-untestable on Flutter web; widget test owns contract |

### PARKED summary

- **Downgraded IMPORTANTs:** 4 (see above)
- **NICE-TO-HAVEs parked:** 22 (out of 33)
- **Pre-existing PARK from agent severity:** 7 (finding-022, 023, 024, 025 (A) + 032, 034, 035 (B) + 061 (D))
- **Verification-only (not in severity buckets):** 1 (finding-065 (E) — Phase 29.5 cleanup verified complete)

Full park rationale + revisit-conditions live in **PROJECT.md §2 → Phase 33 audit deferrals**. Each parked finding has a concrete revisit-condition per Phase 33 triage principles (no vague "later").

## Finding-block reference

Each finding follows this format:

```
### finding-NNN — <one-liner>
- File: `path/to/file.dart:LINE` (or "(N files)" for batch findings)
- Current: <observed behavior>
- Recommended: <change>
- Severity: CRITICAL | IMPORTANT | NICE-TO-HAVE | PARK
- Suggested home: PR 33x | PARK | adjacent
- Cluster ref (optional): <cluster-name>
```

## §A — Code review

Surveyed 342 Dart files; 25 findings; severity breakdown: 0 CRITICAL / 10 IMPORTANT / 11 NICE-TO-HAVE / 4 PARK.

---

### IMPORTANT

### finding-001 (A) — `developer.log` in 5 core files evades adb logcat

- File: `lib/core/local_storage/cache_service.dart:21,33,48,57` — also `lib/core/offline/pending_sync_provider.dart:71,137`, `lib/core/l10n/locale_provider.dart:82,89`, `lib/core/local_storage/hive_service.dart:184,212,226`, `lib/features/personal_records/providers/pr_cache_bootstrap_provider.dart:118,141,155`
- Current: All five files import `dart:developer` and call `developer.log()` / bare `log()` for operational diagnostics (cache misses, offline-queue errors, locale sync failures, Hive box recovery, PR-cache migration). The `developer-log-invisible-logcat` cluster documents that these messages are DevTools-only — they never appear in `adb logcat`, so on-device debugging of those paths produces silent failures. PR 32g fixed all occurrences in `active_workout_notifier.dart` but did not sweep these five files.
- Recommended: Replace `developer.log(...)` calls in these five files with `debugPrint('[Scope] msg')` using `package:flutter/foundation.dart`. Fold the `log(name:, level:, error:, stackTrace:)` structured fields into a single debugPrint string. Reserve `developer.log` only for DevTools-attached sessions.
- Severity: IMPORTANT
- Suggested home: PR 33b
- Cluster ref: `developer-log-invisible-logcat`

### finding-002 (A) — `CodexNavRow` emits `Semantics(identifier:)` without pair-rule flags

- File: `lib/features/rpg/ui/widgets/codex_nav_row.dart:40`
- Current: When `semanticIdentifier != null` the widget wraps `inner` with `Semantics(identifier: semanticIdentifier, child: inner)` — no `container: true`, no `explicitChildNodes: true`. The `semantics-identifier-pair-rule` cluster states that every `Semantics(identifier:)` exposed for E2E must carry both flags. Without them, Flutter Web's AOM silently elides the identifier node on rebuild, making E2E selectors for the Stats / Titles / History codex rows unreliable. The widget is wired to three `CodexNavRow` calls on `CharacterSheetScreen` where all three pass `semanticIdentifier`.
- Recommended: Change the conditional wrap to: `Semantics(container: true, explicitChildNodes: true, identifier: semanticIdentifier!, child: inner)`. The `explicitChildNodes: true` is especially important here because `inner` already contains a `Text` that would otherwise merge up into the same AOM node.
- Severity: IMPORTANT
- Suggested home: PR 33e
- Cluster ref: `semantics-identifier-pair-rule`

### finding-003 (A) — RPE l10n keys in both ARBs are dead code

- File: `lib/l10n/app_en.arb:1179` and `lib/l10n/app_pt.arb:475` (6 keys: `rpeTooltip`, `rpeValue`, `rpeMenuItem`, `rpeLabel`, `setRpe`, `rpeLabel`)
- Current: Phase 25 (RPE tracking) was dropped on 2026-05-15. The six ARB keys and their generated getters/methods in `app_localizations.dart` (lines ~2661–2833) exist across both locale files but are never called anywhere in `lib/features/**`. Grep confirms zero usage of `l10n.rpeTooltip`, `l10n.rpeValue`, `l10n.rpeLabel`, `l10n.rpeMenuItem`, or `l10n.setRpe` across all feature code. These inflate the generated `app_localizations.dart` by ~170 lines and will confuse future agents searching for RPE references.
- Recommended: Delete the six ARB keys from both `app_en.arb` and `app_pt.arb`, regenerate localizations with `make gen`, verify CI passes. The `ExerciseSet.rpe` model field should be retained per the PROJECT.md §2 v1.1 spec (zero cost; notifier already wires it).
- Severity: IMPORTANT
- Suggested home: PR 33b

### finding-004 (A) — `SagaStubScreen` is a dead widget with no import path

- File: `lib/features/rpg/ui/saga_stub_screen.dart:13`
- Current: `SagaStubScreen` is declared but never imported or instantiated anywhere in `lib/`. The router (`app_router.dart`) does not reference it; no feature file imports it. The class doc says it's a placeholder for "Stats deep-dive → 18d, Titles → 18c" — both of which shipped (Phase 26c for Stats, Phase 26d for Titles). The `comingSoonStub` l10n key it consumes is also reachable from no UI path. This file + l10n key mislead agents who grep for "Coming soon" or "stub."
- Recommended: Delete `lib/features/rpg/ui/saga_stub_screen.dart`. Also remove `comingSoonStub` from both ARB files and regenerate.
- Severity: IMPORTANT
- Suggested home: PR 33b

### finding-005 (A) — `bpProgressFractionPre` stored but never consumed

- File: `lib/features/workouts/ui/post_session/post_session_controller.dart:34,50`
- Current: `PostSessionParams` declares `required Map<BodyPart, double> bpProgressFractionPre` and stores it as `final Map<BodyPart, double> bpProgressFractionPre`. The coordinator always passes `_emptyBpFractions()` (an empty map). The controller's `_buildInitial()` method never reads `params.bpProgressFractionPre` — confirmed by exhaustive grep (zero `params.bpProgressFractionPre` references). A `// TODO(30b): populate from the pre-finish snapshot...` comment in the coordinator acknowledges this. The parameter misleads future implementors into thinking the B2 tally-cut bars animate from a non-trivial pre-state, when they always start from 0%.
- Recommended: Either (a) implement the TODO — capture `RankCurve.progressFraction(preXp, preRank)` per-BP in the coordinator before `await notifier.finishWorkout()` (same capture pattern as `bpRankBefore`) and pass it through; or (b) if the visual is acceptable as-is, remove `bpProgressFractionPre` from `PostSessionParams` and the controller entirely. Option (a) is the correct fix; option (b) accepts the visual limitation permanently.
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-006 (A) — `week_plan_screen.dart` single `build` method is 566 lines

- File: `lib/features/weekly_plan/ui/week_plan_screen.dart:133`
- Current: The `_WeekPlanScreenState.build` method is 566 lines long — over 11x the CLAUDE.md 50-line guidance. It directly constructs every section (header counter pill, bucket chip row, engagement section, week review section, plan-empty state, add-routines FAB, undo snackbar, soft-cap warning) inline. Two private helper methods (`_buildRoutineRow`, `_buildBucketChipRow`) exist but are not enough. No `_buildBody` / `_buildHeader` / `_buildPlanContent` extractions. When future agents need to modify the week-plan flow, they must parse 566 lines of interleaved state reads, conditional build branches, and layout code to locate the relevant section.
- Recommended: Extract private build helpers: `_buildHeader(...)`, `_buildBucketSection(...)`, `_buildEngagementSection(...)`, `_buildWeekReview(...)`, `_buildEmptyState(...)`. Each should be ≤60 lines. The `build()` root becomes a Scaffold+body that delegates to those helpers.
- Severity: IMPORTANT
- Suggested home: PR 33f

### finding-007 (A) — `set_row.dart` build methods routinely exceed 200 lines

- File: `lib/features/workouts/ui/widgets/set_row.dart:166,379,580,1078` (4 build methods)
- Current: Four build methods in `set_row.dart` exceed 200 lines: `_SetRowState.build` (212 lines at line 166), `_SetRowFrame.build` (200 lines at line 379), `_SetNumberCell.build` (187 lines at line 580), and `_WeightStepperCellState.build` (215 lines at line 1078). The file itself is 1350 lines. The per-widget decomposition is good at the class level — the problem is that each class's own `build` method has grown too large. The `_SetRowFrame.build` is particularly dense: it contains the full 5-state PR-chrome conditional inline, with each branch repeating the full `Dismissible → Padding → Row` skeleton.
- Recommended: In `_SetRowFrame.build`, extract `_buildDismissible(PrRowState state) → Widget` and delegate the chrome-by-state table to `_prChromeForState(PrRowState) → ({Color stripe, ...})`. In `_WeightStepperCellState.build`, extract `_buildEditingMode(...)` and `_buildDisplayMode(...)`. Each extracted method should fit within 60 lines.
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-008 (A) — `progress_chart_section.dart` build methods exceed 100–180 lines

- File: `lib/features/exercises/ui/widgets/progress_chart_section.dart:99,187,376,483` (4 build methods)
- Current: Four build methods exceed the 50-line guideline: `ProgressChartSection.build` (87 lines), `_ChartContent.build` (139 lines), `_PrDotsDecorLayer.build` (106 lines), `_AxisChart.build` (181 lines). `_AxisChart.build` is the most egregious — it inlines the full fl_chart `LineChartData` construction with left/bottom/right axis tick formatters, dot painter callbacks, and touch-tooltip builder as nested lambdas.
- Recommended: In `_AxisChart.build`, extract `_buildLineChartData()`, `_buildLeftAxis()`, `_buildBottomAxis()`, `_buildTouchTooltip()` as private helpers. In `_ChartContent.build`, extract `_buildFilterRow()` and `_buildChartCard()`.
- Severity: IMPORTANT
- Suggested home: PR 33f

### finding-009 (A) — `_flushDebouncedSave` uses `.then()` instead of `await` — error silently swallowed and no mounted check

- File: `lib/features/weekly_plan/ui/week_plan_screen.dart:634`
- Current: `_flushDebouncedSave` calls `notifier.upsertPlan(_bucketRoutines)` and chains `.then((_) { _maybeShowSavedSnackbar(); }).catchError((_) {})`. The `.then()` callback calls `_maybeShowSavedSnackbar()` but does not guard with `if (mounted)` — if the widget is disposed between the debounce-flush and the future completing (e.g. user navigates away while save is in flight), calling `_maybeShowSavedSnackbar()` accesses `ScaffoldMessenger.of(context)` on a disposed state and throws. The `.catchError((_) {})` swallows all errors silently (no log, no Sentry capture).
- Recommended: Restructure as an `async` method: `Future<void> _flushDebouncedSave() async { try { await notifier.upsertPlan(...); if (mounted) _maybeShowSavedSnackbar(); } catch (e) { debugPrint('[WeekPlanScreen] flush save failed: $e'); } }`. This also fixes the missing `mounted` guard.
- Severity: IMPORTANT
- Suggested home: PR 33c
- Cluster ref: `async-caller-broke-snackbar`

### finding-010 (A) — `_syncToRemote` in `locale_provider.dart` uses `developer.log` on both sync and async error paths

- File: `lib/core/l10n/locale_provider.dart:82,89`
- Current: See finding-001 (A) for the cluster rationale. Additionally the `_syncToRemote` method uses `.catchError` chained directly on the Future (a pattern that makes it harder to add typed error handling later), and the error messages are only visible in DevTools. For locale sync failures on physical devices the diagnostic is completely invisible.
- Recommended: Combined fix with finding-001 (A) — replace `developer.log(...)` with `debugPrint('[LocaleNotifier] Failed to sync locale: $e')`. Also consider wrapping the `repo.updateLocale(...)` in `unawaited(() async { try { await ...; } catch (e) { debugPrint(...); } }())` to keep the explicit try/catch pattern consistent with the rest of the codebase (PR 32g style).
- Severity: IMPORTANT
- Suggested home: PR 33e
- Cluster ref: `developer-log-invisible-logcat`

---

### NICE-TO-HAVE

### finding-011 (A) — `_emptyBpFractions()` is a trivially wrappable helper

- File: `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:598`
- Current: `_emptyBpFractions()` is a private helper that just returns `<BodyPart, double>{}`. It exists solely to give the empty map a name, but since the TODO to actually populate this was left in place (finding-005 (A)), the abstraction adds confusion rather than clarity — the name implies eventual intent while the body is a literal empty map.
- Recommended: Replace the call site with an inline `const <BodyPart, double>{}` (or `_emptyBpFractions()` → remove and inline), and co-locate the TODO comment with the `bpProgressFractionPre:` argument. Once finding-005 (A) is fixed (real pre-fraction population), remove the empty default entirely.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33c

### finding-012 (A) — `SagaStubScreen` `comingSoonStub` l10n key remains in generated files

- File: `lib/l10n/app_localizations.dart:219`, `lib/l10n/app_localizations_en.dart:69`, `lib/l10n/app_localizations_pt.dart:70`
- Current: After deleting `SagaStubScreen` (finding-004 (A)), the `comingSoonStub` key persists in the generated localizations until `make gen` is run. Flagging separately so the PR checklist includes regeneration.
- Recommended: Run `make gen` after deleting the ARB key. Verify `app_localizations.dart` no longer exports `comingSoonStub`.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33b

### finding-013 (A) — `PostSessionParams.bpProgressFractionPre` field is undocumented as intentionally empty

- File: `lib/features/workouts/ui/post_session/post_session_controller.dart:50`
- Current: The field declaration has no doc comment explaining that it is always passed as `{}` today and is unused pending the TODO(30b). Future agents reading the struct will assume it is populated and may build logic on a false premise.
- Recommended: Add a doc comment: `/// Pre-finish rank-progress fraction per BP. Currently always empty — see TODO(30b) in finish_workout_coordinator.dart for the planned population path.`
- Severity: NICE-TO-HAVE
- Suggested home: PR 33c

### finding-014 (A) — `developer.log` in `cache_service.dart` is unguarded import of `dart:developer`

- File: `lib/core/local_storage/cache_service.dart:2`
- Current: `import 'dart:developer';` is unaliased. The bare `log(...)` calls are easy to confuse with the Dart `dart:core` top-level `print` or any future introduction of a logging package. The PR 32g CI gate (`check_no_developer_log.sh`) presumably gates only on `developer.log(` (prefixed form) and would miss the bare `log(` form.
- Recommended: After migrating all calls to `debugPrint` (finding-001 (A) fix), remove the import. Confirm the CI gate pattern covers bare `log(` usage or extend `check_no_developer_log.sh` accordingly.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33b

### finding-015 (A) — `_workoutSource` has an open TODO for `planned_bucket` discrimination

- File: `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:239`
- Current: A `// TODO post-PR: differentiate 'planned_bucket' when config exposes the flag` comment exists in `_workoutSource()`. The method always returns `'routine_card'` or `'empty'` — a `planned_bucket` analytics source was never wired. This means workout-started events from the week-plan bucket chips are attributed to `'routine_card'` (same as direct routine list taps), making funnel attribution between "started from plan" vs "started from routine list" impossible in analytics.
- Recommended: The `RoutineStartConfig` model should carry a `source` discriminator. Pass `'planned_bucket'` when starting from `WeekPlanScreen`, `'routine_card'` when starting from `RoutineListScreen`. Update `_workoutSource` to consume it.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33d

### finding-016 (A) — `rank $rankThreshold.` hardcoded English in `_titleSubLabel`

- File: `lib/features/workouts/ui/post_session/post_session_screen.dart:953`
- Current: `'${state.bodyPartLabels[bodyPart] ?? bodyPart.dbValue} · rank $rankThreshold.'` — the word "rank" is hardcoded in English. The post-session summary panel is a user-visible surface that ships pt-BR. If the user's locale is pt, this label should read "rank $rankThreshold." in Portuguese (or use the `l10n.rankLabel` / `l10n.rank` key if one exists).
- Recommended: Check whether an l10n key for "rank" exists; if not, add `"rank": "rank"` / `"@rank": {}` to both ARBs and reference it here. Alternatively move the entire `_titleSubLabel` rendering to the `PostSessionController._buildInitial()` pass where `l10n` is already available.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33d

### finding-017 (A) — `set_row.dart` `_SetRowState.build` at line 166 is 212 lines and embeds inline logic

- File: `lib/features/workouts/ui/widgets/set_row.dart:166`
- Current: The root `_SetRowState.build` is 212 lines. It reads multiple providers, computes PR row state, decides whether to show a completion-flash overlay, conditionally builds the `RewardAccent.provide(...)` wrapper, and assembles a `Semantics(key: ValueKey(rowStateId), ...)`. The logic for deriving `rowStateId`, `display`, `goldColor`, and the snap-to-complete flash is interspersed with widget construction.
- Recommended: Extract `_resolveDisplay(WidgetRef ref) → (PrRowDisplay, Color?)` and `_buildRowContent(PrRowDisplay display, Color? goldColor) → Widget` out of `build`. The `Semantics` wrapper + `ValueKey` assignment remains in `build` (≤30 lines).
- Severity: NICE-TO-HAVE
- Suggested home: PR 33c

### finding-018 (A) — `ProgressChartSection._AxisChart.build` (181 lines) inlines full fl_chart data

- File: `lib/features/exercises/ui/widgets/progress_chart_section.dart:483`
- Current: `_AxisChart.build` is 181 lines, inlining the full `LineChartData` construction with axis configs, dot painter lambdas, and tooltip builder directly in the method. Any future chart variant or responsive adaptation requires navigating all 181 lines.
- Recommended: Extract `_buildAxisTitlesData()`, `_buildLineBarsData()`, `_buildTouchData()` as private helpers on `_AxisChart`. Each is self-contained and ≤ 50 lines.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33f

### finding-019 (A) — `active_workout_notifier.dart` is 2050 lines

- File: `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:1`
- Current: The notifier is 2050 lines. While the heavy commenting accounts for much of that size, the file mixes: lifecycle methods (start/startFromRoutine/finish/discard/cancel), set-CRUD methods (add/delete/restore/swap/reorder/complete), RPG bridge methods (buildAndStashCelebration, recordZeroXpSession, consumeLastCelebration), analytics helpers (_trackWorkoutEvent, _workoutSource), and Hive helpers (_saveToHive). The celebration-build logic at line ~1923 is a 70-line async method that could live in a separate `ActiveWorkoutRpgBridge` class.
- Recommended: Extract `_buildAndStashCelebration` + the `_firstAwakeningFiredThisSession`, `_lastCelebration`, `_lastSessionTotalXpDelta`, `_lastSessionBpDeltas` state fields into an `ActiveWorkoutCelebrationBridge` mixin or standalone helper that the notifier delegates to. The consume methods and per-session throttle logic move with them.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33c

### finding-020 (A) — `finish_workout_coordinator.dart` is 776 lines with a 500-line `finish()` method

- File: `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:92`
- Current: The `finish()` method is approximately 500 lines. It serially handles: empty-session guard, confirm dialog, state captures (×5 `ref.read` calls before await), the `finishWorkout` await, error-path snackbar, cache invalidations, offline-snackbar branch, celebration orchestration, post-session navigation. Each concern is well-commented but the serial length makes the dependency graph of the five pre-await captures hard to audit. `_computeSetsCount` and `_computeTonnage` at the bottom are small but could be extracted to the domain layer alongside `SessionLiftSummary`.
- Recommended: Extract the pre-await capture block (lines ~144–236) into `_capturePreFinishContext(WidgetRef ref, ActiveWorkoutState? state) → _PreFinishContext` record type. Extract the post-finish snackbar + invalidation block into `_handleOnlineFinish(...)`. Each extraction reduces cognitive scope when reading individual paths.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33c

### finding-021 (A) — `PendingMarkRoutineComplete` legacy drain log via `developer.log` in `pending_sync_provider.dart`

- File: `lib/core/offline/pending_sync_provider.dart:137`
- Current: A legacy drain path for `PendingMarkRoutineComplete` (pre-26e entries) calls bare `log(...)`. As noted in finding-001 (A), this is DevTools-only and invisible in adb logcat. The comment explains these entries only exist for users upgrading from a pre-26e build — but if such an upgrade occurs today, the diagnosis is invisible on physical device.
- Recommended: Replace the `log(...)` with `debugPrint('[PendingSyncNotifier] 26e: ...')`.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33b
- Cluster ref: `developer-log-invisible-logcat`

---

### PARK

### finding-022 (A) — `PostSessionController` uses `ChangeNotifier` instead of Riverpod

- File: `lib/features/workouts/ui/post_session/post_session_controller.dart:97`
- Current: The `PostSessionController` extends `ChangeNotifier` rather than an `AsyncNotifier`. The class doc explains the choice: Riverpod 3 dropped `StateNotifierProvider` family API and the codegen form requires hashable params (`AppLocalizations` + `PostSessionParams` are not hashable). The reasoning is sound and documented.
- Recommended: No action needed for launch. If Riverpod 3 adds `@riverpod` family support for non-hashable params in a future release, this could be revisited. The current pattern is architecturally justified.
- Severity: PARK
- Suggested home: PARK

### finding-023 (A) — `_routerProvider` `redirect` reads `activeWorkoutProvider` inside router factory

- File: `lib/core/router/app_router.dart:137`
- Current: The `/workout/active` route's `redirect` callback calls `ref.read(activeWorkoutProvider).value` and `ref.read(hasActiveWorkoutProvider)`. This is a `Provider` (not `AsyncNotifier`) factory read, which is fine — `ref.read` is synchronous here. But the outer `routerProvider = Provider<GoRouter>((ref) {...})` captures `ref` in a long-lived closure; the redirect runs on every navigation. This is the established GoRouter pattern and is correct.
- Recommended: No action. Current pattern is idiomatic GoRouter with Riverpod.
- Severity: PARK
- Suggested home: PARK

### finding-024 (A) — `rank $rankThreshold.` may be intentional design copy

- File: `lib/features/workouts/ui/post_session/post_session_screen.dart:953`
- Current: This is already flagged in finding-016 (A) as NICE-TO-HAVE. Flagging again as PARK because the post-session summary is a celebratory context where "rank N" may be intentionally kept as a universal noun — the word "rank" is used as-is in the Brazilian fitness community (similar to how "RPG" and "XP" are used untranslated). The product-owner should decide.
- Recommended: Product-owner triage: confirm whether "rank" should stay as English across both locales or use a localized form.
- Severity: PARK
- Suggested home: PARK (product decision)

### finding-025 (A) — `_WeightStepperCellState.build` is 215 lines of inline editing-mode widget tree

- File: `lib/features/workouts/ui/widgets/set_row.dart:1078`
- Current: `_WeightStepperCellState.build` at line 1078 is 215 lines, constructing the inline keyboard editing mode (TextField with focus listeners, done button, keyboard dismiss) and display mode side-by-side. The widget is already extracted as a `ConsumerStatefulWidget`; the concern here is purely build-method length, not architecture.
- Recommended: Extract `_buildEditingMode(...)` and `_buildDisplayMode(...)` private methods. This is a cosmetic split — no behavior changes.
- Severity: PARK
- Suggested home: PARK (v1.1 polish)

## §B — Security

Widens PR 32b's targeted audit which shipped 0 criticals across 21 RLS-scoped user-data tables + 4 Edge Functions. Scope of this widening: all Edge Function input paths (validate / size / type / order vs JWT-verify), signed-URL TTL, deeplink hijack vectors, dependency CVE surface, bundle-secret re-sweep, new-table RLS sweep (migrations 00067–00071), CORS, LGPD posture, and Auth/PKCE session handling.

**Counts:** 0 CRITICAL · 4 IMPORTANT · 4 NICE-TO-HAVE · 2 PARK (10 findings total). The PR 32b baseline holds — every CRITICAL bullet on the checklist returned clean. The 4 IMPORTANT findings are all defense-in-depth gaps (input-validation tightening, JWT-verify ordering, missing UUID format check) that an attacker cannot directly exploit today but should be closed before public launch.

### Checklist result (per-bullet verification)

1. **Edge Function input validation** — `delete-user` clamps `platform` / `app_version` to 64 bytes (good). `validate-purchase` type-checks `product_id` / `purchase_token` / `user_id` / `source` as strings but applies NO length caps, NO regex/format check, and NO UUID validation on the `user_id` field even on the service-role branch. `rtdn-webhook` defers to Google's signed payload (length implicitly bounded by Play). `vitality-nightly` only accepts `chunk` (0–9) and `source` (audit-only). See findings 026 (B), 027 (B), 033 (B).
2. **Signed-URL TTL audit** — `avatar_repository.dart:59` ships `signedUrlExpirySeconds = 365 * 24 * 60 * 60` (1yr). Only signed-URL issuer in `lib/`. TTL is appropriate for rarely-rotated user content. No finding.
3. **Deeplink hijack vectors** — `AndroidManifest.xml` exports MainActivity with one custom-scheme intent filter `io.supabase.repsaga` (login-callback). No host filter, but the scheme is namespaced under our package identifier and Supabase SDK validates the callback URL fragment before extracting tokens. The scheme is only used for OAuth state, not for app-action deeplinks (no PIN, no admin actions, no in-app payment). See finding-034 (B).
4. **Dependency CVE scan** — `flutter pub outdated` shows 12 direct deps + 32 transitives upgradable. No CVE-grade hits on pinned versions (`supabase_flutter 2.12.2`, `go_router 17.2.0`, `flutter_riverpod 3.3.1`, `permission_handler 11.4.0`, `share_plus 10.1.4`, `image_picker 1.1.2`, `sentry_flutter 9.16.1`, `hive 2.2.0`). `npm audit` on `test/e2e/` flags **1 moderate** in transitive `ws` (8.0.0–8.20.0, GHSA-58qx-3vcg-4xpx — uninitialized memory disclosure, fix available via `npm audit fix`). E2E-only, never bundled into shipped app, but devs running Playwright are exposed. See finding-029 (B).
5. **Bundle secrets re-sweep** — Grep across `lib/` for `sk_live_` / `sk_test_` / `eyJ…` / `xoxb-` / bearer tokens / service-role keys / GCP SA JSON returned only one hit: a doc comment in `auth_repository.dart:131` referring to "the service-role key" (no actual key). `lib/` clean. No finding.
6. **New-table RLS sweep (00067–00071)** — `workout_template_translations` (00067): RLS enabled, SELECT-only to authenticated, INSERT/UPDATE/DELETE service-role only. ✓ — Avatars bucket (00068 → 00069 flip): public-read policy dropped, replaced with `auth.uid()::text = (storage.foldername(name))[1]` for SELECT/INSERT/UPDATE/DELETE. ✓ — `get_workout_history_with_aggregates` (00070) + `get_workout_xp`: `SECURITY INVOKER` so RLS on `workouts` / `xp_events` / `personal_records` / `sets` short-circuits at the SELECT layer. ✓ — `peak_load_per_body_part` (00071): `SECURITY INVOKER`, `WHERE w.user_id = p_user_id` predicate, RLS on `workouts` enforces ownership regardless of the parameter. ✓ — No finding.
7. **JWT verification on Edge Functions** — `rtdn-webhook` verifies Pub/Sub JWT BEFORE envelope parse ✓ (line 261-269). `vitality-nightly` verifies service-role JWT BEFORE body parse ✓ (line 378). `delete-user` checks Authorization header presence first, parses optional body, then verifies JWT — body parsing is bounded (only two short strings clamped to 64b each), acceptable. `validate-purchase` checks header presence, then parses request body BEFORE JWT-validity check (`getUser` at line 416 runs after `req.json()` at line 385). The gateway has already verified the JWT *signature* before our handler runs (verify_jwt is default-on, only `rtdn-webhook` disables it via `config.toml`), so a forged service-role claim is structurally impossible. But the *getUser network round-trip* runs after body parse. See finding-027 (B).
8. **CORS configuration** — All four functions pin `Access-Control-Allow-Origin` to `Deno.env.get('SUPABASE_URL')`. `validate-purchase` / `rtdn-webhook` / `vitality-nightly` fail-loud at module load if `SUPABASE_URL` is unset; `delete-user` uses `?? ''` fallback (same effect — empty Allow-Origin blocks all browser CORS). No wildcard origins. No finding.
9. **LGPD/GDPR posture** — Avatars bucket flipped public→private mid-PR (00069). Bucket privacy state confirmed in migration. Zero live users when the flip happened (pre-launch), so no stale public objects to remediate. `exercise-media` bucket remains public-read but holds only editorial demo content seeded by service-role — not user-uploaded personal data, so LGPD does not apply. Account-deletion path (`delete-user` Edge Function) cascades via FK across all user tables; the audit row in `account_deletion_events` is intentionally anonymous (no `user_id` column). No finding.
10. **Auth + session** — PKCE flow set in `main.dart:60` via `FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce)`. Refresh-token rotation enabled in `supabase/config.toml:167`. Session tokens persist via `supabase_flutter`'s platform-native secure storage (Keychain / EncryptedSharedPreferences). Grep for `Hive.*token` / `Hive.*Session` / `Hive.*jwt` returns no matches — no plaintext token persistence in app code. Sentry `sendDefaultPii: false` + `beforeSend` scrubs email-like strings + `beforeBreadcrumb` drops crumbs containing `@`. PII posture is strict. No finding.

---

### IMPORTANT

### finding-026 (B) — `validate-purchase` lacks length cap + UUID format validation on body fields

- File: `supabase/functions/validate-purchase/index.ts:390-411`
- Current: `product_id`, `purchase_token`, `source`, and `user_id` are type-checked as strings but have no length cap, no format/UUID validation, no allow-list on `source`. A malformed `user_id` from a service-role caller hits Postgres `uuid` cast and 500s (instead of cleanly 400ing). A 10MB `source` string lands verbatim in `subscription_events.notification_type` as `validate:<source>`.
- Recommended: clamp `product_id` ≤ 128 chars, `purchase_token` ≤ 4096, `source` ≤ 32 (and consider an allow-list `{'client','cron_reconcile'}`), validate `body.user_id` against `/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i` before passing it to `validatePurchase()`. Mirror the `clampMeta` pattern already used in `delete-user`.
- Severity: IMPORTANT
- Suggested home: PR 33a

### finding-027 (B) — `validate-purchase` parses request body BEFORE JWT validity verification

- File: `supabase/functions/validate-purchase/index.ts:384-417`
- Current: handler reads `req.json()` at line 385, runs `isServiceRoleJwt(jwt)` decode (which the comment correctly notes is safe because the gateway verified the signature already), then ONLY in the user branch calls `userClient.auth.getUser(jwt)` at line 416 — a network round-trip that constitutes the actual *validity* check (signature is verified by gateway, but expiry / revocation / user-still-exists is what `getUser` enforces). An attacker who presents an expired/revoked JWT triggers a full body parse + `JSON.parse` cycle before the 401 fires.
- Recommended: move `getUser` (or `decodeJwt(jwt).exp > now` cheap precheck) ahead of `req.json()`. Pattern matches `vitality-nightly` and `rtdn-webhook` (auth-then-body). No CRITICAL because (a) gateway already verified signature, (b) JSON.parse is bounded by Deno's default request size, (c) the user-branch service-role decode is local-only.
- Severity: IMPORTANT
- Suggested home: PR 33a

### finding-028 (B) — Edge Functions accept arbitrary-size JSON bodies (no app-level cap)

- File: `supabase/functions/{delete-user,validate-purchase,rtdn-webhook,vitality-nightly}/index.ts`
- Current: none of the four functions check `Content-Length` header before `await req.json()` / `req.text()`. Supabase Edge Runtime imposes a platform-level body ceiling (~10MB), but no app-level cap exists. A 9MB payload to `delete-user` or `validate-purchase` will be fully parsed before the type-check on each field rejects it.
- Recommended: add a 32KB request-body cap (Content-Length check + 413 response) at the top of each `serve()` handler, before `req.json()`. Trivially small for our actual payloads (`delete-user` ≤ 200B, `validate-purchase` ≤ 1KB, `rtdn-webhook` ≤ 8KB for Pub/Sub envelopes, `vitality-nightly` ≤ 100B).
- Severity: IMPORTANT
- Suggested home: PR 33a

### finding-029 (B) — `ws` 8.0.0–8.20.0 transitive in `test/e2e/` has known moderate CVE

- File: `test/e2e/package-lock.json` (transitive of `@playwright/test ^1.44.0`)
- Current: `npm audit` reports GHSA-58qx-3vcg-4xpx (uninitialized memory disclosure) on `ws` 8.0.0–8.20.0. Fix available via `npm audit fix`.
- Recommended: run `cd test/e2e && npm audit fix` (likely lifts `ws` to ≥ 8.20.1 transitively). Verify Playwright still passes the full e2e suite after the bump. Dev-only impact — never shipped to user devices — but a Playwright worker reading attacker-crafted WebSocket frames is the realistic blast radius (browser test contexts that hit hostile origins).
- Severity: IMPORTANT
- Suggested home: PR 33a

---

### NICE-TO-HAVE

### finding-030 (B) — `delete-user` parses body BEFORE auth.getUser JWT validity check

- File: `supabase/functions/delete-user/index.ts:64-108`
- Current: same shape as finding-027 (B) — header-presence check (line 65), env check, body parse (lines 82-96), then `getUser(jwt)` at line 105. Lower exposure than finding-027 (B) because body is much tighter (two clamped strings, no recursive JSON parsing), but ordering is the same.
- Recommended: same fix as finding-027 (B) — verify JWT validity (or at least decode + `exp` precheck) before `await req.json()`. Either fix the two functions together in PR 33a or move the precheck into a `_shared/auth.ts` helper that both `delete-user` and `validate-purchase` (and any future stateful endpoint) call uniformly.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33a (fold into finding-027 (B) fix)

### finding-031 (B) — `delete-user` audit insert uses caller-supplied `platform` / `app_version` without server-side allow-listing

- File: `supabase/functions/delete-user/index.ts:82-96`
- Current: `platform` and `app_version` are clamped to 64 bytes but otherwise free-form. A bad client can write `platform = "ios"` on an Android device (or arbitrary string). The audit row drives churn analytics — feeding adversarial values pollutes the dashboard.
- Recommended: validate `platform` against an allow-list `{'android','ios','web'}` and reject (or coerce to `'unknown'`) on mismatch. Validate `app_version` against `/^\d+\.\d+\.\d+(\+\d+)?$/`. Both can be coercion-style (silently strip) rather than 400-style (rejecting) because the audit row is "best-effort" already per the function's design.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33a (small)

### finding-032 (B) — `flutter pub outdated` shows multiple major-version-behind direct deps

- File: `pubspec.yaml` (12 direct deps with newer stable lines, see `flutter pub outdated` output)
- Current: `connectivity_plus` 6.1.5 → 7.1.1, `google_fonts` 6.3.3 → 8.1.0, `package_info_plus` 9.0.1 → 10.1.0, `permission_handler` 11.4.0 → 12.0.3, `share_plus` 10.1.4 → 13.1.0, `wakelock_plus` 1.5.1 → 1.6.1. No known CVEs on the pinned versions — gap is purely "behind current". `share_plus` and `package_info_plus` are pinned intentionally (Dart SDK constraint per `pubspec.yaml:54` + L44 comment).
- Recommended: PARK to a v1.1 dependency-refresh PR after launch. Bumping multiple major versions pre-launch is high-risk for low security yield. Re-evaluate when Dart SDK constraint changes or a CVE drops on a pinned version.
- Severity: NICE-TO-HAVE
- Suggested home: PARK (v1.1 dependency refresh)

### finding-033 (B) — `rtdn-webhook` `decodePubSubPayload` does not cap embedded base64 payload size

- File: `supabase/functions/rtdn-webhook/index.ts:141-148`
- Current: `atob(envelope.message.data)` followed by `JSON.parse` runs against arbitrary-size base64 (envelope itself is capped by Deno's request limit, but a 10MB envelope still produces a 7MB decoded payload). Google's actual RTDNs are ≤ ~2KB, so anything > 16KB is malicious.
- Recommended: after `atob`, check `json.length > 16384` → throw `Error('payload too large')` → 400. The handler already returns 200 on `testNotification` and unknown notification types, so attacker can't force expensive DB work; the only cost would be CPU on JSON.parse. Defense-in-depth, not exploitable.
- Severity: NICE-TO-HAVE
- Suggested home: PR 33a (fold into finding-028 (B) size cap)

---

### PARK

### finding-034 (B) — `AndroidManifest.xml` intent filter accepts `io.supabase.repsaga` with no host filter

- File: `android/app/src/main/AndroidManifest.xml:73-78`
- Current: `<data android:scheme="io.supabase.repsaga"/>` accepts any host and any path on the custom scheme. The OAuth callback is `io.supabase.repsaga://login-callback/`, but the filter as written matches `io.supabase.repsaga://attacker.example/admin/delete` too. Mitigations: (1) the only consumer is the Supabase SDK which validates the URL fragment for a valid `access_token` / `code` before doing anything stateful; (2) the scheme is namespaced under our package identifier so other apps cannot claim it pre-installation; (3) no in-app routing reads custom-scheme paths.
- Recommended: tighten to `<data android:scheme="io.supabase.repsaga" android:host="login-callback"/>` so the OS only routes matching authorities to MainActivity. Purely defense-in-depth — no current code path exploits the looseness.
- Severity: PARK
- Suggested home: PARK (no clear attacker model in v1; revisit if a second deeplink surface ships)

### finding-035 (B) — `_shared/google_play.ts` JWK cache lacks size cap + signed access-token cache lifetime trusts Google response uncritically

- File: `supabase/functions/_shared/google_play.ts:258-282, 116-148`
- Current: `loadGoogleJwks` caches the entire JWK set for 1h with no upper bound on the number of keys (Google currently returns ~3 RSA keys, but a malicious or compromised upstream could return 10k). `getPlayAccessToken` uses `json.expires_in ?? 3600` from the token endpoint — a malicious upstream returning `expires_in: 999999999` would cache a stale token forever.
- Recommended: cap JWK count at 16; cap token TTL at `Math.min(json.expires_in, 3600)` (Google's documented contract). Threat model is upstream-Google-or-MITM-compromise, very low likelihood with TLS pinning by Deno's fetch, but the bound is cheap.
- Severity: PARK
- Suggested home: PARK (Google upstream compromise is out-of-scope for v1)

## §C — Wiring-trace test candidates

Surveyed 307 test files (157 in `test/unit/` + 150 in `test/widget/`); **0 findings**; severity breakdown: 0 CRITICAL / 0 IMPORTANT / 0 NICE-TO-HAVE / 0 PARK.

**Result:** comprehensive mechanical wiring-trace pattern search completed across all four patterns from the agent prompt: `verify(...).called`, `when(...).thenAnswer` chains without downstream `expect(find...)`, tests with zero `expect(find...)` assertions, `tester.pump(Duration(...))` without downstream rendered-output assertion. The RepSaga test suite demonstrates strong discipline in following the "test user-visible behavior, not wiring" rule from CLAUDE.md — no violations surfaced.

**Why zero findings:**

1. `celebration_orchestrator_test.dart` uses `verify(...).called(N)` patterns ONLY — but this is a LEGITIMATE exception per CLAUDE.md ("fire-and-forget analytics emission test must `verify(.called)` because there's no UI consequence"). The function is explicitly fire-and-forget with contract documented as a cosmetic side effect (writing pulse timestamps to Hive).
2. Widget tests across all surfaces consistently assert rendered output via `expect(find.text(...))`, `expect(find.byType(...))`, or widget property assertions. Examples: `snackbar_tap_out_dismiss_scope_drain_test.dart` pumps animation `Duration` then measures rendered filler width; `active_workout_add_exercise_snackbar_dismiss_test.dart` pumps then asserts snackbar text/visibility; `ambient_pulse_dot_test.dart` pumps then asserts ring border alpha.
3. Unit tests with mocks use the `_RecordingAnalyticsRepository` pattern (capture event values, assert EXACT payload). Examples: `active_workout_notifier_zero_xp_emit_test.dart` asserts `recorded.props['exercise_count']` not just `verify(insertEvent).called(1)`; `weekly_plan_notifier_set_optimistic_test.dart` asserts `state.value` changes synchronously.
4. No Pattern 3 violations (tests with zero `expect(find...)`) — widget tests have rendering assertions OR are unit tests with behavior assertions.
5. No Pattern 4 violations (`tester.pump(Duration)` without downstream assertion) — all pumps are followed by `expect(...)` within 5 lines. Some tests even reference the cluster `pump_duration_masks_forward` in inline comments.

**Code-quality signal:** explicit cluster references in test comments (`pump_duration_masks_forward`, `persist-eats-duration`) + behavior-asserting widget tests (drain-bar width, ring alpha, snackbar text/visibility) + factory-pattern tests that verify both wiring AND behavior demonstrate the post-PR-#214 culture stuck. Maintain the current discipline on new tests.

_No findings in any severity bucket._

## §D — E2E gap matrix

**Route inventory:** 27 user-reachable screens/surfaces extracted from the GoRouter config and modal surfaces triggered via navigation actions.

**Actions/error-paths enumerated:** 89 (screen × action/error-path) cells.

**Coverage summary:**
- COVERED: 51 cells
- PARTIAL: 18 cells
- MISSING: 20 cells

**Finding blocks:** 26 total (11 IMPORTANT, 14 NICE-TO-HAVE, 1 PARK). PARK findings beyond the 1 numbered block are not enumerated individually; 3 PARK-class surfaces are identified in the preamble: (1) `/paywall` — not yet implemented (Launch Phase dep); (2) deeplink cold-start (out-of-app URL open); (3) push notification tap-to-launch.

**Existing skipped tests surfaced:** 6 `test.skip()` blocks are called out as findings below (onboarding full flow, week-complete review state, overflow card tap, saga body-part row routing, ActionHero create-first-routine branch, PR empty-state condition).

**Note on agent's internal severity tally:** the agent's summary table at the bottom of its return listed 25 findings total with D-13 placed in NICE-TO-HAVE; the per-block severity in D-13 says IMPORTANT. Orchestrator trusts the per-block severity. Adjusted counts: 11 IMPORTANT / 14 NICE-TO-HAVE / 1 PARK / 26 total.

---

### Coverage matrix

| Screen | Action / Error Path | Status | Existing test | Notes |
|---|---|---|---|---|
| `/login` | Render login screen with fields + buttons | COVERED | `auth.spec.ts:24` | @smoke |
| `/login` | Email/password sign-in (happy path) | COVERED | `auth.spec.ts:41` | @smoke |
| `/login` | Sign-in with wrong password → error message | COVERED | `auth.spec.ts:53` | @smoke |
| `/login` | Sign-in with non-existent email → error | COVERED | `auth.spec.ts:164` | — |
| `/login` | Sign-in with empty fields → validation error | COVERED | `auth.spec.ts:179` | — |
| `/login` | Malformed email (no @) → inline error | COVERED | `auth.spec.ts:205` | — |
| `/login` | Toggle to sign-up mode → button/subtitle change | COVERED | `auth.spec.ts:117` | @smoke |
| `/login` | Sign-up with already-registered email → error | COVERED | `auth.spec.ts:257` | — |
| `/login` | Complete sign-up with new account (full flow) | MISSING | — | No actual successful new-account creation E2E |
| `/login` | Forgot password → send reset email → feedback | COVERED | `auth.spec.ts:78` | @smoke |
| `/login` | Google Sign-In button visible | COVERED | `auth-google.spec.ts` | @smoke |
| `/login` | Google Sign-In OAuth flow wired (request fires) | COVERED | `auth-google.spec.ts` | @smoke |
| `/onboarding` | Page 1 welcome renders (conditional on fresh user) | PARTIAL | `onboarding.spec.ts:44` | test.skip() fires when user already onboarded |
| `/onboarding` | GET STARTED → page 2 profile setup | PARTIAL | `onboarding.spec.ts:85` | test.skip() fires same condition |
| `/onboarding` | Complete onboarding → redirect to /home | PARTIAL | `onboarding.spec.ts:122` | test.skip() fires same condition |
| `/onboarding` | Back button on page 2 → page 1 | PARTIAL | `onboarding.spec.ts:162` | test.skip() fires same condition |
| `/email-confirmation` | Screen renders + confirmation message | MISSING | — | No spec reaches this route |
| `/privacy-policy` | LegalDocScreen renders correct content | MISSING | — | Route exists; no E2E |
| `/terms-of-service` | LegalDocScreen renders correct content | MISSING | — | Route exists; no E2E |
| `/home` | Home screen renders with ActionHero | COVERED | `workouts.spec.ts:164` | @smoke |
| `/home` | CharacterCard collapsed on load | COVERED | `home.spec.ts:120` | @smoke |
| `/home` | CharacterCard expand/collapse toggle | COVERED | `home.spec.ts:131,152` | @smoke |
| `/home` | Closest rank-up indicator (trained user) | COVERED | `home.spec.ts:287` | — |
| `/home` | Encouragement nudge renders | COVERED | `home.spec.ts:195` | @smoke |
| `/home` | Day-0 first-step fallback (fresh user) | COVERED | `home.spec.ts:184` | @smoke |
| `/home` | ActionHero free-workout branch | COVERED | `home.spec.ts:203` | @smoke |
| `/home` | ActionHero start-routine branch (bucket non-empty) | COVERED | `home.spec.ts:369` | — |
| `/home` | ActionHero create-first-routine branch | PARTIAL | `home.spec.ts:448` | test.skip() — schema-migration dependency |
| `/home` | BucketChipRow renders with planned chips | COVERED | `home.spec.ts:346` | — |
| `/home` | BucketChipRow empty state | COVERED | `home.spec.ts:216` | @smoke |
| `/home` | Editar plano link → /plan/week navigation | COVERED | `home.spec.ts:245` | @smoke |
| `/home` | Tap planned bucket chip → routine sheet → start workout | COVERED | `home.spec.ts:395` | — |
| `/home` | Body-part row in expanded CharacterCard → /saga/stats | COVERED | `home.spec.ts:300` | — |
| `/home` | Last session line tap → /home/history | COVERED | `history-localization.spec.ts:34` | — |
| `/home` | Active workout banner renders while in-progress | PARTIAL | `workouts.spec.ts:226` | Asserts stat cards, not banner specifically |
| `/home` | Active workout banner tap → resume /workout/active | MISSING | — | No direct banner-tap-from-home isolated test |
| `/home/history` | History list renders with week headers + XP eyebrow | COVERED | `history-localization.spec.ts:100` | @smoke |
| `/home/history` | History empty state | COVERED | `workouts.spec.ts:964` | — |
| `/home/history` | History error state → Retry button | MISSING | — | `HISTORY.retryButton` selector exists; no test |
| `/home/history` | PR diamond badge renders on workout card with PRs | MISSING | — | `HISTORY.cardPrDiamond` selector exists; no test |
| `/home/history/:id` | Workout detail screen renders | PARTIAL | `workouts.spec.ts:731` | Asserts one weight value; no full content assertion |
| `/home/history/:id` | Detail strip (XP + PR count) renders | MISSING | — | `HISTORY.detailStrip` selector unexercised |
| `/workout/active` | Start empty workout (ActionHero) | COVERED | `workouts.spec.ts:182` | @smoke |
| `/workout/active` | Start routine workout (from routine card) | COVERED | `routines.spec.ts:339` | @smoke |
| `/workout/active` | Resume active workout after page reload | COVERED | `crash-recovery.spec.ts:170` | — |
| `/workout/active` | Add exercise from picker | COVERED | `workouts.spec.ts:480` | — |
| `/workout/active` | Add exercise auto-seed from prior session | COVERED | `workouts.spec.ts:2800` | @smoke |
| `/workout/active` | Set weight via dialog | COVERED | `workouts.spec.ts:536` | — |
| `/workout/active` | Set reps via dialog | COVERED | `workouts.spec.ts:536` | — |
| `/workout/active` | Complete set (checkbox toggle) | COVERED | `workouts.spec.ts:584` | — |
| `/workout/active` | Add multiple sets | COVERED | `workouts.spec.ts:556` | — |
| `/workout/active` | Swipe-to-delete set → undo SnackBar | COVERED | `workouts.spec.ts:1104` | — |
| `/workout/active` | Swipe-to-delete SnackBar auto-dismisses | COVERED | `workouts.spec.ts:1247` | — |
| `/workout/active` | Undo set deletion | COVERED | `workouts.spec.ts:1180` | — |
| `/workout/active` | Cascading undo restores set order | COVERED | `workouts.spec.ts:2216` | — |
| `/workout/active` | Swap exercise (no completed sets) | COVERED | `workouts.spec.ts:1757` | — |
| `/workout/active` | Swap exercise (completed sets → confirm dialog) | COVERED | `workouts.spec.ts:1800` | — |
| `/workout/active` | Remove exercise from workout | COVERED | `workouts.spec.ts:1627` | — |
| `/workout/active` | Add exercise → undo SnackBar | COVERED | `workouts.spec.ts:1908` | — |
| `/workout/active` | Exercise reorder toggle visible at 2+ exercises | MISSING | — | No promoted regression spec |
| `/workout/active` | Workout notes field (enter text) | MISSING | — | Selector exists; only in skipped charter-d |
| `/workout/active` | Finish workout (happy path) | COVERED | `workouts.spec.ts:124` | @smoke |
| `/workout/active` | Finish with zero sets → empty-session guard | PARTIAL | widget tests only | No E2E assertion for the guard sheet |
| `/workout/active` | Finish with incomplete sets → dialog warning | COVERED | `workouts.spec.ts:611` | — |
| `/workout/active` | Discard workout → confirm dialog → home | COVERED | `workouts.spec.ts:681` | — |
| `/workout/active` | Discard → cancel → stay in workout | COVERED | `workouts.spec.ts:1339` | — |
| `/workout/active` | Discard re-entrance during stalled DELETE | COVERED | `workouts.spec.ts:2071` | — |
| `/workout/active` | Loading overlay Stop button → cancel restores | COVERED | `workouts.spec.ts:1503` | @smoke |
| `/workout/active` | Decimal weight round-trip (22.5 kg) | COVERED | `workouts.spec.ts:731` | — |
| `/workout/active` | Exercise detail sheet (tap exercise name) | COVERED | `workouts.spec.ts:790` | — |
| `/workout/active` | PR signal in set row (standing-PR state) | COVERED | `rank-up-celebration.spec.ts:1043` | @smoke |
| `/workout/active` | PR row loading state → reclassify on data landing | COVERED | `workouts.spec.ts:2551` | @smoke |
| `/workout/active` | Rest overlay: FAB + finish bar hidden during timer | COVERED | `workouts.spec.ts:2724` | @smoke |
| `/workout/active` | Disabled Finish helper text when no sets complete | COVERED | `workouts.spec.ts:2374` | — |
| `/workout/active` | Bodyweight prompt SnackBar on first bodyweight set | COVERED | `bodyweight-prompt.spec.ts` | @smoke |
| `/workout/active` | Offline finish → queued to pending badge → home | COVERED | `offline-sync.spec.ts:485` | — |
| `/workout/active` | Network error during save → error SnackBar | COVERED | `offline-sync.spec.ts:673` | — |
| `/workout/finish/:workoutId` | Post-session screen renders (skip to summary) | COVERED | `post_session.spec.ts:92` | @smoke |
| `/workout/finish/:workoutId` | Beat 1 XP cut visible | PARTIAL | `rank-up-celebration.spec.ts:426` | No isolated B1 assertion |
| `/workout/finish/:workoutId` | Beat 2 body-part tally cut | PARTIAL | `rank-up-celebration.spec.ts:426` | No isolated B2 assertion |
| `/workout/finish/:workoutId` | Beat 3 PR cut visible | MISSING | — | `POST_SESSION.b3Pr` unexercised |
| `/workout/finish/:workoutId` | Beat 3 Title Unlock cut visible | PARTIAL | `rank-up-celebration.spec.ts:513` | Multi-event flow only |
| `/workout/finish/:workoutId` | Beat 3 Class Change cut + EQUIP row | COVERED | `rank-up-celebration.spec.ts:1298` | @smoke |
| `/workout/finish/:workoutId` | Skip button advances to summary | COVERED | `post_session.spec.ts` beforeEach | @smoke |
| `/workout/finish/:workoutId` | Mission Debrief section renders | COVERED | `post_session.spec.ts:92` | @smoke |
| `/workout/finish/:workoutId` | Mission Debrief lift row visible | COVERED | `post_session.spec.ts:100` | @smoke |
| `/workout/finish/:workoutId` | Mission Debrief XP bar visible | COVERED | `post_session.spec.ts:122` | @smoke |
| `/workout/finish/:workoutId` | Mission Debrief BP rank delta row visible | COVERED | `post_session.spec.ts:111` | @smoke |
| `/workout/finish/:workoutId` | Share CTA → share sheet opens | COVERED | `share_flow.spec.ts:154` | @smoke |
| `/workout/finish/:workoutId` | Share sheet Discreet row → preview screen | COVERED | `share_flow.spec.ts:168` | @smoke |
| `/workout/finish/:workoutId` | Preview retake → back to share sheet | COVERED | `share_flow.spec.ts:189` | @smoke |
| `/workout/finish/:workoutId` | Preview share button tap → export | MISSING | — | Selector asserted visible but never tapped |
| `/workout/finish/:workoutId` | Empty-session guard sheet (finish with 0 sets) | MISSING | — | Widget/unit coverage only |
| `/workout/finish/:workoutId` | CONTINUAR CTA → /home navigation | MISSING | — | Tests beforeEach skips to summary; CTA tap untested |
| `/workout/finish/:workoutId` | Leave-confirm dialog on back press | MISSING | — | PopScope unreachable from Playwright web |
| `/exercises` | Exercise list renders with search | COVERED | `exercises.spec.ts:46` | @smoke |
| `/exercises` | Muscle group filter narrows list | COVERED | `exercises.spec.ts:191,530` | @smoke |
| `/exercises` | Equipment filter narrows list | COVERED | `exercises.spec.ts:259,557` | @smoke |
| `/exercises` | Search input filters exercises | COVERED | `exercises.spec.ts:81,272` | @smoke |
| `/exercises` | Combined filter + search | COVERED | `exercises.spec.ts:576` | — |
| `/exercises` | Clear filters restores full list | COVERED | `exercises.spec.ts:605` | — |
| `/exercises` | Empty state (filter yields zero results) | COVERED | `exercises.spec.ts:696` | — |
| `/exercises` | User-created exercise creation (FAB) | COVERED (as negative) | `exercises.spec.ts:61` | Negative pin: FAB retired in 32h |
| `/exercises/:id` | Exercise detail renders | COVERED | `exercises.spec.ts:305` | @smoke |
| `/exercises/:id` | Form tips render without backslash-n artifacts | COVERED | `exercises.spec.ts:362` | @smoke |
| `/exercises/:id` | Start/end images visible for seeded exercises | COVERED | `exercises.spec.ts:755` | — |
| `/exercises/:id` | Progress chart renders for user with logged sets | COVERED | `exercises.spec.ts:434` | @smoke |
| `/exercises/:id` | Delete custom exercise → confirm → removed | COVERED | `exercises.spec.ts` library group | — |
| `/exercises/:id` | Retire exercise (32h) → removes from workout picker | MISSING | — | Only unit-test coverage |
| `/routines` | Routines list renders with MY ROUTINES + STARTER | COVERED | `routines.spec.ts:658` | @smoke |
| `/routines` | Create routine → save → appears in MY ROUTINES | COVERED | `routines.spec.ts:65` | @smoke |
| `/routines` | Edit routine name via action sheet | COVERED | `routines.spec.ts:113` | @smoke |
| `/routines` | Delete routine via action sheet → confirm | COVERED | `routines.spec.ts:171` | @smoke |
| `/routines` | Start workout from starter routine | COVERED | `routines.spec.ts:339` | @smoke |
| `/routines` | Start routine with all-deleted exercises → error SnackBar | COVERED | `routines.spec.ts:593` | @smoke |
| `/routines/create` | CreateRoutineScreen renders + add exercise | COVERED | `routines.spec.ts:65` | @smoke |
| `/routines/create` | Exercise reorder in routine builder | MISSING | — | No drag-to-reorder test |
| `/records` | Records screen renders with PR cards (trained user) | COVERED | `personal-records.spec.ts:322` | @smoke |
| `/records` | Records empty state (fresh user) | COVERED | `personal-records.spec.ts:357` | @smoke |
| `/records` | PR card shows max-weight label + value | COVERED | `personal-records.spec.ts:339` | @smoke |
| `/records` | PR card shows entry after completing a set | COVERED | `personal-records.spec.ts:510` | @smoke |
| `/records` | Records screen reachable via codex navigation | MISSING | — | Tests use hash navigation only |
| `/profile` | Character sheet renders for fresh user (banner visible) | COVERED | `saga.spec.ts:89` | @smoke |
| `/profile` | Character sheet renders for trained user | COVERED | `saga.spec.ts:125` | @smoke |
| `/profile` | CharacterXpBar visible | COVERED | `saga.spec.ts:169` | @smoke |
| `/profile` | Class label visible | COVERED | `saga.spec.ts:485` | — |
| `/profile` | Active title visible on sheet | COVERED | `title-equip.spec.ts:126` | — |
| `/profile` | Body-part row tap → stats deep-dive pre-selected | PARTIAL | `saga.spec.ts:591` | test.skip() with TODO(26-tap-routing-e2e) |
| `/profile` | Gear icon → profile settings navigation | COVERED | `saga.spec.ts:194` | @smoke |
| `/profile` | Codex nav Stats row → /saga/stats | COVERED | `saga.spec.ts:230` | @smoke |
| `/profile` | Codex nav Titles row → /saga/titles | COVERED | `saga.spec.ts:248` | @smoke |
| `/profile` | Codex nav History row → /home/history | COVERED | `saga.spec.ts:263` | @smoke |
| `/profile/settings` | Profile settings screen renders | COVERED | `localization.spec.ts:131` | @smoke |
| `/profile/settings` | Weight unit toggle kg→lbs (or lbs→kg) | MISSING | — | Selectors exist; no test taps them |
| `/profile/settings` | Language picker switch en↔pt + persistence | COVERED | `localization.spec.ts:236,196,271` | @smoke |
| `/profile/settings` | Member-since date renders in pt-BR format | COVERED | `localization.spec.ts:168` | @smoke |
| `/profile/settings` | Avatar surface renders + picker sheet opens | COVERED | `profile.spec.ts:222` | @smoke |
| `/profile/settings` | Log out → confirm → /login | COVERED | `auth.spec.ts:69` | @smoke |
| `/profile/settings` | Weekly goal frequency display + change | COVERED | `profile.spec.ts:45,91` | @smoke |
| `/profile/settings/manage-data` | Manage Data screen renders + delete history flows | COVERED | `manage-data.spec.ts:485,539,581,708,748` | — |
| `/profile/settings/manage-data` | Delete account (full account deletion) | COVERED | `manage-data.spec.ts:267` | @smoke |
| `/saga/stats` | Stats deep-dive renders (3 sub-widgets) | COVERED | `saga.spec.ts:327` | @smoke |
| `/saga/stats` | Vitality trend chart visible + explainer + row tap | COVERED | `saga.spec.ts:327,351,371` | @smoke |
| `/saga/stats` | Fresh user can access without activity gate | COVERED | `saga.spec.ts:437` | @smoke |
| `/saga/stats` | Volume peak blocks render per body part | PARTIAL | `saga.spec.ts:327` | No per-block assertion |
| `/saga/titles` | Titles screen renders + equip + active title pill | COVERED | `titles.spec.ts:95,133`, `title-equip.spec.ts:81,126` | — |
| `/plan/week` | Week plan screen renders with compact layout | COVERED | `weekly-plan.spec.ts:758` | @smoke |
| `/plan/week` | Add workout CTA renders | COVERED | `weekly-plan.spec.ts:774` | @smoke |
| `/plan/week` | Engagement section 6 bars + explainer sheet | COVERED | `weekly-plan.spec.ts:784,812` | @smoke |
| `/plan/week` | Add routine to plan | COVERED | `weekly-plan.spec.ts:214` | @smoke |
| `/plan/week` | Remove routine via swipe (undo SnackBar) | COVERED | `weekly-plan.spec.ts:606` | — |
| `/plan/week` | Clear week → confirm | COVERED | `weekly-plan.spec.ts:360` | @smoke |
| `/plan/week` | Create new routine from within AddRoutinesSheet | MISSING | — | Selector exists; no test |
| `/plan/week` | Week complete state renders | PARTIAL | `weekly-plan.spec.ts:458–521` | 4 tests test.skip() — seeded state missing |
| `RPG — Gamification intro` | SagaIntroOverlay renders 3 steps + dismiss → home | COVERED | `gamification-intro.spec.ts` | @smoke |
| `RPG — Rank-up` | Single rank-up posts XP + navigates home | COVERED | `rank-up-celebration.spec.ts:426` | @smoke |
| `RPG — Rank-up` | Multi-event sequence (rank + level + title) | COVERED | `rank-up-celebration.spec.ts:513` | @smoke |
| `RPG — Rank-up` | First awakening overlay fires for ≤1 body part | COVERED | `rank-up-celebration.spec.ts:643` | @smoke |
| `RPG — Rank-up` | Overflow cap at 3 → overflow card visible | COVERED | `rank-up-celebration.spec.ts:748` | @smoke |
| `RPG — Rank-up` | Overflow card tap → /profile navigation | PARTIAL | `rank-up-celebration.spec.ts:897` | test.skip() — Path A pivot |
| `RPG — XP` | XP backfill + recorded after first workout + no double-XP | COVERED | `rpg-foundation.spec.ts:136,244,339` | @smoke |
| `RPG — Class` | Class label updates after rank cross | COVERED | `saga.spec.ts:485` | — |
| `Offline` | Banner shows/hides + pending sync badge + sync sheet | COVERED | `offline-sync.spec.ts:610,637,212,401` | @smoke |
| `Auth redirect` | All 3 redirect paths (unauthed/post-login/post-logout) | COVERED | `auth.spec.ts` | @smoke |

---

### IMPORTANT

### finding-036 (D) — Onboarding full flow skips due to infrastructure gap

- Screen: `/onboarding` (`lib/features/auth/ui/onboarding_screen.dart`)
- Action / error path: All four onboarding tests self-skip when `smokeOnboarding` user already has a profile row (which happens on every run after the first)
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/onboarding.spec.ts` — fix is in `test/e2e/global-setup.ts` to DELETE the profile row for `smokeOnboarding` before each run, or freshly provision throwaway user per run
- Suggested test name: existing tests already named correctly
- Suggested user fixture: `smokeOnboarding` (existing) — global-setup must wipe profile row after creation
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-037 (D) — New-account sign-up happy path (full flow) not exercised

- Screen: `/login` → `/email-confirmation` or `/onboarding`
- Action / error path: Successful sign-up with a genuinely new email — button press, email confirmation handling, land on onboarding. Only duplicate-email error and UI toggle are tested.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/auth.spec.ts` (new describe block `Auth — sign-up happy path`)
- Suggested test name: `should create a new account and reach email confirmation screen`
- Suggested user fixture: Throwaway user (unique email per run); tear down in afterAll
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-038 (D) — Active workout banner tap (resume) not tested as isolated contract

- Screen: `/home` (shell `_ActiveWorkoutBanner`)
- Action / error path: While a workout is in progress, the active-banner appears in the bottom shell. Tapping it must navigate to `/workout/active`. Crash-recovery spec covers reload-restore (entering via Hive), but no test starts a workout, navigates to another tab, then asserts banner tap returns to active.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (new test in `Workout restore` describe block)
- Suggested test name: `should return to active workout when tapping the active banner from a different tab`
- Suggested user fixture: `smokeWorkoutRestore` (existing)
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-039 (D) — Workout detail screen content not fully asserted

- Screen: `/home/history/:id` (`lib/features/workouts/ui/workout_detail_screen.dart`)
- Action / error path: Detail screen shows a detail strip (XP + PR count) and exercise cards. Only one test navigates here (`workouts.spec.ts:731` WK-023) and asserts a single `text=22.5` value. Detail strip, exercise cards, PR-count display are unasserted.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (extend `Workout history` describe block)
- Suggested test name: `should render the detail strip with XP on the workout detail screen`, `should show exercise cards on the workout detail screen`
- Suggested user fixture: `fullHistory` (existing) — needs at least one seeded completed workout with XP
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-040 (D) — Empty-session guard sheet not exercised in E2E

- Screen: `/workout/active` → guard sheet before `/workout/finish/:workoutId`
- Action / error path: Tapping Finish with zero completed sets shows `emptySessionGuardSheet`. Coverage is only in widget/unit tests; the spec comment at `workouts.spec.ts:263` explicitly defers the E2E.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (new test in `Workouts` smoke describe block)
- Suggested test name: `should show empty-session guard sheet when finishing a workout with no completed sets`
- Suggested user fixture: `smokeWorkout` (existing)
- Severity: IMPORTANT
- Suggested home: PR 33c
- **Triage note:** the 32g PR description called this "platform-untestable on Flutter web (UI gate making EmptySessionGuard unreachable from the standard finish path)". Verify the path still gates before promoting to a fix vs. PARK.

### finding-041 (D) — Post-session CONTINUAR CTA → /home navigation not asserted

- Screen: `/workout/finish/:workoutId` (`post_session_screen.dart`)
- Action / error path: After cinematic, summary panel shows CONTINUAR button that calls `onContinue` → `context.go('/home')`. All post-session tests skip to summary; none taps CONTINUAR.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/post_session.spec.ts` (new test in `Post-session summary`)
- Suggested test name: `should navigate to home screen when CONTINUAR is tapped on the summary panel`
- Suggested user fixture: `rpgRankUpThreshold` (existing)
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-042 (D) — Post-session B3 PR cut not independently asserted

- Screen: `/workout/finish/:workoutId` — Beat 3 PR cut
- Action / error path: When a new PR is set, the B3 PR cut should render. `POST_SESSION.b3Pr` selector exists. Multi-event test covers B3 title + B3 class-change; no test asserts B3 PR cut for a PR-only workout.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/post_session.spec.ts` (new describe block or extend)
- Suggested test name: `should render the B3 PR cut when the finished workout contains a new personal record`
- Suggested user fixture: User seeded with a prior PR (lower weight); new user where first workout's set is guaranteed a PR
- Severity: IMPORTANT
- Suggested home: PR 33d

### finding-043 (D) — Exercise retirement (32h) has no E2E coverage

- Screen: `/exercises/:id` (`exercise_detail_screen.dart`)
- Action / error path: PR 32h introduced user-created exercise retirement. A retired exercise should be hidden from workout pickers. No E2E test verifies the retire action or downstream effects.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/exercises.spec.ts` (new describe block `Exercise retirement`)
- Suggested test name: `should hide a retired user-created exercise from the workout exercise picker`
- Suggested user fixture: New isolated user with a seeded user-created exercise (add to `test-users.ts` + `global-setup.ts`)
- Severity: IMPORTANT
- Suggested home: PR 33d

### finding-044 (D) — /records screen reachable only via hash navigation in tests

- Screen: `/records` (`pr_list_screen.dart`)
- Action / error path: In the app, `/records` is reached by tapping the Records stat row in `ProfileSettingsScreen`. Every E2E test reaches it via `window.location.hash = '#/records'`, bypassing the in-app navigation path.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/personal-records.spec.ts` (new test, or extend existing smoke)
- Suggested test name: `should navigate to the personal records screen when tapping the Records row in profile settings`
- Suggested user fixture: `smokePR` (existing) — navigate via gear icon → settings → tap Records stat row
- Severity: IMPORTANT
- Suggested home: PR 33c

### finding-045 (D) — Weight unit toggle (kg↔lbs) not tested in E2E

- Screen: `/profile/settings` (`profile_settings_screen.dart`)
- Action / error path: Weight unit row allows toggling between kg and lbs. `PROFILE.kgOption`/`PROFILE.lbsOption` selectors exist; no test taps them or asserts the unit persists across screens.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/profile.spec.ts` (new describe block `Profile — weight unit`)
- Suggested test name: `should persist weight unit selection across screens after toggling from kg to lbs`
- Suggested user fixture: New isolated user or `smokeProfileWeeklyGoal` (existing)
- Severity: IMPORTANT
- Suggested home: PR 33d

### finding-046 (D) — Week-complete review state not seeded; 4 tests permanently skip

- Screen: `/home` (WeekReviewSection / bucket chip row in week-complete state)
- Action / error path: When all bucket routines for the week are completed, home transitions to week-complete state. Four tests in `weekly-plan.spec.ts:458–521` cover this but `test.skip()` because `smokeWeeklyPlanReview` user is never seeded with completed weekly plan in `global-setup.ts`.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/weekly-plan.spec.ts` — unskip existing tests; fix is in `test/e2e/global-setup.ts` to seed completed weekly plan for `smokeWeeklyPlanReview`
- Suggested test name: existing names are correct
- Suggested user fixture: `smokeWeeklyPlanReview` (existing) — requires global-setup to insert a `weekly_plans` row with all workouts marked done for the current ISO week
- Severity: IMPORTANT
- Suggested home: PR 33c

---

### NICE-TO-HAVE

### finding-047 (D) — Email confirmation screen has zero E2E coverage

- Screen: `/email-confirmation` (`email_confirmation_screen.dart`)
- Action / error path: Screen renders with confirmation message; user sees prompt to check email after sign-up. No test reaches this route.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/auth.spec.ts` (new test in `Auth — edge cases`)
- Suggested test name: `should show email confirmation screen with check-your-email message after sign-up with new address`
- Suggested user fixture: Throwaway user (unique-email-per-run pattern)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33d

### finding-048 (D) — Legal screens (Privacy Policy, Terms of Service) have zero E2E coverage

- Screen: `/privacy-policy`, `/terms-of-service` (`legal_doc_screen.dart`)
- Action / error path: Screen renders correct document content; routes are public (reachable without auth). No spec navigates to either.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/auth.spec.ts` (add to smoke describe — unauthenticated surfaces)
- Suggested test name: `should render the privacy policy document at /privacy-policy`, `should render the terms of service document at /terms-of-service`
- Suggested user fixture: None required — public routes
- Severity: NICE-TO-HAVE
- Suggested home: PR 33d

### finding-049 (D) — History error state (Retry button) not tested

- Screen: `/home/history` (`workout_history_screen.dart`)
- Action / error path: When history load fails (network error), a Retry button renders. `HISTORY.retryButton` selector exists but no test exercises this path.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (add to `Workout history` describe, or new describe)
- Suggested test name: `should show retry button when history fails to load and reload list on tap`
- Suggested user fixture: `fullHistory` — use `page.route()` to return 500 on workouts RPC
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-050 (D) — History card PR diamond badge not asserted

- Screen: `/home/history` (workout history list cards)
- Action / error path: When a workout's `prCount > 0`, a diamond row renders on the card. `HISTORY.cardPrDiamond` selector exists; no test asserts its presence after a workout with a PR.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/history-localization.spec.ts` (`History redesign affordances`)
- Suggested test name: `should render PR diamond badge on history card for a workout that produced a personal record`
- Suggested user fixture: `fullHistoryPt` (verify global-setup seeds at least one with a PR) or `fullPR`
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-051 (D) — Exercise reorder toggle in active workout not promoted to regression spec

- Screen: `/workout/active` (`active_workout_screen.dart`)
- Action / error path: Reorder toggle (`workout-reorder-toggle`) appears only when workout has 2+ exercises. Tapping it enters reorder mode. Charter-C explored this but charter specs are opt-in.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (new describe `Exercise reorder toggle`)
- Suggested test name: `should show reorder toggle only when workout has 2+ exercises`, `should enter reorder mode when reorder toggle is tapped`
- Suggested user fixture: `fullWorkout` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-052 (D) — Workout notes field has no promoted E2E test

- Screen: `/workout/active` (notes field)
- Action / error path: `WORKOUT.notesInput` selector exists; only usage is inside `test.describe.skip` charter-d (manual env var). No promoted regression test pins notes field accepts input and persists through save.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/workouts.spec.ts` (add to `Workout logging`)
- Suggested test name: `should accept text input in the workout notes field`
- Suggested user fixture: `fullWorkout` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-053 (D) — Share preview export CTA never tapped in E2E

- Screen: `/workout/finish/:workoutId` → share preview screen
- Action / error path: `SHARE_FLOW.previewShareButton` is asserted visible but never tapped. On Flutter web, `share_plus` uses a web stub. Untested path means a silent regression in the share pipeline (e.g., `kIsWeb` guard missing) would not be caught.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/share_flow.spec.ts` (add new test to `Share flow`)
- Suggested test name: `should not crash and remain on preview screen or dismiss cleanly when share button is tapped on web`
- Suggested user fixture: `rpgRankUpThreshold` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-054 (D) — Routine exercise reorder in create/edit screen not tested

- Screen: `/routines/create` (`create_routine_screen.dart`)
- Action / error path: Exercises within a routine can be reordered via drag. No E2E test exercises drag-to-reorder in the routine builder.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/routines.spec.ts` (add to `Routine management`)
- Suggested test name: `should persist exercise order after reordering within the routine builder`
- Suggested user fixture: `smokeRoutineManagement` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-055 (D) — Overflow card tap → /profile is skipped (post-Path-A pivot note is stale)

- Screen: `/workout/finish/:workoutId` (post-session summary overflow card surface)
- Action / error path: `rank-up-celebration.spec.ts:897` `test.skip()` with comment "PR 30a will reintroduce the post-session screen overflow surface." PR 30a shipped in May 2026. Test has not been unskipped or re-evaluated.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/rank-up-celebration.spec.ts` (unskip and adapt)
- Suggested test name: `should route to /profile when the user taps the overflow card on the post-session summary`
- Suggested user fixture: `rpgOverflowTapCard` (existing — seeded for this exact scenario)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-056 (D) — Saga body-part row tap routing skip (26-tap-routing-e2e) still open

- Screen: `/profile` → `/saga/stats?body_part=<X>`
- Action / error path: `saga.spec.ts:591` `test.skip()` with `TODO(26-tap-routing-e2e)`. Per §2 Active Backlog, test was blocked on `expect(page).toHaveURL(...)` and `aria-selected="true"` not working for hash-routing navigation.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/saga.spec.ts` — unskip and replace URL assertion with content-visibility assertion (`SAGA.statsDeepDiveScreen` visible) per `flutter-web-url-assertion` cluster fix template
- Suggested test name: `should open stats deep-dive when a body-part row is tapped`
- Suggested user fixture: `rpgFoundationUser` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-057 (D) — PR empty-state condition test.skip

- Screen: `/records` — PR card renders after completing a set
- Action / error path: `personal-records.spec.ts:557` `test.skip()` with comment "TODO: Seed PR-eligible exercise data or fix save_workout RPC PR detection." Smoke-level check that a PR card appears after completing a qualifying set.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/personal-records.spec.ts` — unskip; seed the `smokePR` user with a prior PR baseline; OR rely on existing `fullPR` coverage at line 510 and PARK the smoke variant
- Suggested test name: existing name is correct
- Suggested user fixture: `smokePR` (existing); requires verifying global-setup correctly seeds a lower-baseline PR
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-058 (D) — Create new routine from within AddRoutinesSheet (weekly plan) not tested

- Screen: `/plan/week` → AddRoutinesSheet → Create new routine row
- Action / error path: `WEEKLY_PLAN.createNewRoutineRow` selector exists. Tapping it while add-routines sheet is open should push `/routines/create`. No E2E test exercises this.
- Status: MISSING
- Suggested test landing: `test/e2e/specs/weekly-plan.spec.ts` (add to `Weekly Plan` smoke describe)
- Suggested test name: `should open the routine creation screen when tapping Create new routine inside the add-routines sheet`
- Suggested user fixture: `smokeWeeklyPlan` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

### finding-059 (D) — Full auth journey verifies tabs but not Records screen

- Screen: `/records` + full shell tab coverage
- Action / error path: `auth.spec.ts:276` "full journey: login, navigate all tabs, logout" tests Home, Exercises, Routines, Profile tabs. The `/records` route (accessed via in-app navigation only) is not part of this journey.
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/auth.spec.ts` (extend full journey or add separate test)
- Suggested test name: `should reach personal records screen via profile settings records row`
- Suggested user fixture: `fullAuth` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33d

### finding-060 (D) — Crash recovery rapid double-tap Finish deduplication: PARTIAL behavioral assertion

- Screen: `/workout/active` → finish double-tap
- Action / error path: `crash-recovery.spec.ts:411` covers "should not create duplicate workouts on rapid double-tap of Finish." Currently COVERED but assertion only checks "no crash, no duplicate dialogs" without DB-level deduplication (single workout row).
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/crash-recovery.spec.ts` (extend existing test with DB-level count assertion via admin client)
- Suggested test name: existing test name is sufficient; add DB assertion
- Suggested user fixture: `fullCrash` (existing)
- Severity: NICE-TO-HAVE
- Suggested home: PR 33e

---

### PARK

### finding-061 (D) — ActionHero create-first-routine branch permanently skipped

- Screen: `/home` (ActionHero `_CreateFirstRoutineHero` branch)
- Action / error path: `home.spec.ts:448` `test.skip()` — deferred because default routines (Full Body, Push Day etc.) are global RLS rows visible to every user, making it impossible to put a test user into zero-routines state without a schema migration. Comment explicitly defers to a "per-user-default-hide migration."
- Status: PARTIAL
- Suggested test landing: `test/e2e/specs/home.spec.ts` — unskip if migration lands in Phase 33 or Launch Phase; otherwise add to §2 Active Backlog tracking
- Suggested test name: `should show create-first-routine ActionHero when user has zero routines`
- Suggested user fixture: New isolated user requiring per-user-default-hide schema change
- Severity: PARK
- Suggested home: PARK (depends on schema migration)

---

### Skipped-test cross-reference

| Skip marker | Spec file | Finding |
|---|---|---|
| Onboarding all 4 tests (profile row exists) | `onboarding.spec.ts:62,94,133,172` | finding-036 (D) |
| Week-complete review 4 tests (no seeded state) | `weekly-plan.spec.ts:468,484,500,521` | finding-046 (D) |
| Overflow card tap → /profile | `rank-up-celebration.spec.ts:897` | finding-055 (D) |
| Saga body-part row routing | `saga.spec.ts:591` | finding-056 (D) |
| PR empty-state card after completing set | `personal-records.spec.ts:557` | finding-057 (D) |
| ActionHero create-first-routine branch | `home.spec.ts:448` | finding-061 (D) |

## §E — Deletion candidates

**Counts:** 0 CRITICAL · 0 IMPORTANT · 4 NICE-TO-HAVE · 0 PARK (4 actionable findings + 1 verification-only entry). Total deletable LOC reported by agent: ~12 lines (RPE l10n keys × 2 locales + generated interface lines).

**Orchestrator caveat (cross-section gap):** A5's sweep underdelivered relative to its scope. The §E agent reported "no orphan files" in `lib/` but A1's `finding-004 (A)` flags `lib/features/rpg/ui/saga_stub_screen.dart` as an orphan widget at IMPORTANT. A5 also reports RPE l10n key counts (4 keys) and line numbers that differ from A1's `finding-003 (A)` (6 keys at line 1179). **Triage should treat A1's findings as canonical** for `SagaStubScreen` and RPE l10n keys; the §E entries below are kept for the sweep's coverage of the 4 retired features by source and the verification of the Phase 29.5 cleanup.

---

### NICE-TO-HAVE

### finding-062 (E) — Unused RPE l10n keys from Phase 25 drop

- File(s): `lib/l10n/app_en.arb` (lines 1280, 1287–1288, 1289–1290, 1291–1296) + `lib/l10n/app_pt.arb` (lines 503–506) + auto-generated `app_localizations*.dart` interface lines
- Reason it's dead: Phase 25 dropped RPE tracking on 2026-05-15 (per PROJECT.md §2). The `ExerciseSet.rpe` model field is intentionally preserved per v1.1-park note, but no UI widget references these l10n keys. Exhaustive grep across `lib/` + `test/` found zero call sites for `.rpeValue`, `.setRpe`, `.rpeLabel`, or `.rpeMenuItem`. **See also `finding-003 (A)` for an alternate count (6 keys at line 1179) — triage should reconcile the exact key list before deletion.**
- Recommended action: DELETE the 4 keys (per §E count) OR 6 keys (per §A count) from both `app_en.arb` and `app_pt.arb`; run `make gen` to regenerate; no test changes (no tests reference these keys).
- Severity: NICE-TO-HAVE (note: `finding-003 (A)` rates the same issue at IMPORTANT — use the higher severity)
- Suggested home: PR 33b

### finding-063 (E) — Comment-only residue from Phase 32h retirement (KEEP)

- File(s): `lib/core/offline/offline_queue_service.dart:116`, `lib/core/offline/sync_service.dart:210`, `lib/features/exercises/ui/exercise_list_screen.dart:564`, `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:1557–1559`, `lib/features/workouts/ui/widgets/exercise_picker_sheet.dart:159`
- Reason it's dead: Phase 32h (#281) cleanly retired `CreateExerciseScreen`, `/exercises/create` route, and `PendingCreateExercise` variant. Only residue is explanatory inline comments referencing the retirement. No code references, no orphan imports.
- Recommended action: KEEP — these comments document the architectural decision and are intentionally preserved per CLAUDE.md "Avoid backwards-compatibility hacks" (comments explain WHY code looks the way it does, not dead code).
- Severity: NICE-TO-HAVE
- Suggested home: PARK (keep as documentation)

### finding-064 (E) — Comment-only residue from Phase 30c retirement (KEEP)

- File(s): `lib/core/router/app_router.dart:153`, `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:402,436,440,546,553`, `lib/features/workouts/ui/coordinators/post_workout_navigator.dart:103`
- Reason it's dead: Phase 30c (#265) retired the legacy `/pr-celebration` route and `PrCelebrationScreen`. Only explanatory comments remain.
- Recommended action: KEEP — comments explain architectural lineage and routing decisions.
- Severity: NICE-TO-HAVE
- Suggested home: PARK (keep as documentation)

### finding-065 (E) — Phase 29.5 overlays retirement verification (DONE)

- File(s): (none remaining)
- Reason it's dead: Phase 29.5 (#255) retired 5 mid-workout overlay widgets: `rank_up_overlay.dart`, `level_up_overlay.dart`, `first_awakening_overlay.dart`, `title_unlock_sheet.dart`, `class_change_overlay.dart`. All files successfully deleted from `lib/`. No orphan imports, no test files importing deleted symbols, no test failures. E2E selectors properly updated in `test/e2e/helpers/selectors.ts` (comments document the Path A pivot at lines 1195–1208).
- Recommended action: NONE — cleanup verified complete; this entry is a record of verification, not an action item.
- Severity: N/A (verification only — not counted in severity buckets)
- Suggested home: N/A

### finding-066 (E) — Comment-only residue from Phase 29.5 pivot documentation (KEEP)

- File(s): `test/e2e/helpers/selectors.ts:1195–1208`, `lib/features/workouts/ui/coordinators/finish_workout_coordinator.dart:350`
- Reason it's dead: Path A pivot documentation explaining why mid-workout celebration overlays were removed. Comments provide architectural context for future agents.
- Recommended action: KEEP — preserve as architectural documentation.
- Severity: NICE-TO-HAVE
- Suggested home: PARK (keep as documentation)

---

### Cross-section summary (orchestrator)

A5's "no orphan files" conclusion is contradicted by A1's `finding-004 (A)` (orphan `saga_stub_screen.dart`). A5's "no orphan tests" / "no dead sealed-union arms" / "no stale CI scripts" conclusions are accepted without independent verification because A1's general code-review pass did not surface contradicting findings in those categories. Triage may choose to commission a narrower re-dispatch if the §B/§D/§A pipeline surfaces additional deletion candidates during fix-PR construction.
