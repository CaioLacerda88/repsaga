# Active Workout — Exploratory Findings (Master)

**Comprehensive exploratory pass per [`active-workout-exploratory-testplan.md`](active-workout-exploratory-testplan.md).** Six charters × strategic device matrix, agent-driven via Playwright MCP and code-level inspection.

| Charter | Persona | Device | Method | Bugs | UX |
|---|---|---|---|---|---|
| A — Brutal set-row | Sam | BR-1 (360×780) | MCP-driven | 6 | 6 |
| B — Interruption survival | Jordan | US-1 (393×852) | MCP-driven | 3 | 5 |
| C — Reorder + add + remove | Alex | BR-1 (360×780) | MCP-driven | 3 | 4 |
| D — Finish-flow router | Sam | US-1 (393×852) | MCP-driven | 4 | — |
| E — Offline / sync drain | Jordan | US-1 (393×852) | code analysis | 5 | — |
| F — A11y, visual scale, i18n | mixed | BR-1 (360×780) | code analysis | 10 | 3 |
| **Total** | | | | **31** | **18** |

**Resolved so far:** 13 / 31 bugs — Family 2 in PR #175 + Family 1A (BLOCKER) in PR #177 + Family 1B in PR #179 + Family 4 in PR #181 (1 real fix + 2 stale measurement findings) + Family 8 in PR #183 (1 stale measurement finding reclassified with regression guards) + Family 7 in PR #185 (postFrameCallback ordering race in finish flow).

Plus ~96 screenshots in `screenshots/` and 9 gated probe spec files in `test/e2e/specs/charter-*.spec.ts` (CI-safe — all guarded by env vars).

Per-charter detail in:
- [`charter-A-BR-1.md`](active-workout-findings/charter-A-BR-1.md) — set-row brutal probing
- [`charter-B-US-1.md`](active-workout-findings/charter-B-US-1.md) — interruption survival
- [`charter-C-BR-1.md`](active-workout-findings/charter-C-BR-1.md) — reorder/add/remove
- [`charter-D-US-1.md`](active-workout-findings/charter-D-US-1.md) — finish-flow router (1 BLOCKER)
- [`charter-E-US-1.md`](active-workout-findings/charter-E-US-1.md) — sync drain (code-confirmed)
- [`charter-F-BR-1.md`](active-workout-findings/charter-F-BR-1.md) — a11y / visual / i18n

---

## Executive summary

The active workout screen has **8 structural root-cause families** that surface as 31 individual bug reports. Fixing the families is far higher leverage than fixing each bug:

1. **Save-error classification gap** (BLOCKER family) — server errors, hangs, and true offline all collapse to one "queued" path. Includes the false-PR celebration BLOCKER.
2. **Rest-timer scrim modality** (MAJOR) — single-tap tap-through hits weight dialog AND exercise detail sheet. Code-confirmed: missing `AbsorbPointer`.
3. **A11y systematically missing** (MAJOR) — 7+ surfaces lack Semantics wrappers; some labels hardcoded English (also i18n).
4. **Tap targets below Material 48dp** (MINOR-MAJOR) — done-mark, Add Set, dialog actions all under min.
5. **Connectivity_plus relies on OS-level event** (MAJOR) — Flutter Web banner never fires; same-SSID reconnect / captive portal → no auto-drain.
6. **i18n leaks** (MAJOR-MINOR) — default workout name English in pt-BR; Semantics labels hardcoded; set-type abbreviations inconsistent across screens.
7. **Saga intro overlay intercepts PR celebration** (MAJOR) — race condition between intro presentation and post-finish navigation.
8. **Disabled-state visual ≠ actual handler** (MAJOR, needs-investigation) — Finish button looks 30% alpha disabled but Charter C found it tappable.

**Trust-impacting blocker:** AW-EX-D-US1-01 — the app celebrates fake PRs because the PR cache is empty at session start. A user who logs a workout 30kg×5 after a 50kg×8 baseline sees three "NEW PR" badges. Compounded by AW-EX-E-US1-03 (cache wipe on drain → fake PR risk re-armed).

