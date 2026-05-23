/// Bug D — OfflineBanner respects the status-bar inset on Android edge-to-edge.
///
/// `_ShellScaffold` paints the OfflineBanner as an `Align(topCenter)` overlay
/// inside a `Stack` at body y=0. With Flutter's default `Scaffold` behavior on
/// Android edge-to-edge mode (no AppBar), the body extends behind the system
/// status bar — so without an explicit `SafeArea(top: true)` wrap the banner
/// sat behind the clock + notification icons.
///
/// Cluster: `safearea-system-overlay-overlap` — new pattern. Same class as
/// the PostSessionScreen visual fix landed in `bff76bd`.
///
/// Contract pinned here:
///   * With `viewPadding.top = 24` and `isOnline = false`, the rendered
///     `OfflineBanner`'s top Y is `>= 24` (it sits below the status bar,
///     NOT at y=0 behind it).
///   * The tab content (inside `widget.child`) starts at Y `>= 24 + 42 = 66`
///     (status bar inset + banner content height).
///   * When online, no padding is added — the body starts at y=0 (the
///     normal edge-to-edge contract; tab content widgets own their own
///     SafeArea wraps).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:repsaga/core/connectivity/connectivity_provider.dart';
import 'package:repsaga/core/local_storage/cache_refresh_provider.dart';
import 'package:repsaga/core/offline/sync_service.dart';
import 'package:repsaga/core/router/app_router.dart';
import 'package:repsaga/core/theme/app_theme.dart';
import 'package:repsaga/features/personal_records/providers/pr_cache_bootstrap_provider.dart';
import 'package:repsaga/features/rpg/providers/earned_titles_backfill_provider.dart';
import 'package:repsaga/features/rpg/providers/rpg_progress_provider.dart';
import 'package:repsaga/features/workouts/models/active_workout_state.dart';
import 'package:repsaga/features/workouts/providers/notifiers/active_workout_notifier.dart';
import 'package:repsaga/features/workouts/providers/workout_providers.dart';
import 'package:repsaga/l10n/app_localizations.dart';
import 'package:repsaga/shared/widgets/offline_banner.dart';

// ---------------------------------------------------------------------------
// Stubs — minimum overrides to render ShellScaffold in isolation. Mirrors
// `test/widget/core/router/shell_back_nav_test.dart`.
// ---------------------------------------------------------------------------

class _NullActiveWorkoutNotifier extends AsyncNotifier<ActiveWorkoutState?>
    implements ActiveWorkoutNotifier {
  @override
  Future<ActiveWorkoutState?> build() async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopSyncService extends SyncService {
  @override
  SyncState build() => const SyncState();
}

class _EmptyRpgProgress extends AsyncNotifier<RpgProgressSnapshot>
    implements RpgProgressNotifier {
  @override
  Future<RpgProgressSnapshot> build() async => RpgProgressSnapshot.empty;

  @override
  Future<RpgProgressSnapshot> refreshAfterSave() async =>
      RpgProgressSnapshot.empty;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ---------------------------------------------------------------------------
// Test sentinel — the tab content rendered inside the shell. A Container
// stretching the full body so we can measure its top Y via `tester.getTopLeft`.
// ---------------------------------------------------------------------------

const String _kTabContentKey = 'tab-content-sentinel';

const _TabContent _tabContent = _TabContent();

class _TabContent extends StatelessWidget {
  const _TabContent();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      key: ValueKey(_kTabContentKey),
      child: ColoredBox(color: Color(0xFF112233)),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Builds a minimal router whose ShellRoute uses the real production
/// [ShellScaffold] and a single tab leaf rendering `_TabContent`. We don't
/// need the full route tree — the SafeArea contract is owned by the shell.
GoRouter _buildRouter() {
  return GoRouter(
    initialLocation: '/home',
    routes: [
      ShellRoute(
        builder: (context, state, child) => ShellScaffold(child: child),
        routes: [GoRoute(path: '/home', builder: (_, _) => _tabContent)],
      ),
    ],
  );
}

/// Wraps the app under test. Status-bar inset is set on `tester.view`
/// BEFORE `pumpWidget` (see test bodies) — `MaterialApp.router` constructs
/// its own `MediaQuery.fromView`, which reads `viewPadding` directly from
/// the test view. Setting it via a `MediaQuery` ancestor above MaterialApp
/// would NOT work — the inner `MediaQuery.fromView` would clobber it.
Widget _wrap({required GoRouter router, required bool isOnline}) {
  return ProviderScope(
    overrides: [
      activeWorkoutProvider.overrideWith(() => _NullActiveWorkoutNotifier()),
      isOnlineProvider.overrideWithValue(isOnline),
      cacheRefreshProvider.overrideWith((_) async {}),
      syncServiceProvider.overrideWith(() => _NoopSyncService()),
      rpgProgressProvider.overrideWith(() => _EmptyRpgProgress()),
      prCacheBootstrapProvider.overrideWith((_) async {}),
      earnedTitlesBackfillProvider.overrideWith((_) async {}),
    ],
    child: MaterialApp.router(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.dark,
      routerConfig: router,
    ),
  );
}

/// Sets the test view's `viewPadding.top` to [inset] dp and registers a
/// tear-down that resets it. Must be called BEFORE `pumpWidget`.
///
/// `tester.view.viewPadding` is stored in PHYSICAL pixels; the framework
/// divides by `devicePixelRatio` (default 3.0) before exposing as logical
/// `MediaQuery.viewPadding`. We force DPR to 1.0 here so the dp we pass in
/// equals the dp the production code reads — otherwise a 24dp inset would
/// come out as 8dp logical and the contract assertions would underflow.
void _setStatusBarInset(WidgetTester tester, double inset) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewPadding = FakeViewPadding(top: inset);
  // `padding` derives from `viewPadding` minus keyboard insets; with no
  // keyboard, the two are equal. We set both to keep MediaQuery internally
  // consistent (some widgets read .padding, others .viewPadding).
  tester.view.padding = FakeViewPadding(top: inset);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetViewPadding();
    tester.view.resetPadding();
  });
}

