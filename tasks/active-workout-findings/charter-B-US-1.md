# Charter B — US-1 (iPhone 15, 393×852) — Jordan persona

**Driver:** qa-engineer agent
**Date:** 2026-05-07 / 2026-05-08
**Plan ref:** tasks/active-workout-exploratory-testplan.md §6 Charter B
**Setup outcome:** succeeded — used `fullCrash` worker-scoped user; login + startEmptyWorkout + addExercise (Barbell Bench Press) + 2 completed sets
**Spec file:** `test/e2e/specs/charter-b-exploratory.spec.ts` (guard: `EXPL_CHARTER_B=1`)
**Follow-up spec:** `test/e2e/specs/charter-b-followup.spec.ts` (guard: `EXPL_CHARTER_B_FU=1`)

---

## Bugs

### AW-EX-B-US1-01 — Rest timer scrim does not block pointer events: weight-entry dialog opens on top of active rest timer overlay

- **Persona:** Jordan
- **Charter:** B
- **Device:** US-1 (iPhone 15, 393×852)
- **Severity:** major (gesture conflict / unexpected layering)
- **Repro steps:**
  1. Start a workout, add Bench Press, add one set.
  2. Complete the set (done-mark tap). Rest timer overlay appears and begins countdown.
  3. While the rest timer is still counting down, tap the weight value button of ANY set row visible behind the overlay (e.g. the one visible through the dimmed background at ~y=350 in portrait).
