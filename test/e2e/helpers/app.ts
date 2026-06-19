/**
 * App-level helpers: launch, readiness checks, and navigation.
 *
 * The Flutter app is served automatically by Playwright's webServer config
 * during local dev (port 4200 by default). In CI the FLUTTER_APP_URL env var
 * is set by the workflow and Playwright connects to the pre-running server.
 *
 * To start the server manually for debugging:
 *   flutter build web
 *   npx serve -s build/web -l 4200
 *
 * OR during active development (with hot-reload):
 *   flutter run -d chrome --web-port 4200
 */

import { Page, expect } from '@playwright/test';
import { GAMIFICATION, NAV, PROFILE, SAGA } from './selectors';

/**
 * Wait for the Flutter app to finish its initial load.
 *
 * Flutter web (CanvasKit) renders to <canvas> and does NOT enable the
 * accessibility/semantics tree by default. It shows a hidden
 * "Enable accessibility" placeholder button instead. We must activate it
 * so that flt-semantics elements are generated for Playwright to interact with.
 *
 * After enabling semantics and waiting for auth to resolve, the router
 * redirects to /login, /home, or /onboarding.
 *
 * Timeout is generous (60s) to accommodate CanvasKit WASM download.
 */
export async function waitForAppReady(page: Page): Promise<void> {
  // Collect console errors for diagnostics if the app hangs.
  const consoleErrors: string[] = [];
  page.on('console', (msg) => {
    if (msg.type() === 'error') {
      consoleErrors.push(`[console.error] ${msg.text()}`);
    }
  });
  page.on('pageerror', (err) => {
    consoleErrors.push(`[page error] ${String(err)}`);
  });

  // 1. Wait for Flutter to render. With --force-renderer-accessibility in the
  //    Playwright launch args, Chrome exposes its accessibility tree and Flutter
  //    auto-enables semantics. We wait for either the placeholder OR any
  //    flt-semantics element (the latter appears when semantics are already on).
  try {
    await page.waitForSelector(
      'flt-semantics-placeholder, flt-semantics',
      { timeout: 60_000 },
    );
  } catch (e) {
    let bodyText = '';
    try {
      bodyText = await page.evaluate(() => document.body?.innerText ?? '');
    } catch {
      // Page already closed — diagnostics unavailable.
    }
    throw new Error(
      `Flutter app failed to render. ` +
        `Body text: "${bodyText.slice(0, 500)}". ` +
        `Console errors: ${JSON.stringify(consoleErrors)}`,
    );
  }

  // 2. Ensure the semantics tree is enabled. With --force-renderer-accessibility,
  //    Flutter usually enables semantics automatically. If not yet active, we
  //    fall back to clicking the placeholder and pressing Tab. Retry up to 3
  //    times to handle timing races during engine initialisation.
  for (let attempt = 0; attempt < 3; attempt++) {
    const semanticsCount = await page.locator('flt-semantics').count();
    if (semanticsCount > 0) break;

    // Fallback: manually trigger semantics via placeholder click + Tab.
    const placeholder = page.locator(
      'flt-semantics-placeholder[aria-label="Enable accessibility"]',
    );
    await placeholder.click({ force: true, timeout: 5_000 }).catch(() => {});
    await page.keyboard.press('Tab');

    // Also try dispatching a pointer event via JS as a last resort — the
    // placeholder may be inside shadow DOM where Playwright's click doesn't
    // trigger Flutter's event handler.
    await page.evaluate(() => {
      const el =
        document.querySelector('flt-semantics-placeholder') ??
        document
          .querySelector('flutter-view')
          ?.shadowRoot?.querySelector('flt-semantics-placeholder');
      if (el) {
        el.dispatchEvent(new PointerEvent('pointerdown', { bubbles: true }));
        el.dispatchEvent(new PointerEvent('pointerup', { bubbles: true }));
      }
    });

    await page.waitForTimeout(attempt < 2 ? 2000 : 500);
  }

  // 3. Wait for the router to navigate away from the splash screen.
  //    With the synchronous auth init, the router resolves immediately:
  //    no session → /login, active session → /home, new user → /onboarding,
  //    active workout in Hive → /workout/active.
  //
  //    We use URL-based detection because it's reliable regardless of whether
  //    flt-semantics elements are in light DOM or shadow DOM.
  try {
    await page.waitForURL(
      /\/(login|home|onboarding|workout|exercises|routines|profile|records)/,
      { timeout: 30_000 },
    );
  } catch (e) {
    // Dump diagnostics: what's actually on screen + any console errors.
    const currentUrl = page.url();
    let snapshot = '';
    try {
      snapshot = await page.evaluate(() => {
        // Check both light DOM and shadow DOM for flt-semantics elements.
        // Flutter 3.41.6+ uses AOM — accessible names are set via the
        // ariaLabel JS property, not as a DOM attribute. Try both.
        const getLabel = (el: Element) =>
          (el as any).ariaLabel ?? el.getAttribute('aria-label') ?? '';
        const lightEls = document.querySelectorAll('flt-semantics');
        const labels = Array.from(lightEls)
          .map(getLabel)
          .filter(Boolean);

        // Also check inside flutter-view shadow root.
        const flutterView = document.querySelector('flutter-view');
        if (flutterView?.shadowRoot) {
          const shadowEls = flutterView.shadowRoot.querySelectorAll('flt-semantics');
          labels.push(
            ...Array.from(shadowEls)
              .map(getLabel)
              .filter(Boolean),
          );
        }

        return labels.join(', ');
      });
    } catch {
      // Page already closed — diagnostics unavailable.
    }
    throw new Error(
      `App stuck on splash — router did not navigate away. ` +
        `URL: ${currentUrl}. ` +
        `Visible semantics: [${snapshot}]. ` +
        `Console errors: ${JSON.stringify(consoleErrors)}`,
    );
  }

  // 4. Wait for the destination screen to populate its semantics tree.
  await page.locator('flt-semantics').first().waitFor({ state: 'visible', timeout: 5_000 });
}

