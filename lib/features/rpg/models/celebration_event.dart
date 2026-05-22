// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

import 'body_part.dart';
import 'character_class.dart';

part 'celebration_event.freezed.dart';

/// Discriminated union of post-workout celebration events.
///
/// The workout-finish flow (`ActiveWorkoutNotifier._finishOnline`) builds an
/// ordered list of these events from the `record_set_xp` deltas and feeds
/// them into [CelebrationQueue], which applies the cap-at-3 rule and returns
/// the playback order plus an optional overflow payload.
///
/// **Why a sealed class instead of polymorphism via subclassing**: Freezed's
/// `@Freezed` union gives us exhaustive `switch`/`when` ergonomics in the
/// orchestrator and the overlay router — adding a new event type forces a
/// compile error in every consumer until they handle it. That structural
/// guarantee is the point: we do not want a future contributor to add
/// `WeeklyStreakEvent` and silently drop it on the floor at the queue.
@freezed
sealed class CelebrationEvent with _$CelebrationEvent {
  /// A body-part rank threshold was crossed in this workout.
  ///
  /// `newRank` is the post-workout rank value (1–99). `bodyPart` drives both
  /// the rune sigil chosen for the overlay and the tiebreaker in the
  /// celebration queue (highest rank first).
  const factory CelebrationEvent.rankUp({
    required BodyPart bodyPart,
    required int newRank,
  }) = RankUpEvent;

  /// The derived character level rolled over.
  ///
  /// One per workout finish at most — character level is a pure function of
  /// the per-body-part ranks, so the queue collapses multiple body-part rank
  /// crosses into a single character-level event.
  const factory CelebrationEvent.levelUp({required int newLevel}) =
      LevelUpEvent;

  /// A title slug was newly unlocked.
  ///
  /// `slug` is the asset-catalog join key. The half-sheet resolves the
  /// localized name + flavor + sub-label at render time by looking the slug
  /// up against the catalog ([Title]) and pattern-matching on the variant
  /// (body-part / character-level / cross-build).
  ///
  /// **Why slug-only (Phase 18e):** the body-part rank-threshold sub-label
  /// is one of three possible sub-labels — character-level and cross-build
  /// titles use different copy entirely. Carrying only the slug forces the
  /// resolver to consult the catalog, which is the only surface that knows
  /// what shape the metadata has. The pre-18e shape (`slug + bodyPart +
  /// rankThreshold`) silently encoded the body-part assumption.
  const factory CelebrationEvent.titleUnlock({required String slug}) =
      TitleUnlockEvent;

  /// A body part transitioned from "never trained" to "trained" — fires the
  /// 800ms first-awakening compressed overlay.
  ///
  /// Throttled by `ActiveWorkoutNotifier._firstAwakeningFiredThisSession`:
  /// only one fires per workout session even if the user awakens multiple
  /// body parts in one finish. Subsequent body-part awakenings render
  /// silently as a rune-state change on the next character-sheet read.
  const factory CelebrationEvent.firstAwakening({required BodyPart bodyPart}) =
      FirstAwakeningEvent;

  /// The user's derived [CharacterClass] changed between the pre-finish and
  /// post-finish snapshots — fires the 1600ms class-change overlay (BUG-011,
  /// Cluster 3).
  ///
  /// Detection lives in [`CelebrationEventBuilder`] which compares
  /// [`ClassResolver.resolve(pre.ranks)`] against the post-finish equivalent.
  /// Fires on EVERY transition, not just Initiate→first — a Bulwark-to-
  /// Ascendant cross is just as celebration-worthy as the day-1 Initiate→
  /// Bulwark cross.
  ///
  /// **Why both `from` and `to` are payload, not just `to`:** the overlay
  /// shows a small "before: {Initiate}" subtitle on the first non-Initiate
  /// transition (PO call: gives the day-1 user a sense of "you graduated").
  /// Subsequent class crosses suppress the fromClass display since lifters
  /// past Initiate have a stronger sense of identity that the previous-class
  /// line would dilute. Carrying both payload pieces keeps that branch in
  /// the overlay (presentation), not in the event constructor.
  ///
  /// **Cap-at-3 priority:** the celebration queue's reservation policy
  /// gives slot 1 to ClassChangeEvent when present (the rarest event), then
  /// the highest rank-up, then the level-up + title closers. This event
  /// never enters the overflow card — there's only one class change per
  /// finish ever needs to play, and dropping it would silently delete the
  /// rarest progression beat in the entire loop.
  const factory CelebrationEvent.classChange({
    required CharacterClass fromClass,
    required CharacterClass toClass,
  }) = ClassChangeEvent;

  /// A personal record was set during this workout — fires the mid-workout
  /// PR thin-flash (Phase 30 mockup §4½ variant 5) and the post-session
  /// Beat 3 PR cut (PR 30a).
  ///
  /// **Carrier semantics:** the variant intentionally carries pre-resolved
  /// display strings ([exerciseName]) instead of the bare ID. The exercise
  /// object is in scope at the active-workout notifier (where the builder
  /// is invoked); resolving the display name there keeps this event a
  /// pure data carrier and avoids re-fetching the exercises catalog from
  /// the celebration player or the thin-flash widget.
  ///
  /// **Why `exerciseId` instead of `exerciseSlug` (deviation from WIP):**
  /// the [Exercise] model in this codebase exposes `id` (UUID), not
  /// `slug`. Carrying the UUID serves the documented purposes (analytics
  /// keying + future tap-to-exercise navigation) the same way a slug
  /// would — call sites translate id → exercise object the same way
  /// they would translate a slug.
  ///
  /// **Slot policy:** [SlotPolicy.serialize]. The PR flash is the most
  /// viscerally meaningful mid-workout signal a user can experience (it
  /// is the canonical share moment per the post-session mockup); it
  /// holds its own slot in the cap-at-3 visible queue.
  ///
  /// **Emission site (NOT in PR 29.5):** the builder + active-workout
  /// notifier wiring lands in PR 30a/30b. PR 29.5 ships the union variant
  /// + queue policy + thin-flash renderer so the boundary is in place;
  /// the emission path is unblocked without further refactor.
  const factory CelebrationEvent.personalRecord({
    /// The exercise UUID for analytics keying + future post-session
    /// tap-to-exercise navigation.
    required String exerciseId,

    /// Pre-resolved display name (e.g. "Bench Press" / "Supino reto").
    /// Resolved at the call site where the [Exercise] object is in scope
    /// to keep this event a pure data carrier.
    required String exerciseName,

    /// PR weight in kilograms.
    required num weight,

    /// Reps achieved at the PR weight.
    required int reps,

    /// Rep-band classification (e.g. "1-5", "6-12", "13+"). Carried for
    /// the post-session screen's PR-by-band breakdown (PR 30a).
    required String repBand,

    /// Previous best weight for this rep-band, in kilograms. `null` for
    /// first-ever PR in this band.
    num? priorBest,
  }) = PersonalRecordEvent;
}
