import '../models/celebration_event.dart';

/// Per-variant slot policy attached to each [CelebrationEvent].
///
/// The policy names what [CelebrationQueue.build] already does today on a
/// per-variant basis; promoting it to a first-class enum (rather than
/// implicit conditionals scattered across the builder) means:
///
///   1. Future variants added to the sealed union have to make an explicit
///      choice via the exhaustive [slotPolicyFor] switch — Dart fails the
///      compile if a new variant is added without a slot decision.
///   2. The mid-workout thin-flash overlay dispatch (PR 29.5) and the
///      eventual post-session screen state machine (PR 30a) both read
///      against the same policy without re-implementing the precedence
///      rules.
///   3. The behavior is unit-test-pinned per variant; refactors to the
///      queue body can't silently demote a `serialize` variant to `drop`
///      without failing the policy test.
///
/// Semantics:
///   * [serialize] — the event holds its own slot. If multiple slots are
///     available the variant fills them in canonical order.
///   * [coalesce] — the event collapses into a summary surface when the
///     visible cap is exceeded. The current implementation surfaces this
///     for rank-up overflow only (cap-trimmed rank-ups condense into the
///     overflow card flipbook). It is the queue's overflow strategy, not
///     a per-event policy; no event currently carries [coalesce] as its
///     own policy. The enum still names it because the post-session
///     screen's elevated rank-up "fusion" beat (PR 30a) will read against
///     this name when computing whether to coalesce ≥3 simultaneous
///     body-part rank-ups into a cascade grid.
///   * [drop] — silently absorbed when no slot is available; not surfaced
///     to the user during this finish. Used only for level-up because the
///     character level is a pure function of body-part ranks and is
///     always re-derivable on the saga screen — dropping it costs less
///     narrative continuity than any other variant.
enum SlotPolicy { serialize, coalesce, drop }

/// Returns the [SlotPolicy] for a given [CelebrationEvent] variant.
///
/// Exhaustive — adding a new variant to the [CelebrationEvent] union
/// without extending this switch is a compile error.
SlotPolicy slotPolicyFor(CelebrationEvent event) {
  return switch (event) {
    // First-awakening narratively precedes the body-part's first rank-up
    // and is session-throttled upstream; never dropped.
    FirstAwakeningEvent() => SlotPolicy.serialize,
    // Class change is the rarest progression beat in the entire loop
    // (≈ once per quarter for an active lifter). Slot 1 reserved.
    ClassChangeEvent() => SlotPolicy.serialize,
    // Top rank-up reserved (BUG-013); spillover rank-ups also serialize.
    // Beyond cap-at-3, the queue's overflow strategy coalesces remaining
    // rank-ups into the overflow card — but the per-event policy is
    // serialize. coalesce is a queue-level fallback, not the event's
    // intrinsic policy.
    RankUpEvent() => SlotPolicy.serialize,
    // Title is the crown (BUG-017) — beats level-up in the closer slot.
    TitleUnlockEvent() => SlotPolicy.serialize,
    // PR flash is the most viscerally meaningful mid-workout signal
    // (canonical share moment per the post-session mockup); reserved
    // in the cap-at-3 queue.
    PersonalRecordEvent() => SlotPolicy.serialize,
    // Character level is a pure function of body-part ranks; the saga
    // screen always re-derives it. Dropping it costs less narrative
    // continuity than dropping any other variant.
    LevelUpEvent() => SlotPolicy.drop,
  };
}

/// Result of [CelebrationQueue.build] — the ordered playback list plus an
/// optional overflow card payload when the cap-at-3 rule trims rank-ups.
class CelebrationQueueResult {
  const CelebrationQueueResult({required this.queue, this.overflow});

  /// Ordered events to render. Length is at most 3 + (number of
  /// first-awakening events). First-awakening events bypass the cap because
  /// they are themselves session-throttled upstream (see
  /// `ActiveWorkoutNotifier._firstAwakeningFiredThisSession`) — at most one
  /// per workout.
  final List<CelebrationEvent> queue;

  /// Non-null when the cap-at-3 rule dropped one or more rank-ups. The UI
  /// renders a non-modal "{N} more rank-ups — open Saga" card after the
  /// last queue overlay (3s auto-dismiss, tappable).
  final OverflowPayload? overflow;
}