/**
 * Navigate to a bottom navigation tab by its label.
 *
 * Tabs: 'Home' | 'Exercises' | 'Routines' | 'Profile'
 *
 * The NavigationBar destinations emit aria-label via Flutter Semantics, so we
 * target them with the selector map in NAV.
 */
export async function navigateToTab(
  page: Page,
  tabName: 'Home' | 'Exercises' | 'Routines' | 'Profile',
): Promise<void> {
  const selectorMap: Record<string, string> = {
    Home: NAV.homeTab,
    Exercises: NAV.exercisesTab,
    Routines: NAV.routinesTab,
    Profile: NAV.profileTab,
  };

  // URL segment for each tab — used to detect navigation completion.
  const urlSegmentMap: Record<string, string> = {
    Home: 'home',
    Exercises: 'exercises',
    Routines: 'routines',
    Profile: 'profile',
  };

  const selector = selectorMap[tabName];
  await page.click(selector);

  // Wait for the URL to contain the tab's route segment. This is more reliable
  // than waiting for `text=${tabName}` because `text=` matches visible text node
  // content, not aria-label attributes (which is what the nav tabs use).
  await page.waitForURL(`**/${urlSegmentMap[tabName]}**`, { timeout: 15_000 });

  // Wait for destination screen semantics tree to populate.
  await page.locator('flt-semantics').first().waitFor({ state: 'visible', timeout: 5_000 });
}