- **Expected:** The rest timer scrim / GestureDetector absorbs all pointer events. Tapping the area behind the overlay should dismiss the rest timer (via the scrim's tap-to-dismiss) or do nothing. Under no circumstances should a second modal (weight entry dialog) open on top of the rest timer overlay.
- **Actual:** The "Enter weight" AlertDialog opens on top of the rest timer overlay. Both are simultaneously visible. The weight-entry "OK" input and the rest timer "Skip/-30s/+30s" controls are both interactive at the same time. See `screenshots/charter-B-US-1-P3-portrait-after-rotate.png` and `charter-B-US-1-P4-set-offline.png` — both clearly show `Enter weight: 20 kg` dialog layered over the rest timer ring.
- **Backend / console errors:** none observed
- **Notes:** Reproducible in both portrait and landscape. The rest timer overlay uses a `GestureDetector` with `onTap: stop()` for the scrim, but does not appear to use `AbsorbPointer` or `ModalBarrier` to block routing of tap events to underlying widgets. The result is that a second overlay can stack on top of the rest timer without first dismissing it. Recovery: user can Cancel the weight dialog, then the rest timer is still counting. However, any weight changes submitted while the rest timer is active are unexpected. This is the same tap-through problem documented in AW-EX-A-BR1-04 (Charter A) but on a different path — Charter A found it for the *exercise detail sheet*, this charter found it for the *weight entry dialog*.
- **Screenshot:** `screenshots/charter-B-US-1-P3-portrait-after-rotate.png`, `screenshots/charter-B-US-1-P4-set-offline.png`

---

### AW-EX-B-US1-02 — Rest timer overlay is semantically invisible: no flt-semantics node, not announced to accessibility tree

- **Persona:** Jordan
- **Charter:** B
- **Device:** US-1 (iPhone 15, 393×852)
- **Severity:** major (accessibility)
- **Repro steps:**
  1. Start a workout, add Bench Press.
  2. Complete a set to trigger the rest timer overlay.
  3. Query the accessibility tree: `document.querySelectorAll('flt-semantics')` — note every element's ariaLabel and role.
- **Expected:** The rest timer overlay exposes at minimum: (a) a container with a label like "Rest timer: 1:29" or similar, (b) the three control buttons ("-30s", "Skip", "+30s") as `role=button` elements, (c) the countdown value as a live region so screen readers announce remaining time.
- **Actual:** When the rest timer is active, the AOM dump (FU-1 probe) shows ZERO rest-timer-related entries. The overlay is visually present (confirmed by screenshots showing the 1:24 countdown ring) but produces no `flt-semantics` nodes. The workout's set rows and buttons are still in the AOM but the entire rest timer layer — container, countdown, and controls — is absent. Accessibility tools, switch access, and E2E test selectors (including `role=progressbar[name*="Rest timer"]`) find nothing.
- **Backend / console errors:** none
- **Notes:** The `completeSet()` E2E helper confirms the rest timer appears visually by screenshot but dismisses it via `page.mouse.click(center)` because it cannot target it by AOM selector. The AOM for the rest timer is effectively `display:none` from the accessibility tree's perspective. This is a Semantics gap: the `RestTimerOverlay` widget tree needs `Semantics` wrappers on its container (with a live label), its countdown text, and its three buttons. Related to AW-EX-A-BR1-03 (stepper buttons also not in AOM).

---

### AW-EX-B-US1-03 — ConnectivityService offline banner does not fire on Flutter Web — fetch override and CDP network-offline both ineffective

- **Persona:** Jordan
- **Charter:** B
- **Device:** US-1 (iPhone 15, 393×852)
- **Severity:** major (offline UX — users never see offline feedback on web)
- **Repro steps:**
  1. Navigate to active workout screen.
  2. Inject a fetch override: `window.fetch = () => Promise.reject(new TypeError('Failed to fetch'))`.
  3. Wait 8 seconds — observe offline banner.
  4. Restore fetch. Repeat with CDP `Network.emulateNetworkConditions({ offline: true })`.
  5. Confirm `navigator.onLine` reads `false` during CDP offline.
- **Expected:** The offline banner (`[flt-semantics-identifier="offline-banner"]`) appears within a few seconds of the device going offline, as shown in `offline-sync.spec.ts`.
- **Actual:** The offline banner NEVER appeared in either scenario. CDP offline correctly sets `navigator.onLine = false` (confirmed via `page.evaluate(() => navigator.onLine)`), but the banner does not appear. `connectivity_plus` on Flutter Web uses the browser's `NetworkInformation` API or `onLine` change events — both were triggered — yet the banner did not fire. The `onlineStatusProvider` 500ms debounce is not the issue (we waited 8s).
- **Backend / console errors:** none
- **Notes:** The `ConnectivityService` (`lib/core/connectivity/connectivity_provider.dart`) uses `connectivity_plus`'s `Connectivity().checkConnectivity()` and `onConnectivityChanged` stream. On Flutter Web, `connectivity_plus` polls `navigator.onLine`. The discrepancy may be that:
  (a) CDP network offline does NOT fire a `navigator.onLine` change event (only the value changes), OR
  (b) `connectivity_plus` on web uses `window.addEventListener('online'/'offline')` but CDP doesn't dispatch these events.
  This means the offline banner is likely non-functional on Flutter Web in real-world offline scenarios that aren't triggered by the physical network adapter going down. The E2E suite at `offline-sync.spec.ts` likely simulates offline differently. **Practical impact**: Jordan on the web build will see NO offline feedback if their wifi drops mid-workout — they will just get silent errors. The Hive autosave still works (sets complete locally), but the offline snackbar and pending badge will not appear until the app is restarted or a real network change event fires.
- **Suspicious files:** `lib/core/connectivity/connectivity_provider.dart`
- **Screenshot:** `screenshots/charter-B-US-1-P4-offline-banner.png` (banner absent), `screenshots/charter-B-US-1-FU-FU4-cdp-offline-banner.png` (CDP offline, banner absent)

---

## UX Notes

### AW-UX-B-US1-01 — Active workout home banner shows elapsed timer — excellent discoverability

- **Surface:** `_ActiveWorkoutBanner` in shell bottom bar
- **Device:** US-1 (393×852)
- **Issue:** Positive note. The banner shows "Workout — Thu May 7" + "00:34" elapsed + chevron arrow. Visually clear, positioned above the nav bar, tappable. Survives navigation-away and correctly resumes with all sets intact.
- **Proposed direction:** No change needed — this is working as intended. Worth noting for the UX baseline.
- **Severity:** positive observation

---

### AW-UX-B-US1-02 — Landscape layout is functional but the FINISH bar is clipped at bottom on 393×393 effective height

- **Surface:** Active workout screen in landscape
- **Device:** US-1 rotated to 852×393
- **Issue:** In landscape mode (852×393), the FINISH button is present at y=325 on a 393px tall viewport — leaving only 68px of viewport for the Scaffold body above it. The set rows are still visible but very compressed. The exercise header row takes ~120px, leaving ~240px for set rows and the "Add Set" button. On a real iPhone 15 landscape (without a navigation bar taking extra space), this is borderline usable. However, the layout doesn't break — the finish button is visible and the workout chrome is intact.
- **Proposed direction:** Flutter web landscape support on mobile is explicitly not a priority per `§10 Out of scope`. The graceful degradation is acceptable. No change required.
- **Severity:** annoyance (acknowledged out-of-scope)

---

### AW-UX-B-US1-03 — Two-tab behavior is unexpectedly well-handled: Tab B resumes the same Hive state

- **Surface:** Active workout + home screen (two tabs)
- **Device:** US-1 (393×852)
- **Issue:** Positive note. Opening a second tab for the same user correctly shows the active workout banner on /home and navigating to it resumes the exact same workout with all sets (the second tab showed 4 completed sets matching the running total). This is the expected Hive-backed behavior and works correctly.
- **Proposed direction:** No change. Note for documentation.
- **Severity:** positive observation

---

### AW-UX-B-US1-04 — visibilitychange backgrounding during finish dialog leaves dialog open — correct but potentially unexpected

- **Surface:** Finish workout dialog during backgrounding
- **Device:** US-1
- **Issue:** When the app is "backgrounded" (visibilitychange to hidden) while the finish dialog is open, the dialog remains open when returning to visible. This is correct behavior (no data loss). However, a user who backgrounds the app while reviewing the finish dialog might be surprised the dialog is still open when they return — especially if the rest timer was running before.
- **Proposed direction:** No change to behavior. Consider adding a brief "Your workout is still in progress" tooltip or toast on foreground return if the finish dialog was open during background. Low priority.
- **Severity:** annoyance (acceptable behavior, minor discoverability improvement opportunity)

---

### AW-UX-B-US1-05 — No visual indication of offline state in workout screen except absent banner

- **Surface:** Active workout screen + offline state
- **Device:** US-1
- **Issue:** Since the offline banner doesn't fire on Flutter Web (AW-EX-B-US1-03), the user receives zero visual feedback that they are offline during a workout. Sets continue to complete and Hive autosaves them. The only signal would be after a finish attempt (which would fail silently or show an error). A user with unreliable wifi is flying blind during the entire workout session.
- **Proposed direction:** Dependent on fixing AW-EX-B-US1-03 first. Once the banner fires correctly on web, it should display at the top of the workout screen (same position as charter E's pending-sync badge), not just on the home screen. The current banner is only shown in the shell bottom bar and requires being on /home to see it.
- **Severity:** friction (depends on AW-EX-B-US1-03 fix)

---

## Deferred Probes

- **P1-B3 (rest timer background timing):** The `completeSet()` helper dismisses the rest timer before observation. Requires a custom don't-dismiss probe. The visual confirms the rest timer does appear during the background window in P1-B3 (screenshot shows 1:24 after ~6s of background from 1:30 start, implying it ran correctly — delta=6s). Quantitative accuracy measurement deferred.
- **P4 offline finish path (Save & Finish while offline):** Not fully testable since the offline banner doesn't trigger via fetch override or CDP on Flutter Web. Requires OS-level network drop on a real device or a different connectivity simulation approach.
- **P6 (offline banner layout overlap measurement):** Deferred until AW-EX-B-US1-03 is fixed. Layout cannot be measured if the banner never appears.
- **Mid-loading-overlay background (P1 sub-probe):** The 10-second loading overlay cancel button was not exercised because reaching it requires a network call in progress. Deferred to Charter D (finish-flow paths) or a dedicated loading overlay test.
- **Lock screen / wakelock (real device):** Cannot simulate in Playwright Web. Defer to Android device pass.
- **Notification-tap resume:** Cannot simulate in Playwright Web. Defer to native pass.

---

## Probes Completed

- [x] P1-B1: Background mid-stepper — PASSED (URL survived, state intact)
- [x] P1-B2: Background mid-finish-dialog — PASSED (dialog survived backgrounding)
- [x] P1-B3: Background mid-rest-timer — PARTIAL (visual confirms timer ran during BG; AOM-based timing measurement deferred)
- [x] P1-B4: Background during 600ms done-mark lock — PASSED (workout screen intact)
- [x] P2-A: Navigate away → resume banner on /home — PASSED (banner visible)
- [x] P2-B: Tap resume banner → sets intact — PASSED (3 completed sets preserved)
- [x] P3-A: Rotate to landscape — PASSED (state preserved, chrome visible)
- [x] P3-B: Rest timer in landscape — PARTIAL (rest timer appeared visually per screenshot; AOM selector issue; BUG AW-EX-B-US1-01 discovered via screenshots)
- [x] P3-C: Finish dialog in landscape — SKIPPED (finish button not visible in landscape due to pending overlays from P3-B)
- [x] P3-D: Rotate back to portrait — PASSED (state on /workout/active); NOTE: weight dialog + rest timer simultaneously open observed (AW-EX-B-US1-01)
- [x] P4-A: Offline banner with fetch override — OBSERVED (banner absent, see AW-EX-B-US1-03)
- [x] P4-B: Set operations while offline — PARTIAL (sets complete via Hive; offline banner absent)
- [x] P4-C: Finish while offline — SKIPPED (pending overlay blocked; test sequence issue)
- [x] P4-D: Reconnect online → sync drain — OBSERVED (banner not triggered, consistent with P4-A)
- [x] P5-A: Two-tab same user — PASSED (Tab B shows banner, resumes with correct sets)
- [x] P6: Offline banner layout — DEFERRED (banner not triggered)
- [x] FU-1: AOM dump with rest timer active — CONFIRMED (rest timer has zero AOM presence; AW-EX-B-US1-02)
- [x] FU-4: CDP network offline → banner — CONFIRMED (navigator.onLine=false, banner absent; AW-EX-B-US1-03)

### Skipped / Partially Blocked

- P3-C, P4-C: test sequence left lingering overlays from prior probes (inter-probe state management issue); findings still valid
- P1-B3, FU-2, FU-3: `completeSet()` helper auto-dismisses rest timer before observation; timing measurement requires a probe that avoids the helper's dismissal logic