/// Payload for the condensed overflow card shown when more than 3 events
/// would otherwise queue. Currently only rank-ups can overflow — level-ups
/// and titles always survive the cap (see [CelebrationQueue.build]).
class OverflowPayload {
  const OverflowPayload({required this.remainingRankUps});

  final int remainingRankUps;
}

/// Pure transform that takes the unordered events from a workout finish and
/// produces the playback queue.
///
/// **Ordering rules (locked, spec §13.2 + Cluster 3 BUG-011/BUG-013/BUG-017):**
///   1. First-awakening events lead — they narratively precede the body part
///      ranking up at all. Throttled to one per workout upstream.
///   2. ClassChangeEvent — the rarest progression beat (slot 1 reserved).
///   3. Rank-up events, sorted by `newRank` descending (biggest jump first
///      as tiebreaker — the lifter's biggest win leads the narrative).
///   4. Title-unlock events close the visible queue — they are the crown on
///      the workout.
///   5. The character level-up event sits LAST in the closer priority —
///      character level is a pure function of body-part ranks and the saga
///      screen always re-derives it, so dropping it costs less narrative
///      continuity than dropping a rank-up or a title.
///
/// **Cap-at-3 rule with reservation policy (BUG-013 + BUG-017, Cluster 3):**
///   * Total visible queue capped at 3 to keep the celebration under ~3.5s.
///   * First-awakening overlays bypass the cap (separate onboarding moment).
///   * **Slot 1 reserved for ClassChangeEvent** when present — the rarest
///     progression event in the entire loop.
///   * **Slot 2 reserved for the highest rank-up** when any rank-up exists
///     — the most viscerally satisfying moment in the loop. The pre-Cluster-3
///     logic let closers (level-up + titles) starve rank-ups entirely; the
///     PO call locked this to "rank-ups never lose to closers".
///   * Spillover fills the remaining slots in this priority order:
///     additional rank-ups (descending) → titles (FIFO) → level-up. Title
///     beats level-up so a (class, rank-up, level-up, title) finish surfaces
///     the title (BUG-017: "title is the crown"); the level-up drops to
///     silent absorption. Additional rank-ups still beat both closers
///     because BUG-013 promised "rank-ups never lose to closers" — a finish
///     with 4 rank-ups + 1 title + 1 level-up surfaces 3 rank-ups and the
///     1-rank overflow card; both closers absorb silently.
///   * Trimmed rank-ups are summarized in [OverflowPayload.remainingRankUps]
///     so the overflow card (BUG-013 mini-flipbook) can render
///     "+{N} ranks" with three cycling muscle sigils.
///   * Trimmed level-ups + titles are dropped silently — they remain
///     server-side and surface in the saga screen / titles library on
///     next visit. Adding a separate overflow surface for closers was
///     considered and deferred — the rank-up overflow card already
///     fronts a "go look at the rest" affordance.
///
/// **Why ClassChangeEvent never enters the overflow card:** there's only
/// ever one class change per finish (a user can't cross two class boundaries
/// in a single workout — the resolver is a single function over the rank
/// distribution). Slot 1 is enough.
///
/// **Idempotency:** same input → same output. The dismiss-skip-end semantic
/// is owned by the runtime scheduler (`ActiveWorkoutNotifier`), not the
/// queue. A user dismissing mid-queue does not change what `build` returns.
class CelebrationQueue {
  const CelebrationQueue._();

  static const int _capExcludingAwakening = 3;

