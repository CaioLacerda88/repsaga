import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../l10n/app_localizations.dart';
import '../../models/character_class.dart';
import '../widgets/class_localization.dart';

/// Class-change celebration overlay (BUG-011, Cluster 3).
///
/// Fires once per class transition the user crosses on a workout finish:
///   * Day-1 Initiate → first earned class (Bulwark / Sentinel / etc.)
///   * Mid-saga class flips (Bulwark → Sentinel when back overtakes chest)
///   * The rare Ascendant cross (every track within 30% spread above floor)
///
/// **Why a 1600ms timeline (rank-up is 1100ms):** the critic and PO call
/// (2026-05-02) locked class-change at a slower pace because it's the
/// rarest beat in the loop — typically once per ~3 months for an active
/// lifter. Burning 1100ms on a per-week rank-up but compressing the
/// per-quarter class change into the same window flattens the celebration
/// hierarchy. The extra 500ms is spent on the headline beat (700-1000ms,
/// border-color cross-fade + class name letter-by-letter).
///
/// **Choreography (locked, see WIP §Cluster 3 BUG-011 overlay):**
///
///   * 0-300ms — backdrop fades in to abyss @ 0.85 (heavier than rank-up's
///     0.72 because class-change is more identity-defining); sigil
///     silhouette renders centered at 120dp with `textDim @ 0.2`,
///     asymmetric corners from [`ClassBadge._sigilRadius`].
///   * 300-700ms — sigil border traces itself counter-clockwise via the
///     [_BorderTracePainter] (CustomPainter + PathMetric.extractPath at
///     a fractional length). Border color tweens `textDim → primaryViolet`.
///   * 700-1000ms — border `primaryViolet → hotViolet`; fill opacity
///     `0 → 0.18` (matches `ClassBadgeStyle.earnedFillAlpha`); class name
///     materializes letter-by-letter (Rajdhani 700 36sp uppercase, 0.06em
///     tracking, FittedBox guard against long pt-BR strings).
///   * 1000-1400ms — outer hotViolet glow expands (BoxShadow blur 0→32,
///     spread 0→8). **CRITICAL: NO heroGold.** Rank-up uses heroGold at
///     its 200-500ms peak; class-up is violet-only end-to-end. That is
///     the differentiator between the two overlays.
///   * 1400-1600ms — subtitle ("Sua jornada ganhou um nome.") fades in
///     beneath the class name in Inter 14sp textDim. On Initiate→first
///     transition, a small "antes: Iniciante" line appears further below.
///
/// **Haptic:** double-pulse at t=700ms — `HapticFeedback.heavyImpact()`,
/// then 80ms pause, then `HapticFeedback.mediumImpact()`. The double-pulse
/// is intentionally heavier than rank-up's single `mediumImpact` to mark
/// the rarity. Idempotent via boolean flag (one-fire structural guarantee).
///
/// **No skip:** force the full 1600ms. The overlay never installs a tap
/// handler — auto-dismissed by the celebration player after the timeline
/// elapses (the player schedules pop based on [overlayHold] which is
/// 1600ms for this overlay; see celebration_player.dart routing).
class ClassChangeOverlay extends StatefulWidget {
  const ClassChangeOverlay({
    super.key,
    required this.fromClass,
    required this.toClass,
  });

  /// The class the user held BEFORE the workout. Used to render the
  /// "before: {className}" subtitle when the transition is from
  /// [CharacterClass.initiate]; suppressed for non-Initiate transitions
  /// per PO call (lifters past Initiate don't need to be reminded what
  /// they were).
  final CharacterClass fromClass;

  /// The class the user holds AFTER the workout. Headline of the overlay.
  final CharacterClass toClass;

  /// Total duration of the choreography. Public so the celebration player
  /// can schedule its auto-pop against the same canonical value rather
  /// than redeclaring the magic number.
  static const Duration totalDuration = Duration(milliseconds: 1600);

  @override
  State<ClassChangeOverlay> createState() => _ClassChangeOverlayState();
}

