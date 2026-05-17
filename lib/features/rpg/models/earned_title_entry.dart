import 'title.dart';

/// UI-shaped row for the Titles screen — pairs a [Title] catalog entry with
/// its per-user earned state.
///
/// Lives in `models/` rather than `providers/` so pure domain code (e.g.
/// `TitlesViewModel.split`) can consume it without pulling in Riverpod.
/// The Riverpod-side `earnedTitlesProvider` re-exports this class for
/// backward compatibility with existing screen-layer imports.
class EarnedTitleEntry {
  const EarnedTitleEntry({
    required this.title,
    required this.earnedAt,
    required this.isActive,
  });

  final Title title;
  final DateTime earnedAt;

  /// True for the single equipped row enforced by
  /// `earned_titles_one_active` UNIQUE INDEX.
  final bool isActive;
}
