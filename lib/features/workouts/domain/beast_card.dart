// ignore_for_file: invalid_annotation_target

import 'package:flutter/painting.dart' show Color;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../rpg/models/body_part.dart';

part 'beast_card.freezed.dart';

/// The bestiary tier ladder (Solo-Leveling E→S). The base tier is the
/// dominant line's RANK league — NOT the session's raw XP (spec §3
/// RANK-PRIMARY; session-XP-driven tiers invert over a career because the
/// locked XP formula decays per-session XP as rank climbs). Ordinal order
/// E < D < C < B < A < S is load-bearing: boss promotion is "one tier up",
/// so the enum index IS the ladder position.
enum BeastTier {
  e('E'),
  d('D'),
  c('C'),
  b('B'),
  a('A'),
  s('S');

  const BeastTier(this.label);

  /// Display token rendered on the share overlay rank line ("RANK C").
  final String label;

  /// Rank-league mapping (the locked bands, spec §3):
  /// E[1–4] D[5–10] C[11–20] B[21–35] A[36–55] S[56+]. A null/0/negative
  /// rank (pathological — no dominant BP) floors to E.
  static BeastTier fromRankLeague(int rank) {
    if (rank <= 4) return BeastTier.e;
    if (rank <= 10) return BeastTier.d;
    if (rank <= 20) return BeastTier.c;
    if (rank <= 35) return BeastTier.b;
    if (rank <= 55) return BeastTier.a;
    return BeastTier.s;
  }

  /// The next tier up, used for boss promotion (PR / rank-up). Clamps at
  /// [BeastTier.s] — an S-league line's apex IS the top, a boss there
  /// promotes the styling (named apex) without exceeding the ladder.
  BeastTier get promoted {
    final next = index + 1;
    if (next >= BeastTier.values.length) return BeastTier.s;
    return BeastTier.values[next];
  }
}

/// What kind of encounter the session produced. Precedence (highest first):
/// legendary > boss > chimera > base. Resolved by objective triggers only
/// in Slice 1 (spec §4/§5): session-count milestone → legendary; PR or
/// rank-up → boss; 3+ parts trained → chimera; else → base.
enum BeastKind { base, boss, chimera, legendary }

/// The specimen size WITHIN the rank league — flavor only, never a tier
/// change (spec §3). Session XP vs the league's reference median decides it:
/// a routine session yields the [base] creature; a big-for-your-level
/// session a [notable] / [fierce] variant (descriptor + art emphasis).
enum BeastSpecimen { base, notable, fierce }

/// The resolver output — a fully-resolved creature for one finished session.
///
/// Pure data. [name] is already resolved for the requested locale (the
/// resolver is l10n-harness-free; it takes a locale string and picks en/pt
/// from the inline catalog content — see
/// `feedback_widget_l10n_parameterization`). [hues] carries the dominant
/// body part's identity hue first; a chimera appends the other trained
/// parts' hues for the multi-hue rail. [sourceSessionId] is the determinism
/// key — the same session id always yields the same beast.
@freezed
abstract class BeastCard with _$BeastCard {
  const factory BeastCard({
    /// Dominant body part — the creature's LINE (most session XP).
    required BodyPart line,

    /// Rank league of the dominant line (spec §3 RANK-PRIMARY).
    required BeastTier tier,

    /// Encounter kind (base/boss/chimera/legendary).
    required BeastKind kind,

    /// Specimen size within the league (flavor; spec §3).
    required BeastSpecimen specimen,

    /// Display name, already resolved for the requested locale.
    required String name,

    /// Stable slug of the chosen base/legendary/chimera entry (or the boss's
    /// underlying creature). Drives the client-side 1-deep "last beast"
    /// no-repeat guard.
    required String slug,

    /// Boss epithet, already resolved for locale. `null` for non-boss kinds.
    String? epithet,

    /// Identity hues. `hues.first` is the dominant line's hue; a chimera
    /// appends the other trained parts' hues (multi-hue rail, spec §5). Stays
    /// index-aligned with [trainedParts].
    required List<Color> hues,

    /// The body parts trained ≥ the significance floor this session, dominant
    /// first (index-aligned with [hues]). The chassis maps these to rail
    /// segments to widen — a focused session carries just the dominant line,
    /// a chimera carries every trained part so the rail emphasises them ALL
    /// (spec §5 "the rail emphasizes every trained hue"). Carrying the parts
    /// (not only [hues] colors) lets the rail — which keys flex by
    /// [BodyPart] — widen the right segments without a color→part reverse map.
    required List<BodyPart> trainedParts,

    /// Achievement phrase, already resolved for locale (spec §6).
    required String achievementPhrase,

    /// Glyph/sigil token for the rank line (e.g. "◈" base, "⚜" boss laurel).
    required String sigil,

    /// The session this beast was resolved from — the determinism key.
    required String sourceSessionId,
  }) = _BeastCard;
}
