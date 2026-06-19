import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Asset-backed icon set for RepSaga's Arcane Ascent direction (§17.0c,
/// upgraded in §17.0e to the game-icons.net silhouette pack).
///
/// Each constant is an asset path under `assets/icons/v3-silhouette/` pointing
/// at a Game-Icons.net SVG (CC BY 3.0 — Lorc + Delapouite, with one MDI
/// fallback for `kettlebell`). Credits are registered in `lib/main.dart` via
/// `LicenseRegistry.addLicense(...)` and surface through Flutter's built-in
/// `showLicensePage`.
///
/// Why asset paths (not inline strings)?
/// - Pack cohesion: every glyph comes from the same curated set — no
///   hand-drawn outliers reading flat/amateur next to the silhouette icons.
/// - Diffability: a designer tweaking a glyph edits one SVG file, not a Dart
///   string literal.
/// - Binary size: `SvgPicture.asset` streams from the asset bundle;
///   `SvgPicture.string` would keep the XML as Dart source.
///
/// All icons render through [render] which wraps `SvgPicture.asset` in a
/// `ColorFilter.mode(..., srcIn)`. Source SVGs already use `fill="currentColor"`
/// so a single asset recolors for every state (idle / active / reward).
///
/// **Lift icon rule.** [lift] is Delapouite's `weight-lifting-up` — a figure
/// mid-snatch. It is the app's signature icon and the single most-referenced
/// glyph in the codebase; it reads as "this is a lift app" at 24 dp on the
/// nav bar. The same asset doubles as the `EquipmentType.barbell` affordance
/// (see `AppEquipmentIcons` doc for the dedup rationale).
class AppIcons {
  const AppIcons._();

  // ---------------------------------------------------------------------
  // Asset root
  // ---------------------------------------------------------------------

  /// Root path for the v3-silhouette pack. Every [AppIcons] /
  /// [AppMuscleIcons] / [AppEquipmentIcons] asset lives under this folder.
  static const String _root = 'assets/icons/v3-silhouette';

  // ---------------------------------------------------------------------
  // Primary nav
  // ---------------------------------------------------------------------

  /// House silhouette (Game-Icons: `house`). Home tab.
  static const String home = '$_root/home.svg';

  /// Figure mid-snatch (Game-Icons: `weight-lifting-up`). App signature
  /// glyph — also aliased by `EquipmentType.barbell`.
  static const String lift = '$_root/lift.svg';

  /// Unfurled scroll (Game-Icons: `scroll-unfurled`). Routines / plan tab.
  static const String plan = '$_root/plan.svg';

  /// Stepped progression (Game-Icons: `progression`). Stats surface.
  static const String stats = '$_root/stats.svg';

  /// Muscular hero silhouette (Game-Icons: `muscle-up`). Profile tab +
  /// splash lift.
  static const String hero = '$_root/hero.svg';

  // ---------------------------------------------------------------------
  // Reward / state
  // ---------------------------------------------------------------------

  /// Shining crystal (Game-Icons: `crystal-shine`). XP currency glyph.
  static const String xp = '$_root/xp.svg';

  /// Upward arrow badge (Game-Icons: `upgrade`). Level-up celebration.
  static const String levelUp = '$_root/levelUp.svg';

  /// Flame silhouette (Game-Icons: `flame`). Weekly streak glyph.
  static const String streak = '$_root/streak.svg';

  // ---------------------------------------------------------------------
  // Verbs
  // ---------------------------------------------------------------------

  /// Check-mark (Game-Icons: `check-mark`). Confirmation / done state.
  static const String check = '$_root/check.svg';

  /// Spawn node (Game-Icons: `spawn-node`). Create / add action.
  static const String add = '$_root/add.svg';

  /// Quill + ink (Game-Icons: `quill-ink`). Edit action.
  static const String edit = '$_root/edit.svg';

  /// Trash can (Game-Icons: `trash-can`). Delete action.
  static const String delete = '$_root/delete.svg';

  /// Funnel (Game-Icons: `funnel`). Filter action.
  static const String filter = '$_root/filter.svg';

  /// Magnifying glass (Game-Icons: `magnifying-glass`). Search action.
  static const String search = '$_root/search.svg';

  /// Cog (Game-Icons: `cog`). Settings action.
  static const String settings = '$_root/settings.svg';

  // ---------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------

  /// Play button (Game-Icons: `play-button`).
  static const String play = '$_root/play.svg';

