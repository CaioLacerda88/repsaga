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
  ///
  /// The entire snack interior is owned by `_SnackBarCountdown`: the
  /// message text, the optional action button, and the bottom-edge
  /// progress bar all live inside ONE widget so the bar can span the
  /// full snack width and hug the bottom edge.
  ///
  /// Why we don't pass `action:` to `SnackBar`: Flutter renders
  /// `SnackBar.content` and `SnackBar.action` as siblings in a Row. The
  /// content slot is constrained to "everything left of the action
  /// column" — so a progress bar inside `content` can never reach the
  /// snack's right edge. By passing `action: null` and embedding the
  /// action in the content widget ourselves, the entire interior is
  /// one render subtree and the bar spans the actual snack width.
  /// `SnackBar.padding: EdgeInsets.zero` lets the widget control all
  /// inner padding (message side gets 16/14/8/12, bar gets 0 so it
  /// reaches every edge).
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

    // We accept a `SnackBarAction` (callers naturally construct one) but
    // re-render it ourselves inside `_SnackBarCountdown` so message +
    // action share the same Row, and the progress bar can span beneath
    // both. The action's `label` and `onPressed` are the only fields we
    // surface — colour, etc. flow from `AppTheme` defaults at the
    // button level inside the widget.
    final controller = messenger.showSnackBar(
      SnackBar(
        // padding: zero — widget owns all inner padding so the progress
        // bar can hug every edge of the snack interior. Without this,
        // Flutter's default `EdgeInsets.symmetric(horizontal: 16,
        // vertical: 14)` would leave a 14 dp gap between the bar and
        // the snack's bottom edge.
        padding: EdgeInsets.zero,
        duration: duration,
        // persist: false — SnackBar defaults to persistent when an
        // action is set. We pass `action: null` to SnackBar (the action
        // lives inside `_SnackBarCountdown`), so the default `persist`
        // would be `false` anyway; explicit `false` documents intent.
        persist: false,
        content: _SnackBarCountdown(
          key: contentKey,
          message: message,
          duration: duration,
          actionLabel: action?.label,
          onAction: action?.onPressed,
        ),
        // action: null — see the doc above. Embedding the button inside
        // `content` is what lets the progress bar span the full snack
        // width.
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
  /// We use the SnackBar CONTENT's RenderBox (the `_SnackBarCountdown`
  /// instance, keyed via [GlobalKey]). Now that the widget owns the
  /// entire snack interior — message + action + progress bar — the
  /// content RenderBox's rect matches what a user would call "the
  /// snack." A pointer landing on the embedded UNDO button lands
  /// INSIDE that rect, so this handler correctly no-ops and the
  /// button's own `onPressed` fires.
  ///
  /// Why `Listener` and not `GestureDetector`: gestures compete via
  /// recognizers — a child stepper's `onTap` would still fire, but a
  /// parent `GestureDetector(onTap: ...)` would either swallow the tap
  /// or add a recognizer to the arena and possibly steal the gesture
  /// if the child loses arena resolution. `Listener` is a pure
  /// observer; it fires `onPointerDown` for every pointer-down that
  /// reaches this point in the tree, regardless of who eventually
  /// wins the gesture.
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

/// Owns the entire SnackBar interior — message row + optional action
/// button + bottom-edge countdown progress bar.
///
/// **Why this widget owns everything:** see the factory's class-level
/// doc. The short version: Flutter's `SnackBar.content` and
/// `SnackBar.action` slots are siblings in a Row; a progress bar inside
/// `content` can never reach the right edge of the snack because the
/// `action:` column claims its own width. By collapsing both into one
/// widget passed via `SnackBar.content` (with `SnackBar.action: null`),
/// the progress bar lives in the same render subtree as message + action
/// and spans the full snack interior.
///
/// **Adaptive sizing:** the Row uses `Expanded` for the message so it
/// fills whatever horizontal space the snack receives from the framework
/// (which already adapts to screen width via
/// `SnackBarBehavior.floating`'s defaults). The progress bar inherits
/// the Column's stretched width — no fixed `width:` props anywhere.
///
/// **Countdown lifecycle:** the controller is `vsync`-driven via
/// `SingleTickerProviderStateMixin` so the framework auto-pauses ticks
/// when the app is backgrounded. No `Timer`, no wall-clock arithmetic.
class _SnackBarCountdown extends StatefulWidget {
  const _SnackBarCountdown({
    super.key,
    required this.message,
    required this.duration,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final Duration duration;

  /// Localized action label (e.g. `l10n.undo`). When null, the action
  /// button is omitted and the message takes the full row width.
  final String? actionLabel;

  /// Action callback. Required when [actionLabel] is non-null; ignored
  /// otherwise.
  final VoidCallback? onAction;

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
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    // Padding values:
    //   * Left 16 dp — Material's standard SnackBar inset for content.
    //   * Top 14 dp — matches Material's default vertical inset.
    //   * Right 8 dp when an action is present (the TextButton has its
    //     own internal padding that covers the remaining ~8 dp), or 16
    //     dp when there's no action (symmetric inset).
    //   * Bottom 12 dp — generous gap above the progress bar so the
    //     copy doesn't visually collide with the draining stripe.
    final messageRowPadding = EdgeInsets.fromLTRB(
      16,
      14,
      hasAction ? 8 : 16,
      12,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: messageRowPadding,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.message,
                  // Inherit `SnackBarThemeData.contentTextStyle` — set in
                  // `AppTheme` to `textCream` on `surface2`.
                ),
              ),
              if (hasAction)
                TextButton(
                  onPressed: widget.onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.hotViolet,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    // 48 dp minimum width = Material's tap-target floor.
                    // Not a fixed width — the button grows with longer
                    // localized labels (e.g. PT "DESFAZER" vs EN "UNDO").
                    minimumSize: const Size(48, 36),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(widget.actionLabel!),
                ),
            ],
          ),
        ),
        // Progress bar hugs the snack's bottom edge, full width.
        // ColoredBox paints the track (dim violet); the AnimatedBuilder
        // overlays the draining bar on top. The bar's `widthFactor`
        // shrinks from 1.0 → 0.0 as the controller advances.
        ColoredBox(
          color: AppColors.hotViolet.withValues(alpha: 0.18),
          child: SizedBox(
            height: 3,
            // No `width:` — SizedBox inherits its parent Column's
            // stretched cross-axis width, which IS the snack's full
            // interior width (the SnackBar passes
            // `padding: EdgeInsets.zero` so nothing else claims that
            // width).
            child: AnimatedBuilder(
              animation: _controller,
              builder: (_, _) {
                return Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: (1 - _controller.value).clamp(0.0, 1.0),
                  child: const ColoredBox(color: AppColors.hotViolet),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