**Architecture-impacting cluster:** the offline/sync error path conflates four different failure modes (network down, captive portal, server 5xx, validation 4xx) into a single "queued" state. User cannot tell when something is actually broken vs just slow. The drain logic itself relies on an OS-level event that doesn't reliably fire on Flutter Web.

---

## Root-cause families with proposed PR clusters

Severity scale: **B**locker / **M**ajor / **m**inor / **n**it. Effort estimate is for tech-lead time-to-PR-ready (excluding review).

### Family 1 — Save-error classification + PR cache integrity 🚨 BLOCKER — ✅ shipped (1A + 1B)

| ID | Severity | Charter | Symptom | Status |
|---|---|---|---|---|
| AW-EX-D-US1-01 | **B** | D | False PR celebration — empty in-memory cache + first-set-of-session-always-wins | ✅ resolved (PR #177, Family 1A) |
| AW-EX-E-US1-03 | M | E | `clearBox(prCache)` on drain → false-PR risk re-armed for next offline window | ✅ resolved (PR #177, Family 1A) |
| AW-EX-D-US1-03 | M | D | HTTP 500 silently queued as "offline"; user sees no error | ✅ resolved (PR #179, Family 1B) |
| AW-EX-D-US1-04 | M | D | No loading overlay when save hangs; ~2s timeout falls through to queue | ✅ resolved (PR #179, Family 1B) |
| AW-EX-E-US1-02 | M | E | Code-confirmed: single `catch (e)` in `finishWorkout`; `isTerminal()` not at enqueue | ✅ resolved (PR #179, Family 1B) |
| AW-EX-D-US1-02 | M | D | Real PR celebration missing post-finish | ✅ resolved (PR #185, Family 7) |

**Family 1A shipped (PR #177):**
- `prCacheBootstrapProvider` (new) seeds prCache from DB at session start AND on every auth transition (auth-reactive via `authStateProvider.future`).
- Eager warmup wired in `_ShellScaffold` next to the existing `rpgProgressProvider` listener.
- `sync_service._reconcilePrCache` replaced `clearBox(prCache)` with `ref.invalidate(prCacheBootstrapProvider)` — atomic re-seed instead of empty window.
- Reviewer caught a second amplifier path: `PRRepository.upsertRecords` was independently calling `clearBox` — also removed. Both wipe paths now closed.
- One-shot Hive migration (`pr_cache_v2_migrated` flag) wipes existing polluted entries on first launch post-fix.
- Per-exercise cache fallback in `getRecordsForExercises` (load-bearing scope addition not in original plan): the existing `exercises:<sortedSubsetIds>` key shape couldn't satisfy arbitrary workout subsets, so bootstrap alone would have been a no-op for in-session reads. Repo now chains `subset key → per-exercise keys → rethrow`.
- Tests: 8 bootstrap tests (incl. auth-reactivity contract) + 3 per-exercise cache fallback tests + 5 sync_service tests rewritten to the invalidate contract.

**Family 1B shipped (PR #179):**
- Hoisted `SyncErrorClassifier.isTerminal()` to the catch site in `finishWorkout`. Terminal (4xx, RLS, FK violation) → rethrow → `AsyncError` → existing snackbar plumbing surfaces them. Transient (offline, socket, timeout, 5xx) → keep enqueue path.
- Added explicit `.timeout(Duration(seconds: 30))` on `WorkoutRepository.saveWorkout`. The Charter D agent's "no loading overlay" observation was a side effect of the missing timeout — saves fell through to offline at ~2s, before the existing `ActiveWorkoutLoadingOverlay`'s 10s cancel-button reveal threshold. Post-fix, the overlay sticks for the full 30s with cancel revealed at 10s as designed.
- 5xx UX discriminator: `FinishWorkoutResult.serverErrorQueued` bool. Coordinator picks `workoutSavedServerError` snackbar copy ("Server error — saved offline, will retry") instead of plain `workoutSavedOffline`. Localized in en + pt.
- Classifier completion: `BaseRepository.mapException` wraps `supabase.PostgrestException` → `app.DatabaseException`, but pre-1B `SyncErrorClassifier` only matched the RAW Supabase shape — meaning the production catch site never produced a terminal verdict. Extended classifier additively to recognize `app.DatabaseException` / `app.NetworkException` / `app.TimeoutException` / `app.AuthException`. Drain loop in sync_service benefits transitively. Reviewer-suggested helper extraction also landed: `SyncErrorClassifier.httpCode(error)` now provides a single canonical code-extraction path used by both the classifier and the notifier 5xx discriminator.
- Tests: 10 catch-site classification + 5 widget overlay + 4 helper + 5 wrapped-type classifier (28 new total). Pinned the raw `dart:async` `TimeoutException → mapException → enqueue` integration chain end-to-end.

**AW-EX-D-US1-02 status:** medium-high confidence the bug dissolved post-1A. Charter D's primary cause was D-01's polluted PR cache; with bootstrap-seeded prCache, `prResult.hasNewRecords` is now correct → genuine PRs route to `/pr-celebration`. The secondary hypothesis (Saga intro navigation race while `_isFinishHandled=true`) is not fully ruled out by static analysis alone. Routed to Family 7 for a Playwright re-probe before final closure.

### Family 2 — Rest timer scrim modality (MAJOR, single-line fix) — ✅ RESOLVED in PR #175

| ID | Severity | Charter | Symptom | Status |
|---|---|---|---|---|
| AW-EX-A-BR1-04 | M | A | Plain tap on rest scrim opens exercise detail sheet underneath | ✅ resolved (PR #175) |
| AW-EX-B-US1-01 | M | B | Plain tap on rest scrim opens weight dialog underneath | ✅ resolved (PR #175) |
| AW-EX-F-BR1-05 | M | F | Code-level root cause: outer `GestureDetector` at `rest_timer_overlay.dart:49` had default `HitTestBehavior`, no opaque flag | ✅ resolved (PR #175) |

**Shipped:** added `behavior: HitTestBehavior.opaque` to the outer `GestureDetector`. Symmetric with the inner control-row detector. `AbsorbPointer` was rejected as overkill (noted in the original proposal here as a fallback — the impact analysis correctly determined opaque alone was sufficient). Regression guard: a structural pin in `rest_timer_overlay_test.dart` walks all `GestureDetector` instances in the overlay subtree and asserts each declares `HitTestBehavior.opaque` — fails pre-fix, passes post-fix.

### Family 3 — A11y semantic wrappers across active-workout surface (MAJOR)

| ID | Severity | Charter | Symptom |
|---|---|---|---|
| AW-EX-A-BR1-03 | M | A | Stepper +/− absent from AOM — tappable via coords only |
| AW-EX-A-BR1-05 | m | A | Set-type micro-labels (WK/WU/DR/FL) absent from AOM |
| AW-EX-B-US1-02 | M | B | Rest timer overlay missing AOM nodes (revised by F-06: control buttons present, countdown/scrim absent) |
| AW-EX-C-BR1-01 | m | C | Reorder toggle / exit-reorder buttons missing `flt-semantics-identifier` |
| AW-EX-C-BR1-02 | m | C | Swap / remove exercise buttons missing `flt-semantics-identifier` |
| AW-EX-F-BR1-01 | M | F | Code-level: WeightStepper / RepsStepper +/− have no `Semantics` wrapper |
| AW-EX-F-BR1-06 | M | F | Rest timer countdown not `aria-live`; dismiss GestureDetector unlabeled |

**Proposed PR cluster: `fix(workouts)/a11y-semantics-sweep`** — medium effort (~4h), multi-file
- `lib/shared/widgets/weight_stepper.dart`, `reps_stepper.dart` — wrap +/− `IconButton`s with `Semantics(button: true, label: l10n.weightIncrement)` etc.
- `lib/features/workouts/ui/widgets/set_row.dart` — wrap set-type micro-label with Semantics; expose set-row state in label ("Set 3, working, 100kg, 8 reps, completed, standing personal record").
- `lib/features/workouts/ui/widgets/rest_timer_overlay.dart` — countdown as `liveRegion: true`; dismiss GestureDetector with `Semantics(button: true, label: l10n.restTimerDismiss)`.
- `lib/features/workouts/ui/widgets/exercise_card.dart` — add `flt-semantics-identifier` to swap/remove/reorder buttons.
- `lib/features/workouts/ui/active_workout_app_bar_title.dart` — add reorder toggle identifier.
- Tests: widget tests asserting Semantics labels present; e2e selectors test confirming AOM nodes appear.

### Family 4 — Tap targets ≥ Material 48dp — ✅ RESOLVED in PR #181

| ID | Severity | Charter | Symptom | Status |
|---|---|---|---|---|
| AW-EX-A-BR1-01 | M | A | Done-mark 32×32 (PR #160 missed it) | ✅ resolved (PR #181) |
| AW-EX-A-BR1-02 | m | A | Add Set 40-tall (8dp short) | ✅ STALE — Charter A's Playwright `boundingBox()` measurement error; `tester.getSize` reports 300×48 dp pre-fix. Regression-guard test added (PR #181) |
| AW-EX-F-BR1-09 | m | F | Dialog `TextButton` actions at default 36dp | ✅ LARGELY STALE — Material 3's `MaterialTapTargetSize.padded` already inflates hit-test rects to 48dp. `dialogTextButtonStyle` shipped as defense-in-depth + regression guard (PR #181) |

**Family 4 shipped (PR #181):**
- **Real fix:** done-mark cell wrapped in outer `SizedBox(40, 48)` + `GestureDetector(behavior: HitTestBehavior.deferToChild, excludeFromSemantics: true)`. Visual ◆/✓ stays 32×32; only the hit-test box grows. Inner Semantics retains the `workout-set-done` / `workout-set-completed` AOM identifiers and tap action.
- **Defense-in-depth:** new shared `dialogTextButtonStyle` (`minimumSize: Size(64, 48)`) + `dialogFilledButtonStyle` companion in `lib/core/theme/dialog_button_style.dart`. Applied across the 5 active-workout dialogs (Finish, Discard, Weight stepper input, Reps stepper input, Remove exercise). The 48dp floor is now structural at each call site — robust to future theme-level `materialTapTargetSize: shrinkWrap` changes.
- **Tests:** 10 new widget tests using `tester.getSize` on a 360-wide viewport — 2 done-cell hit-area + 1 inner-visual-stays-32×32 + 1 Add Set regression guard + 4 dialog-action regression guards + 2 gesture-arena single-fire pins (Round 2) + 1 shrinkWrap-defense-in-depth pin (Round 2).
- **Methodology insight saved as memory:** future tap-target audits should verify with `tester.getSize` (the authoritative RenderBox measure), not Playwright `boundingBox()` or source `minimumSize` constants — both miss Flutter's `MaterialTapTargetSize.padded` inflation. Two of three Family 4 bugs were stale measurement errors.
- **Reviewer's gesture-arena double-fire claim** was empirically wrong (Flutter's `GestureArena.sweep` accepts only the first member when competing recognizers are pure `onTap`). The `deferToChild` flip is structural defense against future refactors that add competing non-tap recognizers, NOT a runtime bug fix today. Honestly framed in code comments.

**SnackBarAction (Undo)** deliberately untouched: no `style` param exposed, and Material default already gives ≥48dp via the same mechanism. Wrapping in a custom widget for parity not justified.

### Family 5 — Connectivity / sync drain on Flutter Web (MAJOR, architectural)

| ID | Severity | Charter | Symptom |
|---|---|---|---|
| AW-EX-B-US1-03 | M | B | Offline banner never fires on Flutter Web — `connectivity_plus` doesn't see CDP offline |
| AW-EX-E-US1-01 | M | E | Drain only triggers on OS-level event; captive portal recovery / same-SSID reconnect → no auto-drain |
| AW-EX-E-US1-04 | m | E | Fallback PR upsert with `dependsOn: []` — currently safe but fragile |
| AW-EX-E-US1-05 | m | E | Mid-drain connectivity flap splits drain into two passes — safe but subtle |

**Proposed PR cluster: `fix(core)/connectivity-web-and-drain-fallback`** — high effort (~8h)
- `lib/core/connectivity/connectivity_provider.dart` — supplement `connectivity_plus` with browser `online`/`offline` DOM events on web (kIsWeb branch); periodic health check on a Supabase endpoint as third signal.
- `lib/core/offline/sync_service.dart` — supplement OS-event drain trigger with a fetch-failure-feedback path (when a client request succeeds after recent failures, treat as connectivity recovery and drain).
- Tests: integration tests around the recovery branches; widget test for offline banner appearing on simulated web disconnect.

### Family 6 — i18n leaks (MAJOR-MINOR)

| ID | Severity | Charter | Symptom |
|---|---|---|---|
| AW-EX-F-BR1-02 | M | F | Default workout name hardcoded English (`"Workout — Wed May 7"` in pt-BR session) |
| AW-EX-F-BR1-03 | m | F | Stepper Semantics label English literal |
| AW-EX-F-BR1-04 | m | F | AppBar workout-name rename Semantics English literal |
| AW-EX-F-BR1-10 | m | F | Set-type abbreviations: active workout uses raw `WK/WU/DR/FL`; workout detail uses localized `N/AQ/D/F` |

**Proposed PR cluster: `fix(l10n)/active-workout-strings`** — medium effort (~3h)
- `lib/features/workouts/providers/notifiers/active_workout_notifier.dart:_generateWorkoutName()` — read locale, build name via localized prefix + `DateFormat('EEE MMM d', locale)`.
- Stepper / AppBar / set-type Semantics labels — route through `AppLocalizations`.
- Set-type abbreviation: pick canonical convention (the localized one is already populated; rip out the hardcoded `tinyAbbr`). Triage decision: which screen is "wrong"? Expectation is that BOTH screens show the SAME abbreviation per-locale.
- Tests: pt-BR locale golden / unit test for `_generateWorkoutName` returning `"Treino — Qua 7 mai"`.

### Family 7 — postFrameCallback ordering race in finish flow — ✅ RESOLVED in PR #185

| ID | Severity | Charter | Symptom | Status |
|---|---|---|---|---|
| AW-EX-D-US1-02 | M | D | Real PR celebration missing post-finish | ✅ resolved (PR #185) |

Original Charter D framing speculated this was a Saga intro race. Live re-probe (PR #185) showed the bug was a postFrameCallback ordering race in `FinishWorkoutCoordinator`: `_isFinishHandled = false` was released BEFORE `navigateAfterFinish` had a chance to push `/pr-celebration`, then `ActiveWorkoutScreen`'s own postFrameCallback fired AFTER `navigateAfterFinish`'s postFrame in the same frame and called `context.go('/home')` — last-write-wins on GoRouter clobbered the PR celebration route.

**Fix shipped (PR #185):** defer `_isFinishHandled = false` release across 2 frames via chained `addPostFrameCallback`. Flag stays `true` through frame N+1's full postFrame phase, releases at end of frame N+2 — by which time the active-workout screen has unmounted via the route change. Tests: 1 E2E regression (`personal-records.spec.ts:584`) + 1 unit reproducer (`active_workout_notifier_test.dart` AW-EX-D-US1-02 group, with `_StatefulFakeCache` JSON-encoding to mirror Hive).

**Why the data-flow hypotheses were wrong:** unit reproducer with real `PRDetectionService` PASSES — proving PR detection itself works correctly. Bug is in UI navigation choreography, not data flow.

### Family 8 — Disabled-state visual ≠ actual handler — ✅ STALE (PR #183)

| ID | Severity | Charter | Symptom | Status |
|---|---|---|---|---|
| AW-EX-C-BR1-03 | M | C | Finish button at 30% alpha but tappable with 0 completed sets | ✅ STALE — widget tests show `onPressed: null` correctly when no sets complete; tap doesn't open the dialog at the Flutter layer (PR #183) |
| AW-EX-F-BR1-07 | note | F | Code review: `FinishBottomBar:74` correctly uses `onPressed: enabled ? onPressed : null` | ✅ Confirmed correct — Family 8 investigation validated this conclusion |

**Family 8 shipped (PR #183) — investigation pass, NO production code changed:**
- TDD investigation: 3 widget tests pumping `ActiveWorkoutScreen` with various set-completion states. **All passed pre-fix.** The wiring at `finish_bottom_bar.dart:74` (`onPressed: enabled ? onPressed : null`) and `active_workout_screen.dart:271` (`enabled: _hasCompletedSet`) correctly produces `FilledButton.onPressed == null` when no sets are completed, and `tester.tap` does NOT open the FinishWorkoutDialog.
- Tests use Charter C's exact device viewport (360×780) for the disabled-side repros.
- Group doc-comment block documents the contract boundary explicitly: "the `enabled` flag MUST derive from live traversal of `state.exercises[*].sets[*].isCompleted` — any cached/persisted count field would be a regression." (Documented-but-not-CI-pinned for the Hive-deserialization boundary; future hardening opportunity.)
- **What Charter C likely saw:** the widget test rules out the Flutter-engine tap path. It does NOT rule out Playwright Web's `click()` synthesis behavior (focus + Enter on a button with non-null `onPressed`) or stale Hive-resumed completed-set state from the `fullWorkout` worker-scoped seed user (Charter C didn't verify `state.completedSetsCount == 0` before tapping). The Hive-resume hypothesis is the most plausible.
- 3 regression-guard tests + behavioral symmetry on the enabled side ensure the disabled-state contract stays load-bearing across future refactors.

### Family 9 — Web-specific edge cases (LOW priority)

| ID | Severity | Charter | Symptom |
|---|---|---|---|
| AW-EX-E-US1-F06 | n | E | Two-tab same user: both tabs share IndexedDB Hive box; concurrent drains could send same workout save twice. Server 409 → terminal classify. Low probability, web-only. |
| AW-EX-A-BR1-06 | n | A | Test-infra: hidden `<input>` proxy `inputValue()` always returns "" |

**Proposed action: defer.** Document, monitor in production via Sentry, revisit if observed.

---

## UX-improvement notes — route to ui-ux-critic for design direction

Not bugs; design questions that need a unified answer rather than ad-hoc fixes.

| ID | Charter | Surface | Issue |
|---|---|---|---|
| AW-UX-A-BR1-01 | A | Rest timer scrim near top | Tap-through near exercise-card area on small viewport (linked to Family 2) |
| AW-UX-A-BR1-02 | A | Set-type long-press cycle | No mid-hold visual feedback; undiscoverable on first use |
| AW-UX-A-BR1-03 | A | Done-mark 600ms lock | Silent — locked state looks identical to unlocked |
| AW-UX-A-BR1-04 | A | 360 viewport, single exercise | ~200px dead zone between set rows and Add-Exercise FAB |
| AW-UX-A-BR1-05 | A | Rest timer | "Tap anywhere to dismiss" instruction may sit below 780px fold |
| AW-UX-A-BR1-06 | A | All new exercises | Empty history → every set is gold pendingPredictedPr — trains users to ignore the gold signal |
| AW-UX-B-US1-{01-05} | B | Active workout banner / landscape / two-tab / finish dialog | Mostly POSITIVE observations — confirming areas that already work |
| AW-UX-C-BR1-{01-04} | C | Finish-button visual ambiguity / AOM-identifier UX cost / empty-state CTA confirmation | |
| AW-UX-F-BR1-01 | F | Workout-name English in pt-BR | Branding gap (linked to Family 6) |
| AW-UX-F-BR1-02 | F | pt-BR finish dialog at 360 width | Action buttons likely stack vertically due to longer pt-BR labels |
| AW-UX-F-BR1-03 | F | Workout-name rename | No keyboard affordance — `GestureDetector.onTap` only |

**Hidden-affordance question** (A-UX-02 + the deferred Charter A copy-last probe): set-number tap-to-copy, long-press setType cycle, long-press Add-Set fill — all undiscoverable. Sam noticed; Alex won't. Decision needed: surface via tooltip, micro-tutorial, or ditch the hidden gestures in favor of explicit menu options.

---

## Deferred — real-device only or out-of-scope this round

| Probe | Charter | Why deferred |
|---|---|---|
| Real multi-touch (2-finger tap, pinch, multi-swipe) | A | Playwright web cannot synthesize |
| Long-press on already-completed set (PR revert?) | A | Out of session timebox |
| Swipe-to-delete + Undo timing | A | Session state consumed |
| Wakelock under inactivity (real screen-off) | B | Real-device only |
| 3-finger Samsung accessibility shortcut | A/B | Real-device only |
| Reduced-motion emulation | F | MCP `page.emulateMedia` not exposed |
| Forced-colors emulation | F | MCP `page.emulateMedia` not exposed |
| Live AOM dump per PR row state | F | Browser context closed mid-Charter F (re-runnable via `EXPL_CHARTER_F=1` spec) |
| pt-BR locale screenshots | F | Browser context closed mid-Charter F |
| Live tap-target sweep at scale | F | Browser context closed mid-Charter F |
| Long-duration workout (>1h timer rollover) | (cross-cutting) | Out of timebox |
| DST transition mid-workout | (cross-cutting) | Real-device only |
| Browser zoom 200% layout | F | Browser context closed mid-Charter F |
| System font-size XL | F | Web equivalent doesn't reflect Android system setting |

The remaining browser-driven probes are **re-runnable**: each charter agent left a gated spec file in `test/e2e/specs/charter-*.spec.ts`. Setting the appropriate env var (e.g. `EXPL_CHARTER_F=1`) and `--headed` resumes from where the agent left off.

---

## Recommended PR ordering

By value-per-effort + risk dependency:

1. **PR1 — Family 2 (rest timer scrim modality)** — 30min, single file, kills 3 bug reports. Quickest win.
2. **PR2 — Family 1 (save-error classification + PR cache)** — 6h, BLOCKER, kills 6 bug reports including the trust-breaker. Highest priority despite the effort.
3. **PR3 — Family 4 (tap targets 48dp)** — 2h, Material compliance, kills 3 bug reports.
4. **PR4 — Family 3 (a11y semantics sweep)** — 4h, kills 7 bug reports, enables future visual-regression baselines.
5. **PR5 — Family 6 (i18n leaks)** — 3h, kills 4 bug reports.
6. **PR6 — Family 8 investigation → micro-PR** — 1-2h investigation, then patch.
7. **PR7 — Family 7 (Saga vs PR celebration)** — re-evaluate after PR2 ships; may dissolve.
8. **PR8 — Family 5 (connectivity Web fallback)** — 8h, architectural; save for last.

**Total estimated effort:** ~25-28h of tech-lead time across 8 PRs to ship the entire active-workout health pass. Roughly 2-3 weeks at one PR/cycle including review and QA.

---

## Open questions for triage

1. **PR cache architecture (Family 1):** seed-from-DB-on-session-start vs. lazy-load-on-first-detect? Trade-off: cold-start latency vs. correctness. Decision needed before PR2 starts.
2. **Set-type abbreviation canonical form (Family 6):** pt-BR `N/AQ/D/F` is already shipped on workout detail. Standardize active workout to match? Or rip the localized version and standardize on raw `WK/WU/DR/FL`? UX-critic question.
3. **Saga intro sequencing (Family 7):** does Saga intro genuinely belong after PR celebration, or before it? Product question.
4. **Connectivity fallback strategy (Family 5):** browser online/offline events alone, periodic health check, or both? Architectural choice.
5. **Hidden affordances (UX-A-02 cluster):** keep + add discoverability, or ditch? Product+UX choice.

---

_Generated 2026-05-07 from agent-driven exploratory pass. 1535 lines of detail in per-charter sub-files. ~96 baseline screenshots. 9 gated re-runnable probe specs._