  /// Build the playback queue from [events].
  static CelebrationQueueResult build({
    required List<CelebrationEvent> events,
  }) {
    if (events.isEmpty) {
      return const CelebrationQueueResult(queue: <CelebrationEvent>[]);
    }

    // Bucket by event kind. Order within each bucket is canonicalized
    // before we apply the cap.
    final firstAwakenings = <FirstAwakeningEvent>[];
    final classChanges = <ClassChangeEvent>[];
    final rankUps = <RankUpEvent>[];
    final levelUps = <LevelUpEvent>[];
    final titles = <TitleUnlockEvent>[];
    final personalRecords = <PersonalRecordEvent>[];

    for (final e in events) {
      switch (e) {
        case FirstAwakeningEvent():
          firstAwakenings.add(e);
        case ClassChangeEvent():
          classChanges.add(e);
        case RankUpEvent():
          rankUps.add(e);
        case LevelUpEvent():
          levelUps.add(e);
        case TitleUnlockEvent():
          titles.add(e);
        case PersonalRecordEvent():
          personalRecords.add(e);
      }
    }

    // Highest body-part rank first so the biggest jump leads. Stable
    // secondary sort by body-part dbValue keeps output deterministic when
    // two body parts hit the same threshold in the same workout.
    rankUps.sort((a, b) {
      final cmp = b.newRank.compareTo(a.newRank);
      if (cmp != 0) return cmp;
      return a.bodyPart.dbValue.compareTo(b.bodyPart.dbValue);
    });

    // ----- Reservation policy (BUG-011 + BUG-013 + BUG-017 + PR 29.5) -----
    //
    // Allocate slots in priority order so the rarest events always survive
    // the cap.
    //   slot 1: class change (at most 1 — the resolver yields a single
    //           class per snapshot, so multi-class-change in one finish
    //           is structurally impossible)
    //   slot 2: highest rank-up — BUG-013 invariant
    //   spillover: additional rank-ups (descending) → personal records
    //              (FIFO) → titles (FIFO) → level-up. Per WIP §4 + mockup
    //              §4 hierarchy, PR sits AFTER class-change and BEFORE
    //              title in the closer priority; PRs are the canonical
    //              share moment, narratively heavier than a title unlock.
    //              Level-up is the lowest-priority closer because
    //              character level is a pure function of body-part ranks
    //              (always re-derivable on the saga screen).
    //
    // Pure-function arithmetic: same inputs → same allocation.
    var remaining = _capExcludingAwakening;

    // Slot 1: class change. Take at most one (`classChanges.length` will
    // be 0 or 1 in practice; we still .take(1) defensively).
    final keptClassChange = classChanges.take(1).toList(growable: false);
    remaining -= keptClassChange.length;

    // Slot 2: top rank-up — reserved when ANY rank-up exists, regardless
    // of how many closers are queued. This is the BUG-013 invariant.
    final keptTopRankUp = rankUps.isNotEmpty
        ? <RankUpEvent>[rankUps.first]
        : const <RankUpEvent>[];
    remaining -= keptTopRankUp.length;

    // Spillover: additional rank-ups (descending) → personal records (FIFO)
    // → titles (FIFO) → level-up.
    final additionalRankUps = rankUps
        .skip(keptTopRankUp.length)
        .take(remaining < 0 ? 0 : remaining)
        .toList(growable: false);
    remaining -= additionalRankUps.length;

    final keptPersonalRecords = personalRecords
        .take(remaining < 0 ? 0 : remaining)
        .toList(growable: false);
    remaining -= keptPersonalRecords.length;

    final keptTitles = titles
        .take(remaining < 0 ? 0 : remaining)
        .toList(growable: false);
    remaining -= keptTitles.length;

    final keptLevelUps = levelUps
        .take(remaining < 0 ? 0 : remaining)
        .toList(growable: false);
    // remaining -= keptLevelUps.length; — bookkeeping irrelevant past the
    // last bucket; intentionally elided to avoid a dead store warning.

    // Compose final queue in playback order: first-awakening → class →
    // rank-ups → PRs → level-up → titles. Titles render last so they're
    // the crown of the workout (spec §13.2). PRs play after the rank-up
    // body-part beat but before the title's narrative-closing role.
    final queue = <CelebrationEvent>[
      ...firstAwakenings,
      ...keptClassChange,
      ...keptTopRankUp,
      ...additionalRankUps,
      ...keptPersonalRecords,
      ...keptLevelUps,
      ...keptTitles,
    ];

    // Overflow currently surfaces only the trimmed rank-up count — closers
    // (PRs, titles, level-ups) dropped by the cap are silently absorbed
    // (see class-level docstring).
    final overflowCount =
        rankUps.length - keptTopRankUp.length - additionalRankUps.length;
    final overflow = overflowCount > 0
        ? OverflowPayload(remainingRankUps: overflowCount)
        : null;

    return CelebrationQueueResult(queue: queue, overflow: overflow);
  }
}
