# Work In Progress

Active branch work. Each section is removed once the branch is merged. Empty
when no in-flight work exists — backlog and parked items live in `PLAN.md` →
`## Active Backlog` (single source of truth).

When starting a new task, follow CLAUDE.md → "WIP Tracking": write a checklist
here referencing the relevant `PLAN.md` step or backlog entry, check items off
as work lands, and remove the section after the merge condenses to PLAN.md.

---

## Active branch: `fix/core-connectivity-web` — Family 5A (Web connectivity)

Per `tasks/active-workout-implementation-plan.md` §302–§350. Bug AW-EX-B-US1-03
(offline banner never fires on Web — `connectivity_plus` doesn't see CDP
offline / browser-level disconnects).

**Triage decisions (settled before tech-lead dispatch):**
- **Conditional-import discriminator:** `dart.library.js_interop` (modern, Flutter 3.13+).
  Plan §328 mentions `dart.library.html` as legacy alternative — we use the
  modern one.
- **Web event API:** `package:web` (canonical `dart:html` successor). Add to
  pubspec dependencies; pin to a stable version compatible with `dart_sdk
  ^3.11.4`.
- **Debounce per source:** keep the existing 500ms debounce on the
  `connectivity_plus` adapter stream (legitimate flapping). For browser
  online/offline events, use a smaller (or zero) debounce — Chrome fires the
  event immediately on real disconnect, no flapping to absorb. Plan §329.
- **Stream merging:** native + browser sources both feed a single
  `StreamController<bool>` so `onlineStatusProvider` keeps its existing API
  (`StreamProvider<bool>` returning a debounced boolean).
- **Optimistic default of `true`:** preserved (plan §332). The cold-launch
  drain protocol depends on it.

**Files to touch:**
- `lib/core/connectivity/connectivity_provider.dart` — refactor to merge native
  + web sources via conditional-import platform interface.
- New: `lib/core/connectivity/web_online_events.dart` (web shim, exports
  `onWebOnlineStatusChange()` returning `Stream<bool>`).
- New: `lib/core/connectivity/web_online_events_io.dart` (native stub returning
  `Stream<bool>.empty()`).
- `pubspec.yaml` — add `web: ^x.y.z` dependency (verify SDK compat).

**Tests (TDD):**
- New: `test/unit/core/connectivity/connectivity_provider_web_test.dart` —
  use a fake stream injected via the platform-interface seam, assert the
  merged provider emits `false` on browser-offline event and `true` on
  browser-online event.
- New: `test/widget/shared/widgets/offline_banner_web_test.dart` — pump app
  shell with the same fake source; assert `OfflineBanner` becomes visible
  when fake fires offline. (Optional if covered by the unit test on the
  provider — confirm with tech-lead which level is most valuable.)
- Existing `test/unit/core/offline/sync_service_test.dart` and offline-sync
  E2E remain untouched in 5A; QA will overhaul the E2E spec post-merge.

**Acceptance criteria:**
- `make ci` clean (format + analyze + test + android-debug-build).
- Native build (Android) does NOT import `package:web`. Verified by
  android-debug-build step + grep on the bundled Dart classes.
- Web build (`flutter build web`) emits a bundle that subscribes to
  `window.online`/`window.offline` and pipes results into
  `onlineStatusProvider`.
- Existing native behavior preserved: `connectivity_plus` stream still
  drives `onlineStatusProvider` on Android/iOS.

