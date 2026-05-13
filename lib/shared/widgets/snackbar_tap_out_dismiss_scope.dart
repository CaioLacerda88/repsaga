import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// Wraps a screen body in a scope that:
///
///   1. Renders any countdown-style SnackBar built via
///      [SnackBarTapOutDismissScopeState.showCountdownSnackBar] with a thin
///      bottom-edge progress bar that drains over the SnackBar's
///      [SnackBar.duration]. Driven by a `vsync` AnimationController so the
///      framework auto-pauses on app background (the spec asks for this:
///      no wall-clock `Timer`s).
///
///   2. Dismisses the current SnackBar when a pointer-down lands OUTSIDE
///      the SnackBar's rendered screen rect, but does NOT interfere with
///      pointer events that hit the SnackBar itself or that hit other
///      widgets (steppers, set-row "+ Add set", etc.). Uses a top-level
///      [Listener] (not [GestureDetector]) so child gesture recognizers
///      still own their inputs.
///
/// **The "bounding-box hit-test" contract is the load-bearing rule** —
/// without it, a user tapping a weight stepper on the exercise card above
/// the snack would dismiss the undo affordance and lose the chance to
/// restore a swiped-away set. We compute the snack's screen rect from the
/// content's [RenderBox] (via [GlobalKey]) and only dismiss when the
/// pointer is OUTSIDE that rect. The pointer event then continues down to
/// whatever the user was actually trying to tap.
///
/// Scope rather than per-call factory:
///
///   * The countdown bar widget can run independently per show, but the
///     pointer listener is a screen-level resource that must outlive
///     individual snack calls and be gated on "is a countdown snack
///     currently visible." Centralising both behind a single scope keeps
///     the visibility flag and the listener wiring in one place.
///   * Multiple call sites in the same feature reuse the same scope.
///     `SetRow` and `_onAddExercise` both fire snacks from inside
///     `ActiveWorkoutScreen` — one scope above the body covers both.
class SnackBarTapOutDismissScope extends StatefulWidget {
  const SnackBarTapOutDismissScope({super.key, required this.child});

  final Widget child;

  /// Resolve the nearest scope from [context]. Returns null when the
  /// caller is outside any scope — production callers should always be
  /// inside one, so a null return is a programmer error (asserted in
  /// debug, no-op in release).
  static SnackBarTapOutDismissScopeState? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<_SnackBarTapOutDismissInherited>()
        ?.state;
  }

  /// Resolve the nearest scope. Asserts in debug if absent.
  static SnackBarTapOutDismissScopeState of(BuildContext context) {
    final state = maybeOf(context);
    assert(
      state != null,
      'SnackBarTapOutDismissScope.of called from a context with no scope '
      'above it. Wrap your screen body in `SnackBarTapOutDismissScope`.',
    );
    return state!;
  }

  @override
  State<SnackBarTapOutDismissScope> createState() =>
      SnackBarTapOutDismissScopeState();
}

