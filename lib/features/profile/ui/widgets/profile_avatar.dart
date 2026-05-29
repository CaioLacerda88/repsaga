import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../rpg/domain/body_part_hues.dart';
import '../../../rpg/models/body_part.dart';
import '../../../rpg/models/character_sheet_state.dart';
import '../../../rpg/providers/character_sheet_provider.dart';
import '../../models/profile.dart';
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
///   3. **Day-0 gradient + monogram** — when the user has no trained body
///      parts yet, the gradient falls to [AppColors.abyss] →
///      [AppColors.primaryViolet]. Visually distinct enough to read as
///      "no trained path yet" without dropping the user into a blank state.
///
/// **Future-proof constructor.** All identity inputs ([displayName],
/// [avatarUrl], [dominantBodyPart], [userId]) are optional. When null,
/// the widget reads from `userProfileProvider` / `characterSheetProvider`
/// for the current user. Pass them explicitly when rendering for a user
/// who is NOT the current session — e.g. a future leaderboard row.
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
    this.userId,
    this.semanticsLabel,
  });

  /// Pixel diameter of the rendered circle. Defaults to 64dp (IdentityCard
  /// register). The monogram glyph scales to `size * 0.4`.
  final double size;

  /// When non-null, the monogram is derived from this name's first letter.
  /// When null, the widget falls back to the current user's profile
  /// display name (via `userProfileProvider`), then the email prefix.
  final String? displayName;

  /// When non-null, renders the uploaded image instead of the gradient
  /// monogram. The URL should already embed any cache-bust query string
  /// (see `AvatarRepository.uploadAvatar`).
  final String? avatarUrl;

  /// When non-null, used to compute the gradient's body-part hue. When
  /// null, the widget reads the dominant trained body part from
  /// [characterSheetProvider] (current-user path).
  final BodyPart? dominantBodyPart;

  /// Reserved for future cross-user surfaces (leaderboard, social).
  /// Currently unused by the render path — every read goes through the
  /// current-user providers when [displayName] / [avatarUrl] /
  /// [dominantBodyPart] are null. Wired into the constructor so the
  /// signature is forward-compatible without re-architecting.
  final String? userId;

  /// Optional override for the Semantics label. When null, the widget
  /// composes the label from [displayName] (or current-user fallbacks)
  /// using a fixed English template — call sites needing l10n pass the
  /// pre-localized string here.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolveIdentity(ref);
    final label =
        semanticsLabel ?? 'Profile avatar for ${resolved.displayLabel}';

    return Semantics(
      label: label,
      image: true,
      child: SizedBox(
        width: size,
        height: size,
        child: ClipOval(
          child: resolved.avatarUrl != null
              ? CachedNetworkImage(
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
              : _GradientMonogram(
                  size: size,
                  monogram: resolved.monogram,
                  dominantBodyPart: resolved.dominantBodyPart,
                ),
        ),
      ),
    );
  }

  /// Resolve the four identity inputs to render-ready values: the
  /// monogram glyph, the dominant body part (if any), the avatar URL,
  /// and the display-label string used by Semantics.
  ///
  /// All provider reads degrade defensively: a loading / error
  /// [AsyncValue] short-circuits to the explicit-param value (or null
  /// → Day-0 path). This makes the widget pump-safe in any harness
  /// where upstream providers are not stubbed.
  _ResolvedIdentity _resolveIdentity(WidgetRef ref) {
    final profile = _safeWatchProfile(ref);
    final emailFallback = _safeReadEmail(ref);

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
    // trained body parts) returns null and the gradient falls to the
    // abyss → primaryViolet pair.
    var bp = dominantBodyPart;
    if (bp == null) {
      final sheet = _safeWatchCharacterSheet(ref);
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

  /// Watch [profileProvider] defensively — a provider in error state
  /// (common in widget tests that don't stub it) short-circuits to
  /// null instead of bubbling a `ProviderException` through every
  /// ancestor rebuild.
  static Profile? _safeWatchProfile(WidgetRef ref) {
    try {
      return ref.watch(profileProvider).value;
    } catch (_) {
      return null;
    }
  }

  /// Read [currentUserEmailProvider] defensively.
  static String? _safeReadEmail(WidgetRef ref) {
    try {
      return ref.read(currentUserEmailProvider);
    } catch (_) {
      return null;
    }
  }

  /// Watch [characterSheetProvider] defensively. The sheet's upstream
  /// providers (rpg progress, active title, class) can be in
  /// `AsyncError` when tests pump the screen without stubbing them —
  /// we want the avatar to render the Day-0 gradient in that case,
  /// not crash the whole screen.
  static CharacterSheetState? _safeWatchCharacterSheet(WidgetRef ref) {
    try {
      return ref.watch(characterSheetProvider).value;
    } catch (_) {
      return null;
    }
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
    final colors = _gradientColorsFor(dominantBodyPart);

    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ),
      ),
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

  /// Two-stop gradient pair for the disc.
  ///
  /// **Day-0 path (`dominantBodyPart == null`):** `abyss → primaryViolet`.
  /// Reads as a deep brand void with a violet rise — distinct from the
  /// trained-path gradient and intentionally lower contrast so the call
  /// to action ("upload an avatar to claim your face") is implicit.
  ///
  /// **Trained path:** `bodyPartHue → hotViolet`. The hue identifies the
  /// user's dominant trained body part; the second stop lands on the
  /// brand violet so every trained variant shares the same end-state and
  /// the body-part identity remains the leading hue.
  static List<Color> _gradientColorsFor(BodyPart? bp) {
    if (bp == null) {
      return const [AppColors.abyss, AppColors.primaryViolet];
    }
    return [BodyPartHues.hueFor(bp), AppColors.hotViolet];
  }
}
