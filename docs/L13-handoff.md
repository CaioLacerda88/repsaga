# L13 back-nav — systematic-debugging handoff

**Bug.** On real-device Android 16 (Samsung Galaxy S25), system back from
any non-home bottom-nav tab (`/exercises`, `/saga`, `/treinos`) closes the
app instead of routing to `/home`. Per Phase 27 L13 spec the expected
behavior is Material/Android "always-back-to-home" — sub-routes pop
normally; tab roots go Home; Home shows two-tap exit toast.

**Status:** **NOT RESOLVED.** 3 implementation attempts (PopScope with
`enableOnBackInvokedCallback=true`, PopScope without the flag,
BackButtonListener) all pass widget tests but ALL fail on real device.

## Verified facts (do not re-verify these)

- Widget tests via `tester.binding.handlePopRoute()` all pass for every
  attempt (7/7 in `test/widget/core/router/shell_back_nav_test.dart`).
- Real device logcat (Galaxy S25 Android 16) shows
  `WindowOnBackDispatcher: sendCancelIfRunning` confirming
  `FlutterActivity$1` (the OnBackInvokedCallback) IS registered.
- A diagnostic `print('L13_DIAG: ...')` at the top of `_handlePop` (PopScope
  callback) **never appeared in logcat** — PopScope NOT reaching.
- A diagnostic `ScaffoldMessenger.showSnackBar` at the top of `_handlePop`
  **never visually flashed** — PopScope NOT reaching.
- BackButtonListener attempt (current branch state) was NOT instrumented
  with a diagnostic; user reports "still broken" so we don't yet know if
  `_handleBackButton` fires or not.

## What we know about the architecture

- **Flutter:** 3.41.6 stable
- **Engine:** revision `5cdd32777948fa7a648fac915f8da7120ac7e97a`
- **GoRouter:** 17.2.0
- **Target SDK:** 36 (Android 16); minSdk 24
- **Package:** `com.repsaga.app`; `MainActivity extends FlutterActivity` (no
  custom back override)
- `lib/main.dart` has `GoogleFonts.config.allowRuntimeFetching = false`
- AndroidManifest does NOT have `android:enableOnBackInvokedCallback`
  (tried both with and without — same failure either way)
- `lib/core/local_storage/hive_service.dart:openWithRecovery` self-heals
  Hive box corruption — `HiveError: unknown typeId: 45` appears at startup
  in logcat but is auto-recovered. The app reaches Home successfully and
  all other UI works.

## Code under test

`lib/core/router/app_router.dart` — `_ShellScaffoldState`:

```dart
return BackButtonListener(
  onBackButtonPressed: _handleBackButton,
  child: Scaffold(...),
);
```

`_handleBackButton`:
```dart
Future<bool> _handleBackButton() async {
  if (context.canPop()) return false;          // sub-route → let GoRouter pop
  final location = GoRouterState.of(context).matchedLocation;
  final path = Uri.parse(location).path;
  if (path == '/home' || path == '/') {
    if (_exitPending) { SystemNavigator.pop(); return true; }
    _arm(); return true;
  }
  context.go('/home');
  return true;
}
```

`ShellRoute` builder wraps every shell child:
```dart
ShellRoute(
  builder: (context, state, child) =>
      SagaIntroGate(child: ShellScaffold(child: child)),
  routes: [GoRoute(path: '/home', ...), ...],
)
```

Tab switches use `context.go(target)` (REPLACES route stack — that's
intentional, per the locked tab-nav pattern).

## Hypotheses ranked by likelihood

1. **GoRouter 17.2.0's ShellRoute registers its OWN internal PopScope** at
   `lib/src/builder.dart:295`:
   ```dart
   return PopScope(
     canPop: match.matches.length == 1,
     child: _CustomNavigator(...),
   );
   ```
   At a tab root (`match.matches.length == 1`), this PopScope has
   `canPop: true` — it claims to be poppable, possibly racing our
   PopScope and "winning" the route-registration order.
2. **`tester.binding.handlePopRoute()` doesn't simulate the real Android
   back-press chain.** On API 36, Flutter routes back via either
   `OnBackInvokedCallback` (when flag set) or legacy `onBackPressed`
   (default). Both eventually call `navigationChannel.popRoute` →
   `WidgetsBinding.handlePopRoute` → observer chain. The test path enters
   at `handlePopRoute` directly; the device path enters earlier and may
   diverge through the predictive-back integration.
3. **The Hive `unknown typeId: 45` startup error leaves some Riverpod
   provider in error state**, which somehow disposes the BackButtonListener
   or unregisters it before the user presses back. The user navigates
   normally so this is a stretch, but worth a `flutter clean` + uninstall
   (NOT just install -r) + reinstall to clear all box state and test.
4. **API 36-specific Flutter framework bug** with predictive-back and
   nested navigators. Galaxy S25 ships Android 16 which is bleeding edge;
   the user's logcat is one of the first real-device verifications of
   Flutter 3.41 on API 36.

## Suggested next-session approach

1. Open with `superpowers:systematic-debugging` skill.
2. Phase 1 — Read this handoff doc, the L13 commits on
   `feature/27-post-26f-bugfix` (`456047f`, `d9b3737`, the current
   uncommitted L13.3 BackButtonListener change), and the relevant Flutter
   framework source (`/c/flutter/packages/flutter/lib/src/widgets/router.dart`
   `BackButtonDispatcher.invokeCallback`,
   `/c/flutter/engine/src/flutter/shell/platform/android/.../FlutterActivity.java`
   `createOnBackInvokedCallback`). Build the failure model BEFORE writing
   code.
3. Phase 2 — Add a diagnostic that GUARANTEES visibility regardless of
   whether the activity closes immediately. Suggestions:
   - Write to a Hive box and read on next launch (survives activity exit).
   - Use `developer.log` with explicit `name:` — sometimes more reliable
     than `print` in release for the flutter logcat tag filter.
   - Use a Riverpod observer + Sentry breadcrumb (Sentry is wired and
     flushes synchronously on crash).
4. Phase 3 — Hypothesis: dispatch a tech-lead to isolate the failure by
   adding a SECOND BackButtonListener at the ROOT App level (above
   GoRouter). If THAT fires but the shell's doesn't, the issue is
   GoRouter consuming the dispatcher chain.
5. Phase 4 — If the root-level listener also doesn't fire, the issue is
   Flutter 3.41 + Android 16 OnBackInvokedCallback wiring. Workaround:
   add a native-Android back-press override in `MainActivity.kt` that
   forwards to a method channel handled in Dart.

## Out-of-scope reminders

- The other Phase 27 fixes (L1–L18 minus L13) are in commits on the
  branch and verified by the user on device. Do NOT regress them.
- L13 is the only outstanding device-failure.
- 7 memory entries from the original triage are already saved. Plus
  `feedback_fixed_values_in_design` from the user's recent typography
  question.

## Files modified by the current L13.3 attempt (uncommitted)

- `lib/core/router/app_router.dart` (PopScope → BackButtonListener +
  `_handlePop` → `_handleBackButton`; uses `context.canPop()` to
  distinguish sub-route from tab root)