/**
 * Fill a Flutter text field via CanvasKit semantics.
 *
 * Flutter CanvasKit renders to <canvas> — the flt-semantics elements are
 * accessibility overlays (divs), not real <input> elements. Flutter uses a
 * single shared native <input> proxy for text editing. When focus moves
 * between TextFields, values set via Playwright's fill() on this proxy are
 * lost because Flutter doesn't commit the value back to its internal
 * TextEditingController on the focus transition.
 *
 * Instead we click the semantics node to focus the TextField, then use
 * page.keyboard to send real key events at the window level. Flutter
 * captures these and routes them to the focused text field, bypassing the
 * native input proxy entirely.
 */
export async function flutterFill(
  page: Page,
  selector: string,
  value: string,
): Promise<void> {
  // Click the semantics element to focus the Flutter TextField.
  // Flutter 3.41.6 exposes a hidden native <input> proxy with role=textbox,
  // which may match the selector. Using .last() targets the visible semantics
  // overlay (rendered after the proxy in DOM order) rather than the invisible proxy.
  await page.locator(selector).last().click({ timeout: 15_000 });

  // Wait for Flutter's native <input> proxy to appear — this confirms the
  // text editing connection is established and the field is ready for input.
  const input = page.locator('input').last();
  await input.waitFor({ state: 'attached', timeout: 5_000 });
  await page.waitForTimeout(200);

  // Select all existing content (if any) so typing replaces it.
  await page.keyboard.press('Control+a');

  if (value === '') {
    // Clear the field by deleting the selection.
    await page.keyboard.press('Backspace');
  } else {
    // Type the value using real key events — the browser routes these to the
    // focused native <input>, which fires real input events that Flutter
    // processes correctly (unlike fill() which uses synthetic events).
    await page.keyboard.type(value, { delay: 10 });
  }
}

/**
 * Fill a Flutter search/filter text field that may not receive focus from a
 * semantics-node click alone.
 *
 * Some Flutter text fields (notably the exercise search bar) have their
 * underlying HTML <input> element positioned such that clicking the flt-semantics
 * overlay does not reliably transfer focus to the input. This helper targets the
 * underlying <input> element directly using an aria-label substring match.
 *
 * @param page     - Playwright page.
 * @param ariaHint - Substring of the <input aria-label> attribute used to find
 *                   the correct input element (e.g., "Search exercises").
 * @param value    - Text to type.
 */
export async function flutterFillByInput(
  page: Page,
  ariaHint: string,
  value: string,
): Promise<void> {
  const inputEl = page.locator(`input[aria-label*="${ariaHint}"]`);
  await inputEl.waitFor({ state: 'attached', timeout: 5_000 });
  await inputEl.focus();
  await page.waitForTimeout(200);
  await page.keyboard.press('Control+a');
  await page.keyboard.type(value, { delay: 10 });
}

/**
 * Change the active app locale via the Profile → Language sheet.
 *
 * Assumes the user is already logged in and the Profile tab is reachable via
 * the bottom navigation. The helper:
 *   1. Navigates to Profile tab (no-op if already there).
 *   2. Scrolls to / taps the Language row to open LanguagePickerSheet.
 *   3. Taps the option matching `locale`.
 *   4. Waits for the sheet to dismiss.
 *
 * The app persists the locale to Hive and (for logged-in users) Supabase, so
 * the new locale survives page reloads and sign-outs. Callers typically want
 * to reload the page after calling this so deeply-cached widgets rebuild.
 *
 * @param page   - Playwright page.
 * @param locale - Target locale: 'en' for English, 'pt' for Portuguese (Brasil).
 */
