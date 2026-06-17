import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/class_resolver.dart';
import '../models/body_part.dart';
import '../models/character_class.dart';
import 'rpg_progress_provider.dart';

/// Currently-derived [CharacterClass] for the authenticated user.
///
/// Watches [rpgProgressProvider], projects the per-body-part rank map onto
/// [strengthBodyParts] (cardio excluded — cardio is recognised via cardio
/// titles, not a class), and returns the resolver result via
/// [ClassResolver.resolve]. The resolver is pure, so this
/// provider rebuilds in lockstep with the upstream snapshot — there is no
/// secondary state to invalidate.
///
/// **Returns the [CharacterClass] enum, not a localized string.** UI consumers
/// (the [`ClassBadge`](../ui/widgets/class_badge.dart)) resolve the localized
/// label via `AppLocalizations` keyed by [CharacterClass.l10nKey]
/// (`class_initiate`, `class_berserker`, …). Keeping the provider l10n-free
/// means the badge stays correct under locale switches and golden tests can
/// assert against the slug without wiring an `AppLocalizations` mock.
///
/// **Loading / error states:**
///   * `AsyncLoading` → `null` (badge renders the day-1 placeholder copy).
///   * `AsyncData` → resolved class (always non-null; resolver returns
///     `Initiate` for the day-0 distribution).
///   * `AsyncError` → `null` (graceful: badge falls back to placeholder
///     rather than blocking the character sheet on a network blip).
///
/// **Day-1 surface contract.** A brand-new user with no `body_part_progress`
/// rows lands here with every rank at 1 (via [RpgProgressSnapshot.progressFor]
/// fallback). The resolver returns [CharacterClass.initiate] for that
/// distribution — the badge thus transitions from "The iron will name you."
/// (loading) → "Initiate" (data) on the first frame after auth resolves.
final characterClassProvider = Provider<CharacterClass?>((ref) {
  final progressAsync = ref.watch(rpgProgressProvider);
  return progressAsync.when(
    data: (snapshot) {
      final ranks = <BodyPart, int>{
        for (final bp in strengthBodyParts) bp: snapshot.progressFor(bp).rank,
      };
      return ClassResolver.resolve(ranks);
    },
    loading: () => null,
    error: (_, _) => null,
  );
});
