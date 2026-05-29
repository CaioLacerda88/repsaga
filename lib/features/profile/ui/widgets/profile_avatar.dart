import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../rpg/domain/body_part_hues.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/character_sheet_state.dart';
import '../../../rpg/providers/character_sheet_provider.dart';
import '../../providers/profile_providers.dart';

/// Circular avatar widget with three render layers, in priority order:
///
///   1. **Uploaded image** — when [avatarUrl] resolves to non-null,
///      renders a [CachedNetworkImage] inside the circle. The monogram is
///      not shown.
///   2. **Dominant-body-part gradient + monogram** — when the user has
///      trained body parts ([dominantBodyPart] non-null OR derived from
///      [characterSheetProvider]), the circle fills with a 45° linear
///      gradient from the body-part hue to [AppColors.hotViolet]; the
///      single-letter monogram (Rajdhani 700, white) overlays.
///   3. **Day-0 radial gradient + monogram** — when the user has no
///      trained body parts yet, the circle fills with a radial gradient
///      ([AppColors.primaryViolet] center → [AppColors.abyss] edge). The
///      structural shift from "diagonal sweep" (trained) to "glowing
///      center" (Day-0) makes the two states immediately distinguishable
///      at a glance.
///
/// **Current-user fallback.** All identity inputs ([displayName],
/// [avatarUrl], [dominantBodyPart]) are optional. When null, the widget
/// reads from `profileProvider` / `characterSheetProvider` for the
/// current user. Pass them explicitly when rendering for a user who is
/// NOT the current session — once a cross-user surface (leaderboard,
/// social) lands, that surface adds a `userId`-scoped provider override
/// at the consumer level rather than threading a `userId` through this
/// widget.
///
/// **No l10n call.** Per `feedback_widget_l10n_parameterization`, this
/// widget does not read `AppLocalizations.of(context)`. The Semantics
/// label is composed from [displayName] / `userEmailProvider` / a literal
/// fallback. Surfaces wanting a localized semantics label pass it via
/// [semanticsLabel].
class ProfileAvatar extends ConsumerWidget {
  const ProfileAvatar({
    super.key,
    this.size = 64,
    this.displayName,
    this.avatarUrl,
    this.dominantBodyPart,
    this.loading = false,
    this.semanticsLabel,
  });

  /// Pixel diameter of the rendered circle. Defaults to 64dp (IdentityCard
  /// register). The monogram glyph scales to `size * 0.4`.
  final double size;

  /// When non-null, the monogram is derived from this name's first letter.
  /// When null, the widget falls back to the current user's profile
  /// display name (via `profileProvider`), then the email prefix.
  final String? displayName;

  /// When non-null, renders the uploaded image instead of the gradient
  /// monogram. The URL should already embed any cache-bust query string
  /// (see `AvatarRepository.uploadAvatar`).
  final String? avatarUrl;

  /// When non-null, used to compute the gradient's body-part hue. When
  /// null, the widget reads the dominant trained body part from
  /// [characterSheetProvider] (current-user path).
  final BodyPart? dominantBodyPart;

  /// When true, overlays a translucent scrim + small spinner on top of
  /// whichever render path is active (uploaded image OR gradient
  /// monogram). Driven by the screen-layer upload orchestrator so the
  /// silent 3-10s upload window has a visible affordance.
  final bool loading;

  /// Optional override for the Semantics label. When null, the widget
  /// composes the label from [displayName] (or current-user fallbacks)
  /// using a fixed English template — call sites needing l10n pass the
  /// pre-localized string here.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolveIdentity(ref);
    // Semantics label: explicit override wins. Otherwise compose a
    // template — Nit 14: when displayLabel collapses to '?' (no
    // displayName + no email), fall back to the bare 'Profile avatar'
    // string so the AOM label is meaningful.
    final String label;
    if (semanticsLabel != null) {
      label = semanticsLabel!;
    } else if (resolved.displayLabel == '?') {
      label = 'Profile avatar';
    } else {
      label = 'Profile avatar for ${resolved.displayLabel}';
    }