class _ClassChangeOverlayState extends State<ClassChangeOverlay>
    with TickerProviderStateMixin {
  /// Master timeline driving every stage of the choreography.
  late final AnimationController _timeline;

  // Stage-specific tweens. Each is a CurvedAnimation over an Interval so
  // we can read the eased value directly inside the AnimatedBuilder rather
  // than mid-frame `t < ms` branching (matches the rank-up pattern).
  late final Animation<double> _backdrop; // 0-300ms
  late final Animation<double> _silhouette; // 0-300ms (sigil placeholder)
  late final Animation<double> _borderTrace; // 300-700ms (0 → 1)
  late final Animation<Color?>
  _borderColorEarly; // 300-700ms (textDim → violet)
  late final Animation<Color?> _borderColorLate; // 700-1000ms (violet → hotV)
  late final Animation<double> _fillAlpha; // 700-1000ms
  late final Animation<double> _nameReveal; // 700-1000ms (letter-by-letter)
  late final Animation<double> _glowBlur; // 1000-1400ms
  late final Animation<double> _glowSpread; // 1000-1400ms
  late final Animation<double> _subtitle; // 1400-1600ms

  /// Structural one-fire guards for the 700/780ms double-pulse haptic.
  /// The timeline listener fires per frame; without these we'd haptic on
  /// every tick past the marker. Two booleans (one per pulse) so the
  /// second pulse can wait its turn without a side-channel timer that
  /// would leak under `testWidgets` fake-async.
  bool _heavyPulseFired = false;
  bool _mediumPulseFired = false;

  @override
  void initState() {
    super.initState();
    _timeline = AnimationController(
      vsync: this,
      duration: ClassChangeOverlay.totalDuration,
    );
    const total = 1600;

    _backdrop = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(0, 300 / total, curve: Curves.easeOut),
    );
    _silhouette = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(0, 300 / total, curve: Curves.easeIn),
    );

    // 300-700ms: border traces itself + tween color textDim → primaryViolet.
    _borderTrace = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(300 / total, 700 / total, curve: Curves.easeInOut),
    );
    // Cluster-3 review (2026-05-02): the 300-700ms border trace is the
    // longest visual beat; linear interpolation read as mechanical. easeOut
    // gives the last 30% a deceleration that lets the color "land" on
    // primaryViolet rather than snapping to it.
    _borderColorEarly =
        ColorTween(
          begin: AppColors.textDim.withValues(alpha: 0.2),
          end: AppColors.primaryViolet,
        ).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: const Interval(
              300 / total,
              700 / total,
              curve: Curves.easeOut,
            ),
          ),
        );

    // 700-1000ms: border primaryViolet → hotViolet; fill 0 → 0.18; name
    // materialises letter-by-letter via the _nameReveal value (0..1).
    _borderColorLate =
        ColorTween(
          begin: AppColors.primaryViolet,
          end: AppColors.hotViolet,
        ).animate(
          CurvedAnimation(
            parent: _timeline,
            curve: const Interval(
              700 / total,
              1000 / total,
              curve: Curves.easeOut,
            ),
          ),
        );
    _fillAlpha = Tween<double>(begin: 0, end: 0.18).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(700 / total, 1000 / total, curve: Curves.easeIn),
      ),
    );
    _nameReveal = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(700 / total, 1000 / total, curve: Curves.easeOut),
    );

    // 1000-1400ms: hotViolet outer glow grows.
    _glowBlur = Tween<double>(begin: 0, end: 32).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(
          1000 / total,
          1400 / total,
          curve: Curves.easeOut,
        ),
      ),
    );
    _glowSpread = Tween<double>(begin: 0, end: 8).animate(
      CurvedAnimation(
        parent: _timeline,
        curve: const Interval(
          1000 / total,
          1400 / total,
          curve: Curves.easeOut,
        ),
      ),
    );

    // 1400-1600ms: subtitle fade-in.
    _subtitle = CurvedAnimation(
      parent: _timeline,
      curve: const Interval(1400 / total, 1.0, curve: Curves.easeIn),
    );

    _timeline.addListener(_onTick);
    _timeline.forward();
  }

  void _onTick() {
    // Double-pulse haptic: heavyImpact at t=700ms (peak headline reveal),
    // mediumImpact at t=780ms (80ms gap reads as "thump-thump"). Both
    // pulses are scheduled off the SAME timeline rather than via a
    // side-channel `Future.delayed`, because:
    //   1. `unawaited(Future.delayed(...))` leaks under `testWidgets`
    //      fake-async — every Timer the test zone tracks must be
    //      explicitly resolved by [WidgetTester.pump], which we can't
    //      enforce here.
    //   2. Pinning both pulses to the controller value gives us a
    //      structural one-fire guarantee: each pulse fires the FIRST
    //      tick after the threshold and never again, no boolean flag
    //      can race the listener.
    final ms = _timeline.value * 1600;
    if (!_heavyPulseFired && ms >= 700) {
      _heavyPulseFired = true;
      HapticFeedback.heavyImpact();
    }
    if (!_mediumPulseFired && ms >= 780) {
      _mediumPulseFired = true;
      HapticFeedback.mediumImpact();
    }
  }

  @override
  void dispose() {
    _timeline.removeListener(_onTick);
    _timeline.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final toCopy = localizedClassCopy(widget.toClass, l10n);
    final fromCopy = localizedClassCopy(widget.fromClass, l10n);
    final showFromLabel = widget.fromClass == CharacterClass.initiate;

    return AnimatedBuilder(
      animation: _timeline,
      builder: (context, _) {
        // Border color is whichever stage owns the moment: textDim/violet
        // tween for 300-700ms, then violet/hotViolet for 700-1000ms+.
        final t = _timeline.value * 1600;
        final Color borderColor;
        if (t < 700) {
          borderColor =
              _borderColorEarly.value ??
              AppColors.textDim.withValues(alpha: 0.2);
        } else {
          borderColor = _borderColorLate.value ?? AppColors.hotViolet;
        }

        return Stack(
          alignment: Alignment.center,
          children: [
            // Backdrop dim — abyss @ 0.85, fades in over 0-300ms.
            Positioned.fill(
              child: IgnorePointer(
                child: ColoredBox(
                  color: AppColors.abyss.withValues(
                    alpha: 0.85 * _backdrop.value,
                  ),
                ),
              ),
            ),
            // The sigil + name + subtitle stack. Semantics identifier lets
            // Playwright detect the overlay.
            Semantics(
              identifier: 'class-change-overlay',
              container: true,
              label: toCopy.name,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ClassSigil(
                      borderColor: borderColor,
                      fillColor: AppColors.primaryViolet.withValues(
                        alpha: _fillAlpha.value,
                      ),
                      glowBlur: _glowBlur.value,
                      glowSpread: _glowSpread.value,
                      borderTraceProgress: _borderTrace.value,
                      silhouetteOpacity: _silhouette.value,
                    ),
                    const SizedBox(height: 28),
                    // Headline (class name + tagline). The class name uses
                    // a letter-reveal driven by [_nameReveal]; the tagline
                    // appears alongside the subtitle at 1400-1600ms.
                    _ClassHeadline(
                      className: toCopy.name,
                      tagline: toCopy.tagline,
                      revealProgress: _nameReveal.value,
                      subtitleProgress: _subtitle.value,
                    ),
                    const SizedBox(height: 16),
                    // Subtitle line — Inter 14sp textDim, fades in
                    // 1400-1600ms with the tagline.
                    Semantics(
                      identifier: 'class-change-subtitle',
                      child: Opacity(
                        opacity: _subtitle.value,
                        child: Text(
                          l10n.classChangeOverlaySubtitle,
                          textAlign: TextAlign.center,
                          style: AppTextStyles.body.copyWith(
                            fontSize: 14,
                            color: AppColors.textDim,
                          ),
                        ),
                      ),
                    ),
                    // "before: Iniciante" — only on Initiate→first
                    // transition. Lowercase reads as a footnote.
                    if (showFromLabel) ...[
                      const SizedBox(height: 8),
                      Semantics(
                        identifier: 'class-change-previous-label',
                        child: Opacity(
                          opacity: _subtitle.value,
                          child: Text(
                            l10n.classChangePreviousLabel(fromCopy.name),
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodySmall.copyWith(
                              color: AppColors.textDim.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 120dp sigil panel with the asymmetric class-badge corners + animated
/// stroke-drawn border.
///
/// Pulled out of the parent build so the AnimatedBuilder doesn't have to
/// re-allocate the BoxDecoration on every frame; the inner CustomPaint
/// repaints from the [borderTraceProgress] + [borderColor] inputs.
class _ClassSigil extends StatelessWidget {
  const _ClassSigil({
    required this.borderColor,
    required this.fillColor,
    required this.glowBlur,
    required this.glowSpread,
    required this.borderTraceProgress,
    required this.silhouetteOpacity,
  });

  final Color borderColor;
  final Color fillColor;
  final double glowBlur;
  final double glowSpread;

  /// 0..1 — fraction of the border path drawn so far.
  final double borderTraceProgress;

  /// Silhouette opacity for the 0-300ms placeholder beat. Uses textDim @
  /// 0.2 max; modulated by this fade-in alpha.
  final double silhouetteOpacity;

  /// Asymmetric "struck faction mark" corner radius — must mirror
  /// [`ClassBadge._sigilRadius`] exactly so the overlay reads as a
  /// scaled-up sibling of the badge.
  static const _sigilRadius = BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(10),
    bottomLeft: Radius.circular(10),
    bottomRight: Radius.circular(4),
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: _sigilRadius,
        // Outer hotViolet glow — only renders past 1000ms when glowBlur > 0.
        // Conditionally skipping the BoxShadow when blur is zero saves a
        // pointless painter pass on the early frames.
        boxShadow: glowBlur > 0
            ? [
                BoxShadow(
                  color: AppColors.hotViolet.withValues(alpha: 0.45),
                  blurRadius: glowBlur,
                  spreadRadius: glowSpread,
                ),
              ]
            : null,
      ),
      child: Stack(
        children: [
          // Silhouette placeholder — visible from t=0; sits underneath the
          // animated border so the empty-frame state still reads as a sigil.
          Opacity(
            opacity: 0.2 * silhouetteOpacity,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.textDim,
                borderRadius: _sigilRadius,
              ),
            ),
          ),
          // Border trace — CustomPaint owns the partial-stroke render.
          Positioned.fill(
            child: CustomPaint(
              painter: _BorderTracePainter(
                color: borderColor,
                progress: borderTraceProgress,
                radius: _sigilRadius,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Stroke-drawing painter for the [_ClassSigil] border.
///
/// Builds the rounded-rect path once, then uses [PathMetric.extractPath]
/// to grab the leading [progress] fraction of the perimeter. Asymmetric
/// corners from [BorderRadius.only] are stroke-traceable — the underlying
/// path is a single closed RRect path regardless of corner symmetry, and
/// `PathMetrics.first.length` gives a usable total perimeter for the
/// fractional extract.
///
/// **Why not an `AnimatedContainer` border:** Material's BorderSide draws
/// the entire perimeter at every alpha. There's no built-in API to draw
/// "the first 60% of an asymmetric rounded rectangle." `PathMetric` is
/// the standard Flutter idiom for this — same pattern as `dashed_line`
/// implementations.
class _BorderTracePainter extends CustomPainter {
  _BorderTracePainter({
    required this.color,
    required this.progress,
    required this.radius,
  });

  final Color color;
  final double progress; // 0..1
  final BorderRadius radius;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    final rect = Offset.zero & size;
    final rrect = radius.toRRect(rect);
    final fullPath = Path()..addRRect(rrect);
    final metrics = fullPath.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    if (progress >= 1.0) {
      // Past 1.0 means the border is fully drawn — paint the whole RRect
      // as a single stroke to avoid floating-point artifacts at the seam
      // where the extracted path closes back on itself.
      canvas.drawPath(fullPath, paint);
      return;
    }
    for (final metric in metrics) {
      final extract = metric.extractPath(0, metric.length * progress);
      canvas.drawPath(extract, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _BorderTracePainter old) {
    return old.color != color ||
        old.progress != progress ||
        old.radius != radius;
  }
}

/// Headline composition: class name (Rajdhani 700 36sp uppercase, letter
/// reveal) + tagline (Inter italic 14sp textDim, fade-in with subtitle).
///
/// The letter reveal is a per-character opacity stagger driven by
/// [revealProgress]. Earlier revisions used a `ClipRect` wipe that grew
/// `width=0 → width=size.width`, but for long pt-BR class names like
/// "DESBRAVADOR" (11 chars) or "ASCENDENTE" (10 chars) the wipe cut
/// mid-glyph and showed half-rendered letters during the 700-1000ms beat.
/// Per-character opacity gating fades each glyph in one-at-a-time across
/// the same window — visually crisper and works against any font without
/// measuring glyph advance widths.
class _ClassHeadline extends StatelessWidget {
  const _ClassHeadline({
    required this.className,
    required this.tagline,
    required this.revealProgress,
    required this.subtitleProgress,
  });

  final String className;
  final String tagline;

  /// 0..1 — fraction of the class name revealed so far. Drives the
  /// per-character stagger: char `i` of `n` becomes fully opaque once
  /// `revealProgress >= (i + 1) / n`, with a 1/n width per-character
  /// linear ramp so adjacent letters cross-fade rather than pop.
  final double revealProgress;

  /// 0..1 — opacity of the tagline (rides on the same timing as the
  /// subtitle).
  final double subtitleProgress;

  @override
  Widget build(BuildContext context) {
    // Use [String.characters] (grapheme clusters) so accented letters in
    // pt-BR class names render as one unit rather than splitting at
    // combining-mark boundaries. `ASCENDENTE` is plain ASCII today, but
    // `IRMÃO`-style strings would break with `split('')`.
    final chars = className.toUpperCase().characters.toList(growable: false);
    final charCount = chars.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // FittedBox guards against long pt-BR strings ("Desbravador" runs
        // longer than "Pathfinder"). The type scales down rather than
        // wrapping — the choreography reads cleaner with a single line.
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Semantics(
            identifier: 'class-change-name-label',
            label: className,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < charCount; i++)
                  Opacity(
                    opacity: _glyphOpacity(
                      index: i,
                      total: charCount,
                      progress: revealProgress,
                    ),
                    child: Text(
                      chars[i],
                      textAlign: TextAlign.center,
                      style: _ClassChangeHeadlineStyle.headline,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Opacity(
          opacity: subtitleProgress,
          child: Text(
            tagline,
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(
              fontSize: 14,
              color: AppColors.textDim,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      ],
    );
  }

  /// Per-glyph opacity for the staggered reveal.
  ///
  /// Each glyph owns a `1/total` slice of [progress] (0..1). Within its
  /// slice the opacity ramps linearly 0..1 so adjacent glyphs cross-fade
  /// rather than pop. After its slice ends the glyph stays fully opaque.
  ///
  /// Pulled out as a static helper so the reveal math is unit-testable
  /// without mounting the overlay (and so a future glyph-curve change —
  /// e.g. easeIn per glyph — has a single edit point).
  static double _glyphOpacity({
    required int index,
    required int total,
    required double progress,
  }) {
    if (total <= 0) return 1;
    final slice = 1.0 / total;
    final start = index * slice;
    final end = start + slice;
    if (progress <= start) return 0;
    if (progress >= end) return 1;
    return ((progress - start) / slice).clamp(0.0, 1.0);
  }
}

/// Local typography token — the class-change name uses a 36sp Rajdhani 700
/// face for the 1600ms class-change moment.
///
/// **Naming history:** the class was previously named `GoogleFontsRajdhani`
/// even though it never used the `google_fonts` package; it just stamped a
/// `AppTextStyles.headline.copyWith(...)`. Phase 28a renamed to
/// `_ClassChangeHeadlineStyle` (private) so future grep doesn't suggest a
/// google_fonts dependency that doesn't exist.
///
/// **Why not the global [AppTextStyles.celebrationSize] token directly:**
/// the class-change moment uses 0.06em tracking (`letterSpacing: 0.06 *
/// 36 = 2.16`) which is HEAVIER than the 0.04em tracking carried by
/// [AppTextStyles.display] (and therefore by `celebrationSize`). The
/// per-glyph letter-reveal choreography was tuned against that wider
/// tracking — a tighter 0.04em packs the glyphs too close during the
/// 700-1000ms reveal beat. We compose: route through `celebrationSize(36)`
/// for the base register (Rajdhani 700 36sp height 1.0) then override the
/// tracking on top, so the celebration-tier identity is shared but the
/// per-beat tuning is preserved.
class _ClassChangeHeadlineStyle {
  const _ClassChangeHeadlineStyle._();

  /// Rajdhani 700 36sp uppercase, 0.06em tracking.
  static TextStyle get headline =>
      AppTextStyles.celebrationSize(36).copyWith(letterSpacing: 0.06 * 36);
}
