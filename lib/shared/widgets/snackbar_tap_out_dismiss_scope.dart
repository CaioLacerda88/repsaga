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
    SnackBarAction? secondaryAction,
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
    //
    // [secondaryAction] is opt-in (Phase 24c-8 — bodyweight prompt).
    // When provided, it renders as a quieter (text-only, dim) button to
    // the LEFT of the primary action so the user reads "Skip | Set now"
    // left-to-right. Most snack call sites are single-action (Undo /
    // Save now / Retry) so this stays additive — null-secondary
    // preserves the original layout byte-for-byte.
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
        content: SnackBarCountdown._(
          key: contentKey,
          message: message,
          duration: duration,
          actionLabel: action?.label,
          onAction: action?.onPressed,
          secondaryActionLabel: secondaryAction?.label,
          onSecondaryAction: secondaryAction?.onPressed,
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

/// SnackBar content widget owning the full snack interior: message row +
/// optional action button + bottom-edge countdown progress bar.
///
/// **Why this widget owns everything:** Flutter's `SnackBar.content` and
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
/// Public type with a **private constructor** — instantiation is reserved
/// to [SnackBarTapOutDismissScopeState.showCountdownSnackBar]. The class
/// is public so widget tests can locate it via `find.byType(...)`
/// without depending on the library's private GlobalKey lookup. The
/// private constructor prevents call sites from bypassing the factory
/// and dropping the persist:false + tap-out wiring.
///
/// **Drain mechanism** (root-cause fix 2026-05-14): the bar uses
/// [TweenAnimationBuilder] (begin 1.0, end 0.0, curve `Curves.linear`,
/// duration `duration`) instead of a manual `AnimationController` +
/// `forward()`. Single source of truth for the duration, no controller
/// lifecycle to mishandle, and `TweenAnimationBuilder` only animates
/// once on mount — which exactly matches the "drain once over
/// [duration], never restart" contract. The widget can be a
/// [StatelessWidget] as a result.
///
/// **Why `FractionallySizedBox` and not `Align(widthFactor:)`:** the
/// previous implementation used `Align(widthFactor: X, child:
/// ColoredBox(...))`. `Align` passes LOOSE constraints to its child, and
/// a `ColoredBox` with no child collapses to 0×0 under loose constraints
/// — so the draining rectangle was invisible on every frame. The user
/// saw only the unchanging track. `FractionallySizedBox(widthFactor: X,
/// child: ColoredBox)` passes a TIGHT width constraint
/// (`parent.width × X`) so the `ColoredBox` fills it. The wrapping
/// `SizedBox(height: 3, width: double.infinity)` gives the
/// `TweenAnimationBuilder`'s subtree a concrete-bounded parent rect
/// for the `FractionallySizedBox` math to multiply against; without
/// it both axes could be loose and we'd re-introduce the original bug.
class SnackBarCountdown extends StatelessWidget {
  const SnackBarCountdown._({
    super.key,
    required this.message,
    required this.duration,
    this.actionLabel,
    this.onAction,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  /// Key on the track widget — the dim-violet [ColoredBox] that holds
  /// the full-width track plus the draining filler. Exposed so widget
  /// tests can measure the track's rendered rect.
  static const trackKey = ValueKey('snackbar-countdown-track');

  /// Key on the inner draining widget — the [FractionallySizedBox] whose
  /// width shrinks from `parent × 1.0` → `parent × 0.0` over [duration].
  /// Exposed so widget tests can measure the *fill* width at two time
  /// slices and assert it actually drained (regression guard for the
  /// 2026-05-14 "fill collapses to 0×0 under loose constraints" bug).
  static const fillerKey = ValueKey('snackbar-countdown-filler');

  final String message;
  final Duration duration;

  /// Localized action label (e.g. `l10n.undo`). When null, the action
  /// button is omitted and the message takes the full row width.
  ///
  /// Kept nullable to mirror the factory's `SnackBarAction?` arg — every
  /// production caller passes an action today, but the no-action path is
  /// part of the public contract and covered by the widget's unit tests.
  final String? actionLabel;

  /// Action callback. Required when [actionLabel] is non-null; ignored
  /// otherwise.
  final VoidCallback? onAction;

  /// Secondary, dismissive-style action label (e.g. `l10n.bodyweightPromptSkip`).
  /// Renders to the LEFT of the primary action as a quieter
  /// (`onSurfaceVariant`-tinted) text button so the visual hierarchy
  /// reads "Skip | Set now" left-to-right. Optional — null hides the
  /// secondary slot entirely (no layout shift; the Row collapses).
  ///
  /// Phase 24c-8 — bodyweight prompt is the first multi-action snack
  /// in the app. Kept additive so existing single-action callers
  /// (Undo, Save now, Retry) render unchanged.
  final String? secondaryActionLabel;

  /// Secondary action callback. Required when [secondaryActionLabel] is
  /// non-null; ignored otherwise.
  final VoidCallback? onSecondaryAction;

  @override
  Widget build(BuildContext context) {
    final hasAction = actionLabel != null && onAction != null;
    final hasSecondaryAction =
        secondaryActionLabel != null && onSecondaryAction != null;

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
      (hasAction || hasSecondaryAction) ? 8 : 16,
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
                  message,
                  // Inherit `SnackBarThemeData.contentTextStyle` — set in
                  // `AppTheme` to `textCream` on `surface2`.
                ),
              ),
              // Secondary (dismissive) action renders LEFT of the primary
              // so the eye reads "Skip | Set now" — Material convention
              // for paired affirmative/dismissive choices.
              if (hasSecondaryAction)
                _SecondaryActionButton(
                  label: secondaryActionLabel!,
                  onPressed: onSecondaryAction!,
                ),
              if (hasAction)
                _UndoButton(label: actionLabel!, onPressed: onAction!),
            ],
          ),
        ),
        // Progress bar hugs the snack's bottom edge, full width.
        //
        // Layer cake:
        //   * Track:   outer ColoredBox (dim violet @ 18% alpha) sized
        //              by its SizedBox(height: 3, width: infinity) child.
        //   * Filler:  inner FractionallySizedBox whose widthFactor
        //              drains 1.0 → 0.0 over `duration`. Holds a
        //              ColoredBox(hotViolet) keyed for regression
        //              measurement.
        //
        // The SizedBox.width = double.infinity is load-bearing: it
        // gives the TweenAnimationBuilder's subtree a concrete bounded
        // parent for FractionallySizedBox to multiply against.
        ColoredBox(
          color: AppColors.hotViolet.withValues(alpha: 0.18),
          child: SizedBox(
            key: trackKey,
            height: 3,
            width: double.infinity,
            child: TweenAnimationBuilder<double>(
              // Curves.linear: the bar drains evenly over time — matches
              // user expectation ("3 s left → 1.5 s left → done"). A
              // non-linear curve would feel like the bar lies about
              // remaining time near the start/end.
              tween: Tween<double>(begin: 1.0, end: 0.0),
              duration: duration,
              curve: Curves.linear,
              builder: (_, value, _) {
                return FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  // Clamp defensively — TweenAnimationBuilder shouldn't
                  // produce out-of-range values for a 1.0→0.0 tween,
                  // but a future tween/curve change could.
                  widthFactor: value.clamp(0.0, 1.0),
                  child: const ColoredBox(
                    key: fillerKey,
                    color: AppColors.hotViolet,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Undo action button embedded inside [SnackBarCountdown]'s content row.
///
/// Two responsibilities, one widget:
///   1. Run the caller's [onPressed] (the restore action — restoreExercise,
///      restoreSet, etc.).
///   2. Dismiss the current SnackBar with reason `action`, recreating the
///      auto-dismiss behaviour Flutter's built-in [SnackBarAction] gets
///      for free in the `SnackBar.action` slot.
///
/// **Why we can't use [SnackBarAction]:** the action lives inside
/// `SnackBar.content` so the countdown bar can span the full snack
/// interior (see [SnackBarCountdown] class doc). `SnackBarAction`'s
/// auto-dismiss is special-cased by `ScaffoldMessengerState` only when
/// it's wired through the `SnackBar.action` slot.
///
/// **Lifecycle parity with `SnackBarAction`:**
///   * `onPressed` fires synchronously BEFORE `hideCurrentSnackBar` —
///     matches Flutter's order so any state mutation (restore) is
///     observable before the snack closes.
///   * Dismiss uses `SnackBarClosedReason.action` — listeners on the
///     factory's returned `controller.closed` (e.g. plan-management's
///     `_undoSnackbarActive` flag clearing) fire the same way they
///     would for a real `SnackBarAction`.
///
/// Extracted as a `StatelessWidget` rather than inlined as a closure so
/// the build context used for `ScaffoldMessenger.of(...)` is THIS
/// widget's mount-point context — guaranteed to be inside the route-
/// scoped messenger that owns the snack (the messenger inserts this
/// content widget into its own subtree).
class _UndoButton extends StatelessWidget {
  const _UndoButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () {
        onPressed();
        ScaffoldMessenger.of(
          context,
        ).hideCurrentSnackBar(reason: SnackBarClosedReason.action);
      },
      style: TextButton.styleFrom(
        foregroundColor: AppColors.hotViolet,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        // 48 dp minimum width = Material's tap-target floor. Not a
        // fixed width — the button grows with longer localized labels
        // (e.g. PT "DESFAZER" vs EN "UNDO").
        minimumSize: const Size(48, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

/// Quieter, dismissive secondary action paired with [_UndoButton] in
/// multi-action snacks (Phase 24c-8 — bodyweight prompt's "Skip" sits
/// next to "Set now"). Same structural responsibilities as [_UndoButton]
/// — fire the caller's [onPressed] then dismiss the snack with reason
/// `action` so `controller.closed` listeners run the same way they
/// would for a real `SnackBarAction`.
///
/// **Visual treatment:** `onSurfaceVariant` foreground (theme-driven
/// dim cream over `surface2`) instead of [_UndoButton]'s `hotViolet` —
/// the secondary slot is dismissive (Skip/Cancel/Not now), the primary
/// is affirmative (Set now/Undo/Save). Material spec for paired action
/// buttons: dismissive < affirmative in visual weight.
///
/// Padding mirrors [_UndoButton] so the two buttons line up and the
/// 48 dp Material tap-target floor is preserved per button.
class _SecondaryActionButton extends StatelessWidget {
  const _SecondaryActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return TextButton(
      onPressed: () {
        onPressed();
        ScaffoldMessenger.of(
          context,
        ).hideCurrentSnackBar(reason: SnackBarClosedReason.action);
      },
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.onSurfaceVariant,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(48, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}