void main() {
  group('ShellScaffold offline banner — SafeArea status-bar inset contract', () {
    testWidgets('with viewPadding.top=24 and offline, banner top Y >= 24 '
        '(NOT behind the status bar)', (tester) async {
      _setStatusBarInset(tester, 24);

      await tester.pumpWidget(_wrap(router: _buildRouter(), isOnline: false));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBanner), findsOneWidget);

      final bannerTop = tester.getTopLeft(find.byType(OfflineBanner)).dy;
      // With SafeArea(top: true) wrapping the banner, the banner content
      // sits below the 24dp status bar inset. Pre-fix this was 0.0.
      expect(
        bannerTop,
        greaterThanOrEqualTo(24.0),
        reason:
            'OfflineBanner must sit BELOW the status bar inset, not behind '
            'it. Without SafeArea(top: true) the banner renders at y=0 and '
            'is hidden under the clock + notification icons on Android '
            'edge-to-edge mode (Bug D, cluster safearea-system-overlay-overlap).',
      );
    });

    testWidgets(
      'with viewPadding.top=24 and offline, tab content starts at Y >= 66 '
      '(24 inset + 42 banner)',
      (tester) async {
        _setStatusBarInset(tester, 24);

        await tester.pumpWidget(_wrap(router: _buildRouter(), isOnline: false));
        await tester.pumpAndSettle();

        final tabContent = find.byKey(const ValueKey(_kTabContentKey));
        expect(tabContent, findsOneWidget);

        final tabTop = tester.getTopLeft(tabContent).dy;
        // Body Padding = viewPaddingTop + _kOfflineBannerHeight = 24 + 42 = 66.
        // This is the contract that prevents the banner from overlapping
        // tab content when the inset is non-zero.
        expect(
          tabTop,
          greaterThanOrEqualTo(66.0),
          reason:
              'Tab content must start below the status bar inset PLUS the '
              'banner content height. Without this padding the banner overlay '
              'covers the top of the tab content.',
        );
      },
    );

    testWidgets('with viewPadding.top=24 and online, tab content starts at Y=0 '
        '(no padding when banner is hidden)', (tester) async {
      _setStatusBarInset(tester, 24);

      await tester.pumpWidget(_wrap(router: _buildRouter(), isOnline: true));
      await tester.pumpAndSettle();

      expect(find.byType(OfflineBanner), findsNothing);

      final tabContent = find.byKey(const ValueKey(_kTabContentKey));
      final tabTop = tester.getTopLeft(tabContent).dy;
      // When online there is no banner — tab content takes the full body.
      // The shell does NOT add status-bar padding (that's the tab widget's
      // own responsibility via its own SafeArea). This locks the
      // online-state contract so we don't accidentally regress by double-
      // padding the body unconditionally.
      expect(
        tabTop,
        equals(0.0),
        reason:
            'When online, the shell does not add status-bar padding — tab '
            'content widgets own their own SafeArea wraps and the body '
            'flows edge-to-edge.',
      );
    });

    testWidgets(
      'with viewPadding.top=0 (no inset, e.g. iPad without status bar) and '
      'offline, banner top Y == 0 and tab content Y == 42',
      (tester) async {
        _setStatusBarInset(tester, 0);

        await tester.pumpWidget(_wrap(router: _buildRouter(), isOnline: false));
        await tester.pumpAndSettle();

        final bannerTop = tester.getTopLeft(find.byType(OfflineBanner)).dy;
        // Zero inset → SafeArea(top: true) adds no padding → banner at y=0.
        expect(bannerTop, equals(0.0));

        final tabContent = find.byKey(const ValueKey(_kTabContentKey));
        final tabTop = tester.getTopLeft(tabContent).dy;
        // Body padding = 0 + 42 = 42.
        expect(tabTop, equals(42.0));
      },
    );
  });
}