**Pipeline tracking:**
- [x] Branch + WIP entry (Task #41)
- [x] Tech-lead implements 5A with TDD (Task #42)
- [x] CI verification + native-build sanity (Task #43) — full `make ci` green
  (format + gen + analyze + 2458 unit/widget tests + Android debug APK)
- [x] QA gate — E2E offline-sync rewrite (Task #44) — BLOCKED on prod bug
  - Added 5 widget-integration tests (offline_banner_integration_test.dart) — all pass
  - Updated offline-sync.spec.ts: removed stale "documented limitation" header
  - PROD-CODE BUG FOUND (root cause: NOT package:web): the OfflineBanner's
    Semantics(identifier: 'offline-banner') node was being culled by the
    Flutter Web semantics tree compactor because the home/exercises/etc. tab
    content registers `isBlockingSemanticsOfPreviouslyPaintedNodes` (typical
    sources: BlockSemantics, ModalBarrier, Drawer scrim) which propagates up
    to the `Expanded(child)` and drops every sibling semantics node painted
    before it. With the old `Column([if(!isOnline) OfflineBanner, Expanded(child)])`
    layout the banner painted BEFORE child and was therefore blocked.
    The package:web subscription, the merge logic in connectivity_provider,
    and the listener registration are all correct — diagnostic counters
    confirmed the Dart listener fires on `setOffline(true)` and the value
    propagates through `isOnlineProvider`.
- [x] Tech-lead: fix shell-level layout so OfflineBanner surfaces on web
  - Switched `_ShellScaffold.body` from `Column` to `Stack` so the banner
    paints AFTER the active tab content (no longer a "previous sibling")
  - Added `liveRegion: true` and a `label` to the banner Semantics for
    proper AT announcement semantics
  - All 9 offline-sync E2E pass (including OFFLINE-008/009); 115 @smoke pass;
    2463 unit/widget tests pass; analyzer clean
- [ ] Verify + PR + reviewer cycle (Task #45)
- [ ] Post-merge cleanup PR (Task #46)

---

## Resume context (post-compact pickup)

**Active-workout exploratory pass progress: 24 / 31 bugs shipped across 8 PR
pairs.**

| Family | PRs | Status |
|---|---|---|
| 2 — Rest scrim modality | #175, #176 | ✅ |
| 1A — PR cache bootstrap (BLOCKER) | #177, #178 | ✅ |
| 1B — Save-error classification | #179, #180 | ✅ |
| 4 — Tap targets 48dp | #181, #182 | ✅ |
| 8 — Finish-button disabled wiring (STALE) | #183, #184 | ✅ |
| 7 — postFrame race + offline contract | #185, #186 | ✅ (3-round arc) |
| 3 + 6 — A11y semantics + i18n leaks (combined) | #187, #188 | ✅ (11 bugs in one cycle) |

**What's left (single remaining family):**

**Family 5 — Connectivity / sync drain on Flutter Web.** 4 bugs. ~8h. High
risk (architectural; touches every offline-touching feature). Plan reference:
`tasks/active-workout-implementation-plan.md` §302.

Bugs:
- AW-EX-B-US1-03 (offline banner never fires on Web — `connectivity_plus`
  doesn't see CDP offline)
- AW-EX-E-US1-01 (drain only triggers on OS-level event; captive portal
  recovery / same-SSID reconnect → no auto-drain)
- AW-EX-E-US1-04 (fallback PR upsert with `dependsOn: []` — fragile)
- AW-EX-E-US1-05 (mid-drain connectivity flap splits drain into two passes)

Recommended split per plan §336:
- **PR 5A — Web-specific connectivity:** conditional import for `package:web`
  online/offline DOM events; merge into existing `connectivity_plus` stream;
  update `OfflineBanner` for web. Files: `lib/core/connectivity/
  connectivity_provider.dart` + a new web shim. Risk: conditional imports
  across native/web are brittle (`dart.library.html` discriminator —
  modern: `dart.library.js_interop`).
- **PR 5B — Drain reliability fallbacks:** `connectivityRecoveryProvider`
  heuristic (any successful repository call after a recent failure → drain
  signal, with 5s cooldown); periodic health check every 60s while queue
  non-empty (HEAD on Supabase health endpoint). Risk: feedback loops if
  recovery signal fires from a request that itself failed.

Sequencing: independent — 5A and 5B can ship in either order.

**Process pattern that has been working:**
- TDD discipline (failing-test-first) caught stale measurement findings in
  Families 4 and 8, surfaced architecture-level bugs in Families 1A and 7
- Reviewer agent has caught real bugs in every cycle (Family 3+6 caught a
  Critical warmup-abbr divergence + a Warning on `lookupAppLocalizations`
  fallback gap that the orchestrator and tech-lead both initially missed)
- Post-merge cleanup PRs admin-merge after fast checks (memory feedback —
  saves ~20 min per cycle vs waiting on e2e)
- All findings (Critical / Warning / Nit / Suggestion) addressed in same
  cycle per memory feedback — zero post-merge follow-ups

**Next dispatch when resuming:**
- Decide: 5A (web-specific connectivity) or 5B (drain reliability) first?
  Plan says they're independent. 5A is the more user-visible fix (offline
  banner on Web); 5B is the more architecturally interesting work.
- Create branch (`fix/core-connectivity-web` for 5A or `fix/core-drain-
  reliability` for 5B)
- Write WIP entry referencing the implementation plan section
- Dispatch tech-lead with TDD instructions; the conditional-import surface
  in 5A warrants extra caution — plan §356 flags brittle native/web build
  break risk
- Standard pipeline: tech-lead → CI → QA → PR → reviewer → merge → cleanup PR

---

_No work in flight._