  /// Pause button (Game-Icons: `pause-button`).
  static const String pause = '$_root/pause.svg';

  /// Play button (Game-Icons: `play-button`) — ships in a distinct
  /// `resume.svg` file (byte-identical glyph as `play.svg`) so call sites can
  /// express intent without relying on aliasing.
  static const String resume = '$_root/resume.svg';

  /// Checkered flag (Game-Icons: `checkered-flag`). Finish action.
  static const String finish = '$_root/finish.svg';

  /// Cancel / X (Game-Icons: `cancel`). Close action.
  static const String close = '$_root/close.svg';

  // ---------------------------------------------------------------------
  // Renderer
  // ---------------------------------------------------------------------

  /// Renders an icon asset at [size] dp with the given [color].
  ///
  /// All pack SVGs use `fill="currentColor"`, which `flutter_svg` resolves
  /// via a srcIn color filter. This means a single asset recolors for every
  /// state (idle/active/reward) without shipping multiple variants.
  ///
  /// When [color] is omitted, the renderer reads from
  /// `IconTheme.of(context).color`, falling back to a plain black if the
  /// ancestor `IconTheme` doesn't set a color. This lets callers wrap an
  /// `AppIcons.render` subtree in a `RewardAccent` (or any other
  /// `IconTheme.merge`) and have the SVG inherit the ambient icon color
  /// without plumbing it through the call site — the same contract as the
  /// Material `Icon` widget. Passing [color] explicitly still wins.
  ///
  /// A [Builder] is used when [color] is null so the inherited `IconTheme`
  /// is resolved from a context that actually sits under the theme — not
  /// the context that called [render].
  ///
  /// Decorative icons are excluded from the semantics tree by default —
  /// `SvgPicture` otherwise injects an `img` role node which can disrupt
  /// how ancestor [Semantics] wrappers (e.g. `AppBar.title`'s implicit
  /// `header: true`) merge with sibling text. This matches Material
  /// [Icon]'s behaviour: no [semanticsLabel] → no semantic node. Pass
  /// [semanticsLabel] (or explicitly set [excludeFromSemantics] to false)
  /// for icons that carry meaning on their own.
  /// Stable per-(asset, color) identity key for the rendered [SvgPicture].
  ///
  /// Keying by BOTH the asset path and the resolved color guarantees Flutter's
  /// element reconciler matches an icon element only against another icon of
  /// the SAME asset AND color. Two icons that differ in either dimension get
  /// distinct keys, so the reconciler mounts a fresh `RenderWebVectorGraphic`
  /// instead of recycling one with a retained color-filter layer (cluster:
  /// flutter-web-identifier-transition-stale).
  static ValueKey<String> _identityKey(String assetPath, Color color) =>
      ValueKey<String>('appicon:$assetPath:${color.toARGB32()}');

  static Widget render(
    String assetPath, {
    Color? color,
    double size = 24,
    String? semanticsLabel,
    bool? excludeFromSemantics,
  }) {
    final exclude = excludeFromSemantics ?? (semanticsLabel == null);
    if (color != null) {
      return SvgPicture.asset(
        assetPath,
        // cluster: flutter-web-identifier-transition-stale — a stable
        // identity key keyed on (asset, color) so Flutter's reconciler can
        // never recycle one icon's `RenderWebVectorGraphic` element (with its
        // RETAINED ColorFilterLayer + globally-cached `ui.Picture`) onto a
        // different asset/color slot. On CanvasKit web, vector_graphics'
        // `RenderWebVectorGraphic.assetKey` setter deliberately skips
        // `markNeedsPaint`, so a recycled SVG render object keeps painting the
        // PREVIOUS asset's color-filtered layer at its new offset (the violet
        // nav `plan` glyph leaking into the cardio card header). Distinct keys
        // force a fresh element mount → fresh layer handles → no stale paint.
        key: _identityKey(assetPath, color),
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        semanticsLabel: semanticsLabel,
        excludeFromSemantics: exclude,
      );
    }
    return Builder(
      builder: (context) {
        final resolved = IconTheme.of(context).color ?? const Color(0xFF000000);
        return SvgPicture.asset(
          assetPath,
          // cluster: flutter-web-identifier-transition-stale (see above).
          key: _identityKey(assetPath, resolved),
          width: size,
          height: size,
          colorFilter: ColorFilter.mode(resolved, BlendMode.srcIn),
          semanticsLabel: semanticsLabel,
          excludeFromSemantics: exclude,
        );
      },
    );
  }
}