    return Semantics(
      label: label,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (resolved.avatarUrl != null)
                CachedNetworkImage(
                  imageUrl: resolved.avatarUrl!,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                  // Fallback to the gradient + monogram while the image
                  // is in-flight, so the avatar never collapses to a
                  // blank disk. The placeholder/error widgets render the
                  // same gradient computed for the non-uploaded path —
                  // visually consistent during the brief network gap.
                  placeholder: (context, _) => _GradientMonogram(
                    size: size,
                    monogram: resolved.monogram,
                    dominantBodyPart: resolved.dominantBodyPart,
                  ),
                  errorWidget: (context, _, _) => _GradientMonogram(
                    size: size,
                    monogram: resolved.monogram,
                    dominantBodyPart: resolved.dominantBodyPart,
                  ),
                )
              else
                _GradientMonogram(
                  size: size,
                  monogram: resolved.monogram,
                  dominantBodyPart: resolved.dominantBodyPart,
                ),
              if (loading) _LoadingScrim(size: size),
            ],
          ),
        ),
      ),
    );
  }

  /// Resolve the three identity inputs to render-ready values: the
  /// monogram glyph, the dominant body part (if any), the avatar URL,
  /// and the display-label string used by Semantics.
  ///
  /// Reads from [profileProvider], [currentUserEmailProvider] and
  /// [characterSheetProvider] when the corresponding constructor param
  /// is null. `AsyncValue.value` is already null-safe for `AsyncLoading`
  /// / `AsyncError`, so the widget's Day-0 path is the natural fallback
  /// when an upstream provider has not resolved yet — no try/catch
  /// needed at this layer (those swallow real bugs).
  _ResolvedIdentity _resolveIdentity(WidgetRef ref) {
    final profile = ref.watch(profileProvider).value;
    final emailFallback = ref.watch(currentUserEmailProvider);

    // displayName fallback chain: explicit param → current profile →
    // email prefix → '?'.
    var name = displayName;
    if (name == null || name.isEmpty) {
      if (profile?.displayName != null && profile!.displayName!.isNotEmpty) {
        name = profile.displayName;
      }
    }

    final monogram = _monogramFrom(name, emailFallback);
    final displayLabel = name ?? emailFallback ?? '?';

    // dominantBodyPart fallback: explicit param → derived from the
    // character sheet's highest-ranked trained entry. Day-0 (no
    // trained body parts, OR sheet provider still loading) returns null
    // and the gradient falls to the abyss → primaryViolet pair.
    var bp = dominantBodyPart;
    if (bp == null) {
      final sheet = ref.watch(characterSheetProvider).value;
      if (sheet != null) {
        bp = _dominantTrainedFor(sheet);
      }
    }

    // avatarUrl fallback: explicit param → profile row.
    final url = avatarUrl ?? profile?.avatarUrl;

    return _ResolvedIdentity(
      monogram: monogram,
      displayLabel: displayLabel,
      dominantBodyPart: bp,
      avatarUrl: url,
    );
  }

  /// Highest-ranked trained entry from a [CharacterSheetState] — mirrors
  /// `_dominantTrainedEntry` in `character_card.dart` so both surfaces
  /// resolve identically. Tie-break by `activeBodyParts` canonical order,
  /// returns null on day-0 (no trained body parts).
  static BodyPart? _dominantTrainedFor(CharacterSheetState sheet) {
    BodyPart? best;
    int bestRank = 0;
    for (final entry in sheet.bodyPartProgress) {
      if (entry.isUntrained) continue;
      if (best == null || entry.rank > bestRank) {
        best = entry.bodyPart;
        bestRank = entry.rank;
      }
    }
    return best;
  }

  /// Single-letter monogram derived from the fallback chain. Always
  /// uppercase, always non-empty (falls through to '?').
  static String _monogramFrom(String? name, String? email) {
    if (name != null && name.isNotEmpty) return name[0].toUpperCase();
    if (email != null && email.isNotEmpty) return email[0].toUpperCase();
    return '?';
  }
}

/// Resolved identity passed to the gradient + monogram leaf widget.
class _ResolvedIdentity {
  const _ResolvedIdentity({
    required this.monogram,
    required this.displayLabel,
    required this.dominantBodyPart,
    required this.avatarUrl,
  });

  final String monogram;
  final String displayLabel;
  final BodyPart? dominantBodyPart;
  final String? avatarUrl;
}

/// Inner leaf — renders the gradient disc + centered monogram. Public to
/// the file so the [CachedNetworkImage] placeholder/error builders can
/// reuse the exact same shape during the network gap.
class _GradientMonogram extends StatelessWidget {
  const _GradientMonogram({
    required this.size,
    required this.monogram,
    required this.dominantBodyPart,
  });

  final double size;
  final String monogram;
  final BodyPart? dominantBodyPart;

  @override
  Widget build(BuildContext context) {
    final isDay0 = dominantBodyPart == null;
    // Day-0 path uses a RadialGradient so the disc reads as a glowing
    // brand orb instead of a flat dark linear sweep (linear
    // `abyss → primaryViolet` rendered as a near-uniform dark purple at
    // 64dp, indistinguishable from a flat fill). Trained path keeps the
    // diagonal LinearGradient — the body-part hue has enough chroma that
    // the diagonal sweep reads clearly.
    final Gradient gradient = isDay0
        ? const RadialGradient(
            center: Alignment.center,
            radius: 0.6,
            colors: [AppColors.primaryViolet, AppColors.abyss],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              BodyPartHues.hueFor(dominantBodyPart!),
              AppColors.hotViolet,
            ],
          );

    return DecoratedBox(
      decoration: BoxDecoration(shape: BoxShape.circle, gradient: gradient),
      child: Center(
        child: Text(
          monogram,
          // Rajdhani 700 monogram — `headline` is Rajdhani 600/24dp, the
          // closest bundled style. `copyWith` forces the weight to 700
          // (also bundled) and scales the font-size to 40% of the avatar
          // size so the glyph visually centers in the disc regardless of
          // the configured [size] (64dp default → 25.6 sp monogram).
          style: AppTextStyles.headline.copyWith(
            color: AppColors.textCream,
            fontSize: size * 0.4,
            fontWeight: FontWeight.w700,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}

/// Translucent scrim + small spinner overlaid on top of the avatar while
/// the screen-layer upload orchestrator is in flight. Sized to the same
/// circular bounds as the avatar so the loading affordance reads as "this
/// disc is busy" instead of an unrelated overlay.
class _LoadingScrim extends StatelessWidget {
  const _LoadingScrim({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    // 20dp indicator matches the in-button spinner register used by the
    // AvatarCropSheet — visually consistent across the upload flow.
    final indicator = size >= 48 ? 20.0 : size * 0.4;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.abyss.withValues(alpha: 0.55),
      ),
      child: Center(
        child: SizedBox(
          width: indicator,
          height: indicator,
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.hotViolet,
          ),
        ),
      ),
    );
  }
}