export async function setLocale(
  page: Page,
  locale: 'en' | 'pt',
): Promise<void> {
  // Phase 18b: /profile now shows CharacterSheetScreen; the language row is on
  // /profile/settings (ProfileSettingsScreen). Navigate to the Saga tab first,
  // then open settings via the gear icon before tapping the language row.
  await navigateToTab(page, 'Profile');
  await page.locator(SAGA.characterSheet).first().waitFor({ state: 'visible', timeout: 15_000 });
  await page.locator(SAGA.gearIcon).first().click();
  await page.locator(SAGA.profileSettingsScreen).first().waitFor({ state: 'visible', timeout: 10_000 });

  // Open the language picker sheet.
  await page.locator(PROFILE.languageRow).first().click({ timeout: 15_000 });
  await page
    .locator(PROFILE.languagePickerSheet)
    .first()
    .waitFor({ state: 'visible', timeout: 10_000 });

  // Tap the target locale option.
  await page
    .locator(PROFILE.languageOption(locale))
    .first()
    .click({ timeout: 10_000 });

  // Wait for the sheet to dismiss. The sheet is detached from the DOM when
  // Navigator.pop() fires, so we wait for its root semantics node to go away.
  await page
    .locator(PROFILE.languagePickerSheet)
    .first()
    .waitFor({ state: 'detached', timeout: 10_000 });
}

/**
 * Walk the SagaIntroOverlay through its three steps and dismiss it.
 *
 * The overlay appears on first home load for users who haven't yet seen it
 * (gated by Hive `saga_intro_seen` flag). This helper mirrors the real user
 * flow: wait for step 0 → NEXT → step 1 → NEXT → step 2 → BEGIN → gone.
 *
 * Extracted so gamification specs don't duplicate the sequence. The
 * timeouts match the original inline flow — the initial 20s wait
 * accommodates retro_backfill_xp resolving on first login.
 */
export async function dismissSagaIntroOverlay(page: Page): Promise<void> {
  await expect(page.locator(GAMIFICATION.step0)).toBeVisible({
    timeout: 20_000,
  });
  await page.locator(GAMIFICATION.nextButton).click();
  await expect(page.locator(GAMIFICATION.step1)).toBeVisible({
    timeout: 5_000,
  });
  await page.locator(GAMIFICATION.nextButton).click();
  await expect(page.locator(GAMIFICATION.step2)).toBeVisible({
    timeout: 5_000,
  });
  await page.locator(GAMIFICATION.beginButton).click();
  await expect(page.locator(GAMIFICATION.step0)).not.toBeVisible({
    timeout: 5_000,
  });
}

/**
 * Drive the post-session cinematic to its CONTINUAR CTA after a workout
 * finish — the canonical post-finish destination for online + non-empty
 * sessions.
 *
 * **Path A pivot (PR 29.5, 2026-05-22) + PR 30 retirement:** the
 * mid-workout flash layer is gone; the legacy `/pr-celebration` route was
 * retired in PR 30c. Every online finish with at least one logged set
 * routes through `/workout/finish/:workoutId` (the cinematic), which
 * renders the PR confirmation in the B3 PR cut + summary panel detail
 * row. Offline / zero-set finishes still land directly on `/home`.
 *
 * The function is kept (rather than deleted) because ~40 spec call sites
 * already invoke it after `finishWorkout()`; the helper short-circuits
 * cleanly when the cinematic doesn't fire (offline / zero-set finishes
 * skip straight to `/home`).
 *
 * @param page    - Playwright page.
 * @param timeout - How long to wait for the cinematic URL (ms). Default 20 s.
 */