class SnackBarTapOutDismissScopeState
    extends State<SnackBarTapOutDismissScope> {
  /// `GlobalKey` attached to the countdown content widget so we can read
  /// its [RenderBox] for the bounding-box hit-test. A new key per show
  /// keeps the framework from complaining about duplicate-key reuse if a
  /// snack is shown again before the previous controller fully closes.
  GlobalKey? _activeContentKey;

  /// True between `showCountdownSnackBar` and the returned controller's
  /// `closed` future completing. The pointer listener gates on this — no
  /// snack visible means no hit-test, no dismiss.
  bool _snackVisible = false;

  /// Show a countdown-style SnackBar via the nearest [ScaffoldMessenger].
  /// The content is wrapped in a [_SnackBarCountdown] widget that renders
  /// [message] above a 3 dp progress bar draining over [duration].
  ///
  /// Pass [duration] to BOTH `SnackBar.duration` and the countdown widget
  /// — this factory keeps them in sync so callers can't desync them.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>
  showCountdownSnackBar({
    required BuildContext context,
    required String message,
    required Duration duration,
    SnackBarAction? action,
  }) {
    final messenger = ScaffoldMessenger.of(context);
    // Cancel any prior countdown snack so the bar restarts cleanly
    // instead of paint-jumping to the new duration mid-fill.
    messenger.hideCurrentSnackBar();

    final contentKey = GlobalKey(debugLabel: 'snackbar-countdown-content');
    _activeContentKey = contentKey;
    setState(() => _snackVisible = true);

    final controller = messenger.showSnackBar(
      SnackBar(
        // Shrink bottom padding to 0 so the countdown bar hugs the
        // SnackBar's bottom edge. The remaining LRT padding mirrors
        // Material's defaults for floating SnackBars.
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        duration: duration,
        // persist: false — SnackBar defaults to persistent when an action
        // is set (Flutter intentional for "wait for user action"). We
        // want this undo to auto-dismiss at `duration` even if the user
        // ignores the action.
        persist: false,
        content: _SnackBarCountdown(
          key: contentKey,
          message: message,
          duration: duration,
        ),
        action: action,
      ),
    );

    controller.closed.whenComplete(() {
      if (!mounted) return;
      // If a follow-up snack already claimed the active key, leave its
      // state alone. We only clear visibility when no replacement is
      // active.
      if (identical(_activeContentKey, contentKey)) {
        _activeContentKey = null;
      }
      setState(() => _snackVisible = false);
    });

    return controller;
  }

  /// Pointer-down handler. Bounding-box hit-test against the active
  /// countdown SnackBar's content widget; dismiss only when the event
  /// position lies OUTSIDE that rect.
  ///
  /// We deliberately use the SnackBar CONTENT's RenderBox (not the
  /// outer SnackBar widget's) — the content key is the one we own. Its
  /// rect is the user-visible snack region (modulo the
  /// [SnackBarAction]'s right-edge column, which our action affordance
  /// always intentionally falls inside since it's part of the content
  /// row above). The content RenderBox's rect comfortably covers the
  /// area a user would consider "the snack" for tap-disambiguation.
  ///
  /// Why `Listener` and not `GestureDetector`: gestures compete via
  /// recognizers — a child stepper's `onTap` would still fire, but a
  /// parent `GestureDetector(onTap: ...)` would either swallow the tap or
  /// add a recognizer to the arena and possibly steal the gesture if the
  /// child loses arena resolution. `Listener` is a pure observer; it
  /// fires `onPointerDown` for every pointer-down that reaches this point
  /// in the tree, regardless of who eventually wins the gesture.
  void _handlePointerDown(PointerDownEvent event) {
    if (!_snackVisible) return;
    final key = _activeContentKey;
    if (key == null) return;
    final renderObject = key.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.attached) return;
    final topLeft = renderObject.localToGlobal(Offset.zero);
    final rect = topLeft & renderObject.size;
    if (rect.contains(event.position)) return;
    // The pointer is outside the snack. Dismiss with the same reason
    // Flutter uses for swipe-down — we want the `closed` listeners
    // (e.g. `_undoSnackbarActive` clearing) to fire the same way.
    ScaffoldMessenger.of(
      context,
    ).hideCurrentSnackBar(reason: SnackBarClosedReason.dismiss);
  }

  @override
  Widget build(BuildContext context) {
    return _SnackBarTapOutDismissInherited(
      state: this,
      child: Listener(
        // HitTestBehavior.translucent ensures we see every pointer-down
        // without consuming it — child widgets still receive the event.
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        child: widget.child,
      ),
    );
  }
}

/// Inherited carrier so descendants can resolve the scope state without
/// prop drilling. Mirrors how `ScaffoldMessenger.of(context)` works.
class _SnackBarTapOutDismissInherited extends InheritedWidget {
  const _SnackBarTapOutDismissInherited({
    required this.state,
    required super.child,
  });

  final SnackBarTapOutDismissScopeState state;

  @override
  bool updateShouldNotify(_SnackBarTapOutDismissInherited oldWidget) =>
      !identical(state, oldWidget.state);
}

/// SnackBar content with a 3 dp countdown progress bar at its bottom edge.
///
/// The progress bar drains from full-width to zero over [duration]. The
/// controller is `vsync`-driven via `SingleTickerProviderStateMixin` so
/// the framework auto-pauses ticks when the app is backgrounded —
/// matching the SnackBar's own animation lifecycle. No `Timer`, no
/// wall-clock arithmetic.
///
/// Layout: a [Column] of `[content row, 12 dp gap, 3 dp bar]`. The bar
/// extends edge-to-edge of the content row via a 0-padding [Container]
/// pinned to the bottom. The caller is expected to pass
/// `SnackBar.padding: EdgeInsets.fromLTRB(16, 14, 16, 0)` so the bar
/// touches the SnackBar's bottom edge.
class _SnackBarCountdown extends StatefulWidget {
  const _SnackBarCountdown({
    super.key,
    required this.message,
    required this.duration,
  });

  final String message;
  final Duration duration;

  @override
  State<_SnackBarCountdown> createState() => _SnackBarCountdownState();
}

class _SnackBarCountdownState extends State<_SnackBarCountdown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.message),
        const SizedBox(height: 12),
        SizedBox(
          height: 3,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              return Stack(
                children: [
                  Container(color: AppColors.hotViolet.withValues(alpha: 0.18)),
                  Align(
                    alignment: Alignment.centerLeft,
                    widthFactor: (1 - _controller.value).clamp(0.0, 1.0),
                    child: Container(color: AppColors.hotViolet),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
