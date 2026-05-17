import '../models/body_part.dart';
import '../models/title.dart';
import '../providers/earned_titles_provider.dart';
import 'cross_build_title_evaluator.dart';

/// One row in the "Próximos" region. Either a per-body-part next title or
/// the next character-level title.
class NextTitleRowData {
  const NextTitleRowData({
    required this.title,
    required this.currentValue,
    required this.thresholdValue,
  });

  final Title title;

  /// Current rank (for body-part titles) or character level (for char titles).
  final int currentValue;

  /// Required rank or character level.
  final int thresholdValue;

  /// `thresholdValue - currentValue`. Always > 0 for entries placed in
  /// `nextRows` (already-earned titles are filtered out upstream).
  int get remaining => thresholdValue - currentValue;
}

/// One card in the "Próximos" region for a cross-build title that's within 1
/// rank of every condition.
class CrossBuildCardData {
  const CrossBuildCardData({
    required this.title,
    required this.stats,
    required this.bottleneckBodyPart,
  });

  final Title title;

  /// (body-part, current, floor) tuples for the cards' condition rows.
  /// Sourced from `crossBuildStatsFor(slug, ranks)`.
  final List<CrossBuildStat> stats;

  /// The body part with the smallest non-zero gap. Drives the
  /// `Falta 1 rank em {body-part}` sub-line.
  final BodyPart bottleneckBodyPart;
}

/// The three-region snapshot the Titles screen renders.
class TitlesView {
  const TitlesView({
    required this.equipped,
    required this.earned,
    required this.nextRows,
    required this.crossBuildCards,
    required this.totalCatalogCount,
    required this.totalEarnedCount,
  });

  /// The single currently-equipped row, or null.
  final EarnedTitleEntry? equipped;

  /// Earned-but-not-equipped rows, most recent first.
  final List<EarnedTitleEntry> earned;

  /// Single next title per body-part track + character level.
  final List<NextTitleRowData> nextRows;

  /// Cross-build cards within 1 rank of every condition.
  final List<CrossBuildCardData> crossBuildCards;

  final int totalCatalogCount;
  final int totalEarnedCount;
}

/// Pure view-model splitter for the Titles screen.
///
/// **Why a static splitter and not a Riverpod provider:** the Titles screen
/// already reads `earnedTitlesProvider`, `titleCatalogProvider`, and
/// `rpgProgressProvider` via Riverpod — each with their own loading/error
/// machinery. The view-model's job is purely to take the four resolved
/// inputs and split them into the three regions the UI renders. Pinning
/// that split as a free-standing pure function means it's testable without
/// a `ProviderContainer`, and the Titles screen can swap how it composes the
/// inputs without touching this contract.
///
/// **Pure / no side effects / no async:** identical to
/// [`CrossBuildTitleEvaluator`] — the input is fully described by the
/// arguments and the output is fully determined by them. Unit tests pin
/// every region's selection rule against this function directly.
abstract final class TitlesViewModel {
  /// Split [catalog] into the three regions the Titles screen renders.
  ///
  /// Region rules:
  ///   * `equipped` — the single [EarnedTitleEntry] with `isActive: true`,
  ///     or null. The schema enforces "at most one active" via
  ///     `earned_titles_one_active` UNIQUE INDEX; we don't re-validate here.
  ///   * `earned` — every earned entry NOT equipped, sorted most-recent-first
  ///     by `earnedAt`.
  ///   * `nextRows` — for each body part in [activeBodyParts], the smallest
  ///     unearned [BodyPartTitle] with `rankThreshold > current`. Plus the
  ///     smallest unearned [CharacterLevelTitle] with
  ///     `levelThreshold > characterLevel`. Body parts with no candidate
  ///     titles (e.g. user maxed out, or no catalog entries for that part)
  ///     are silently skipped.
  ///   * `crossBuildCards` — unearned [CrossBuildTitle]s where every
  ///     condition is within 1 rank of its floor. Already-cleared conditions
  ///     count as satisfied. Cards with no remaining gap (predicate already
  ///     satisfied — transient race before the awarder writes the row) are
  ///     suppressed to avoid a misleading "0 more" card.
  static TitlesView split({
    required List<Title> catalog,
    required List<EarnedTitleEntry> earned,
    required Map<BodyPart, int> ranks,
    required int characterLevel,
  }) {
    final earnedBySlug = <String, EarnedTitleEntry>{
      for (final e in earned) e.title.slug: e,
    };
    final equippedEntry = earned.where((e) => e.isActive).firstOrNull;
    final earnedNonActive = [
      for (final e in earned)
        if (!e.isActive) e,
    ]..sort((a, b) => b.earnedAt.compareTo(a.earnedAt));

    // --- Next per-body-part: smallest unearned threshold > current rank.
    final nextRows = <NextTitleRowData>[];
    for (final bp in activeBodyParts) {
      final current = ranks[bp] ?? 1;
      final candidates =
          catalog
              .whereType<BodyPartTitle>()
              .where((t) => t.bodyPart == bp)
              .where((t) => t.rankThreshold > current)
              .where((t) => !earnedBySlug.containsKey(t.slug))
              .toList()
            ..sort((a, b) => a.rankThreshold.compareTo(b.rankThreshold));
      if (candidates.isEmpty) continue;
      final next = candidates.first;
      nextRows.add(
        NextTitleRowData(
          title: next,
          currentValue: current,
          thresholdValue: next.rankThreshold,
        ),
      );
    }

    // --- Next character-level: smallest unearned threshold > characterLevel.
    final nextChar =
        catalog
            .whereType<CharacterLevelTitle>()
            .where((t) => t.levelThreshold > characterLevel)
            .where((t) => !earnedBySlug.containsKey(t.slug))
            .toList()
          ..sort((a, b) => a.levelThreshold.compareTo(b.levelThreshold));
    if (nextChar.isNotEmpty) {
      final next = nextChar.first;
      nextRows.add(
        NextTitleRowData(
          title: next,
          currentValue: characterLevel,
          thresholdValue: next.levelThreshold,
        ),
      );
    }

    // --- Cross-build "within 1 rank of every condition".
    final crossBuildCards = <CrossBuildCardData>[];
    for (final t in catalog.whereType<CrossBuildTitle>()) {
      if (earnedBySlug.containsKey(t.slug)) continue;
      final stats = crossBuildStatsFor(t.slug, ranks);
      if (stats.isEmpty) continue;
      // "Within 1 rank of every condition" = every (floor - current) is in
      // 0 or 1. Conditions already cleared have a non-positive gap; we
      // count those as satisfied.
      final allWithinOne = stats.every((s) => (s.floor - s.current) <= 1);
      if (!allWithinOne) continue;
      // Bottleneck = the stat with the largest positive gap (1, since the
      // predicate above bounds the gap to <= 1; ties pick canonical order).
      final bottleneck = stats.where((s) => s.current < s.floor).toList()
        ..sort((a, b) => (b.floor - b.current).compareTo(a.floor - a.current));
      // Empty bottleneck means every floor already cleared — the predicate
      // is satisfied and the title should be earned. Suppress the card to
      // avoid a misleading row during the transient award-vs-UI race.
      if (bottleneck.isEmpty) continue;
      crossBuildCards.add(
        CrossBuildCardData(
          title: t,
          stats: stats,
          bottleneckBodyPart: bottleneck.first.bodyPart,
        ),
      );
    }

    return TitlesView(
      equipped: equippedEntry,
      earned: earnedNonActive,
      nextRows: nextRows,
      crossBuildCards: crossBuildCards,
      totalCatalogCount: catalog.length,
      totalEarnedCount: earned.length,
    );
  }
}