export async function dismissCelebrationIfPresent(
  page: Page,
  timeout = 20_000,
): Promise<void> {
  // Wait for the post-session route (or short-circuit on offline / zero-set
  // finishes that go straight to /home).
  const cinematic = await page
    .waitForURL(/\/workout\/finish\//, { timeout })
    .then(() => true)
    .catch(() => false);

  if (!cinematic) return;

  // Tap the SKIP pill (post-session-skip-btn) to call skipToSummary()
  // directly, then tap the CONTINUAR CTA.
  //
  // The previous implementation used flutterLongPress(screenRoot, 600) which
  // was flaky under workers=4 CPU contention: the long-press would land but
  // the 8 s window for the CTA to appear was too tight when CanvasKit widget
  // rebuild + AOM re-emit took longer than expected. The skip button is
  // composited as a direct GestureDetector tap — no animation timer involved —
  // so it's both faster and more deterministic than the long-press path.
  const skipBtn = '[flt-semantics-identifier="post-session-skip-btn"]';
  const continueCta = '[flt-semantics-identifier="post-session-continue-cta"]';
  const summaryEl = page.locator(continueCta);
  // Wait for the skip button to be present (it renders immediately on
  // the cinematic; if the screen already jumped to summary it won't be
  // there, which is fine — the catch falls through).
  try {
    await expect(page.locator(skipBtn)).toBeVisible({ timeout: 8_000 });
    await page.click(skipBtn);
  } catch {
    // Skip button gone — screen already transitioned to summary panel.
    // Fall through and wait for CONTINUAR directly.
  }
  await expect(summaryEl).toBeVisible({ timeout: 15_000 });
  await page.click(continueCta);
  await page.waitForURL(/\/(home|profile)/, { timeout: 15_000 });
}

/**
 * Simulate a long-press on a Flutter element.
 *
 * Flutter CanvasKit routes semantics `click()` directly to `SemanticsAction.tap`,
 * bypassing the GestureDetector long-press timer. To trigger `onLongPress`, we
 * must send raw pointer events that satisfy Flutter's
 * `LongPressGestureRecognizer` arena rules:
 *   1. `pointerdown` lands inside the target widget.
 *   2. The pointer stays put (within `kTouchSlop` ≈ 18 logical px) for at least
 *      `kLongPressTimeout` (500 ms by default).
 *   3. `pointerup` fires AFTER step 2 completes.
 *
 * Historical flake (FLAKY_TESTS #routines-edit / #routines-delete): the previous
 * `hover() → mouse.down() → waitForTimeout → mouse.up()` pattern fired `onTap`
 * instead of `onLongPress` ~10 % of the time. Failure screenshots showed the
 * routine had been STARTED (active workout screen) — i.e. Flutter's tap
 * recognizer won the arena. The likely mechanism is that Chromium intermittently
 * dispatches a synthetic `pointermove` (sub-pixel jitter) or `pointercancel`
 * during the inert wait window, which rejects the long-press recognizer and lets
 * the tap recognizer fire on pointerup.
 *
 * Mitigations applied here (defence in depth):
 *   - Compute the element centre BEFORE pressing, so we control the press
 *     coordinates exactly (no implicit re-hit-test in the helper).
 *   - After `mouse.down()`, explicitly re-issue `mouse.move(cx, cy)` to anchor
 *     the cursor at the press location. This invalidates any stale browser
 *     pointer state and signals "I am still holding here" to Flutter.
 *   - Hold for `duration` ms (default 1000) — safely past Flutter's 500 ms
 *     long-press threshold even if the hold gets briefly preempted.
 *   - Re-issue `mouse.move(cx, cy)` once more right before `mouse.up()` so the
 *     release coordinate matches the press coordinate. Any drift between press
 *     and release would be interpreted as a drag and reject the long-press.
 *
 * @param page     - Playwright page.
 * @param selector - Playwright selector string for the target element.
 * @param duration - How long to hold the pointer down (ms). Default 1000ms,
 *                   chosen to comfortably exceed Flutter's 500 ms long-press
 *                   threshold even under CPU contention.
 */
export async function flutterLongPress(
  page: Page,
  selector: string,
  duration = 1000,
): Promise<void> {
  const element = page.locator(selector).first();

  // Resolve the element's bounding box BEFORE pressing so we have stable
  // coordinates. `element.hover()` would re-hit-test on each call; computing
  // (cx, cy) once lets us re-anchor the cursor at the SAME spot during the
  // hold, which is essential for Flutter's long-press recognizer.
  await element.scrollIntoViewIfNeeded();
  const box = await element.boundingBox();
  if (!box) {
    throw new Error(
      `flutterLongPress: '${selector}' has no bounding box — element may be ` +
        `detached or zero-sized.`,
    );
  }
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;

  // Move into position with a few interpolation steps so Flutter sees a clean
  // pointermove sequence, not a jump.
  await page.mouse.move(cx, cy, { steps: 3 });
  await page.mouse.down();

  // Re-anchor immediately after press: same coordinates, single step. Flutter
  // treats this as a pointermove with delta 0, which keeps the long-press
  // recognizer's "stillness" check happy and pre-empts any synthetic
  // pointercancel that Chromium might dispatch during the inert wait.
  await page.mouse.move(cx, cy);

  await page.waitForTimeout(duration);

  // Re-anchor once more right before release so the up coordinate matches the
  // down coordinate exactly. Drift between down and up coordinates would be
  // interpreted as a drag and reject the long-press recognizer.
  await page.mouse.move(cx, cy);
  await page.mouse.up();
}

/**
 * Synthesize a vertical drag-to-reorder gesture on a Flutter
 * `SliverReorderableList` / `ReorderableListView` running in CanvasKit web.
 *
 * Why this exists (and why a naive `down → moves → up` flakes ~1/3 of runs):
 * the draggable card is wrapped in a `ReorderableDragStartListener`, which
 * drives an `ImmediateMultiDragGestureRecognizer`. For that recognizer to WIN
 * the gesture arena (and actually pick the card up), CanvasKit needs to see, in
 * order:
 *   1. a settled pointer-down (the pointer registered before any move), then
 *   2. an initial movement that clearly exceeds the touch slop WITH a frame to
 *      process it — a single `mouse.down()` immediately followed by tiny
 *      `steps:2` micro-moves often gets coalesced/processed before the arena
 *      resolves, so the recognizer never claims the pointer and the whole
 *      gesture degrades to a no-op tap (the card is never lifted → order never
 *      changes → the persisted-order assertion fails),
 *   3. incremental travel to the target with per-step settles so the
 *      reorderable's drop-index tracking keeps up, then
 *   4. a hold at the destination + a settle AFTER `mouse.up()` so the drop
 *      frame (list mutation) commits before the test reads state.
 *
 * The waits here are gesture-arena settling (the legitimate use, mirroring
 * `flutterLongPress`), NOT a band-aid masking a race in production code — the
 * production `_onReorder` + Save path is pinned deterministically at the widget
 * tier. This helper only makes the *input synthesis* reliable.
 *
 * @param page    - Playwright page.
 * @param fromSel - selector for the card (or its grab affordance) to pick up.
 * @param toSel   - selector for the card to drop PAST (drops just below its
 *                  bottom edge — i.e. moves `fromSel` to after `toSel`).
 */
export async function flutterDragReorder(
  page: Page,
  fromSel: string,
  toSel: string,
): Promise<void> {
  const fromBox = await page.locator(fromSel).first().boundingBox();
  const toBox = await page.locator(toSel).nth(1).boundingBox();
  if (!fromBox || !toBox) {
    throw new Error(
      `flutterDragReorder: missing bounding box (from=${!!fromBox} ` +
        `to=${!!toBox}) — a collapsed card may be detached or zero-sized.`,
    );
  }

  const startX = fromBox.x + fromBox.width / 2;
  const startY = fromBox.y + fromBox.height / 2;
  // Drop just past the bottom edge of the destination card so the reorderable
  // resolves the insertion to AFTER it.
  const endY = toBox.y + toBox.height + 8;

  // 1. Settle the pointer at the grab point BEFORE pressing.
  await page.mouse.move(startX, startY, { steps: 3 });
  await page.waitForTimeout(120);
  await page.mouse.down();
  await page.waitForTimeout(120);

  // 2. Kick beyond the touch slop (~18px default) in ONE deliberate move, then
  //    give the gesture arena a frame to hand the pointer to the drag
  //    recognizer (the card lifts here). This is the step the naive version
  //    skipped — without it the recognizer never claims the gesture.
  await page.mouse.move(startX, startY + 24, { steps: 6 });
  await page.waitForTimeout(150);

  // 3. Travel to the destination in incremental steps with per-step settles so
  //    the drop-index tracking follows the card down the list.
  const travelSteps = 10;
  for (let i = 1; i <= travelSteps; i++) {
    const y = startY + 24 + ((endY - (startY + 24)) * i) / travelSteps;
    await page.mouse.move(startX, y, { steps: 4 });
    await page.waitForTimeout(40);
  }

  // 4. Hold at the destination so the insertion index settles, drop, then let
  //    the drop frame (list mutation) commit before the caller reads state.
  await page.mouse.move(startX, endY, { steps: 2 });
  await page.waitForTimeout(200);
  await page.mouse.up();
  await page.waitForTimeout(200);
}

/**
 * Scroll a Flutter `CustomScrollView`/`SliverList.builder` until the element
 * matched by `selector` is in the viewport, then return the located element.
 *
 * Background — Flutter web (CanvasKit) only renders sliver list items that
 * intersect the viewport. Off-screen items are NOT in the DOM at all, so
 * Playwright's `.scrollIntoViewIfNeeded()` and plain locator waits never see
 * them. The Routines list is currently long enough (custom routines empty
 * state + 9 starter routines) that the lower starter routines (Push Day,
 * Full Body) render below the 720px default viewport on a fresh user — see
 * BUG-029 follow-up where `_CustomRoutinesEmptyState` (~250px) pushed the
 * default routines off-screen.
 *
 * Implementation notes:
 *   - Hover the centre of the viewport so subsequent `mouse.wheel` events are
 *     dispatched against the scrollable area, not the AppBar/NavBar.
 *   - Step in 200px chunks (matches BUG-004 pattern) so we never blow past
 *     the target. Wait 250ms between steps so Flutter has time to paint the
 *     newly-revealed sliver children before we re-check visibility.
 *   - Bail out as soon as the element is visible — don't fight the smooth-
 *     scroll easing.
 *
 * @param page         - Playwright page.
 * @param selector     - Selector for the target element (typically
 *                       `ROUTINE.routineName('Push Day')`).
 * @param maxScrollSteps - Maximum 200px scroll steps before giving up.
 *                         Default 12 (≈2400px — well past the longest
 *                         realistic routines list).
 * @returns The Playwright `Locator` for the now-visible element. Callers can
 *          chain `.click()` or further assertions on it.
 */
export async function scrollToVisible(
  page: Page,
  selector: string,
  maxScrollSteps = 12,
): Promise<ReturnType<Page['locator']>> {
  const element = page.locator(selector).first();

  // Fast path: already in viewport.
  const alreadyVisible = await element
    .waitFor({ state: 'visible', timeout: 3_000 })
    .then(() => true)
    .catch(() => false);
  if (alreadyVisible) return element;

  // Position the cursor over the scrollable area (centre-ish, biased down so
  // we're definitely inside the body, not on the AppBar).
  const vp = page.viewportSize();
  const cx = vp ? vp.width / 2 : 400;
  const cy = vp ? vp.height * 0.6 : 400;
  await page.mouse.move(cx, cy);

  for (let i = 0; i < maxScrollSteps; i++) {
    await page.mouse.wheel(0, 200);
    await page.waitForTimeout(250);
    const found = await element
      .waitFor({ state: 'visible', timeout: 1_000 })
      .then(() => true)
      .catch(() => false);
    if (found) return element;
  }

  // Last attempt: throw a clear error so the test fails fast with a useful
  // message instead of timing out on a click() against an off-screen element.
  throw new Error(
    `scrollToVisible: '${selector}' did not enter viewport after ` +
      `${maxScrollSteps} scroll steps (≈${maxScrollSteps * 200}px).`,
  );
}
