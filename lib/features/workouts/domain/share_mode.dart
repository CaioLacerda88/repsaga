/// Which share-card MODE the overlay renders — the Bestiary creature card
/// (default, playful) or the Clean Flex stats card (serious, data-forward).
///
/// **Orthogonal to `ShareCardVariant`.** `ShareCardVariant` (photo vs
/// discreet) is the photo axis — whether the card has a user photo behind
/// it. [ShareMode] is the content axis — what the bottom block says. A
/// Bestiary card still has a photo/discreet axis, and so does a Clean Flex
/// card. Collapsing the two would lose the "no-photo Bestiary" combination.
///
/// Both modes render their content block into the SAME shared overlay
/// chassis (full-bleed photo-hero + scrim + 7-hue identity rail + wordmark,
/// spec §7) so both read as RepSaga.
enum ShareMode {
  /// The generated creature you felled (spec §3–§6). Default for most users.
  bestiary,

  /// PR-hero + a four-stat strip (spec §7 Stats mode, Slice 1). For the
  /// serious lifter / data-nerd persona. The six-ring conditioning
  /// dashboard is Slice 2.
  cleanFlex,
}
