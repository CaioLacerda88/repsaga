import 'package:flutter/painting.dart' show Color;

import '../../rpg/domain/body_part_hues.dart';
import '../../rpg/models/body_part.dart';
import '../../rpg/models/celebration_event.dart';
import '../ui/post_session/post_session_state.dart';
import 'beast_card.dart';
import 'bestiary_catalog.dart';

/// Resolves a finished session into a [BeastCard] — the bestiary share
/// payload (spec §3 RANK-PRIMARY).
///
/// **Pure + deterministic + l10n-harness-free.** No IO: the parsed
/// [BestiaryCatalog] is injected, the determinism key ([sessionId]) and the
/// 1-deep no-repeat guard ([lastBeastSlug]) are passed in, and [locale]
/// selects en/pt from the inline content. The same `(state, sessionId,
/// lastBeastSlug)` always yields the same beast.
///
/// **The model is RANK-PRIMARY (do NOT reintroduce session-XP→tier):**
///   * **Line** = dominant body part (max session XP from `bpXpDeltas`).
///   * **Tier** = the dominant line's RANK league
///     (`bpRankAfter[dominantBp]`, spec §3 bands) — NOT session XP, which
///     inverts over a career.
///   * **Specimen** = session XP vs the league's reference median (flavor).
///   * **Kind** = objective triggers, precedence
///     legendary > boss > chimera > base (Slice 1).
///   * **Variant** = `hash(sessionId) mod count` + the no-repeat guard.
class BestiaryResolver {
  const BestiaryResolver(this._catalog);

  final BestiaryCatalog _catalog;

  /// Per-league session-XP reference medians for the specimen band (spec §3).
  /// Derived from the persona simulation (`tasks/bestiary-tier-calibration.py`
  /// per-rank-league p50, de-noised: E/D buckets have few or smurf-inflated
  /// samples, so the early tiers are rounded to a stable floor rather than
  /// the raw sim value). These are FLAVOR thresholds — a coarse 3-band split
  /// per the spec, pinned by a unit test so a future content edit can't drift
  /// them silently.
  static const Map<BeastTier, double> referenceMedianXp = {
    BeastTier.e: 220,
    BeastTier.d: 400,
    BeastTier.c: 420,
    BeastTier.b: 430,
    BeastTier.a: 470,
    BeastTier.s: 500,
  };

  /// Specimen band multipliers over the league reference median. ≥[_fierceX]
  /// → fierce, ≥[_notableX] → notable, else base.
  static const double _notableX = 1.4;
  static const double _fierceX = 2.2;

  /// XP floor for a body part to count as "trained significantly" toward the
  /// chimera parts-count. A part that earned a token sliver of attribution XP
  /// shouldn't push a focused session into chimera territory.
  static const int _significantXpFloor = 1;

  /// Resolve the beast for a finished [state].
  ///
  /// [sessionId] is the determinism key (the finished workout's id). It is an
  /// explicit param — `PostSessionState` carries no workout id — so the
  /// resolver stays a pure function of its arguments. [lastBeastSlug] is the
  /// previously-surfaced beast slug (persisted client-side); on a collision
  /// the resolver advances to the next variant so the same (line, tier) never
  /// shows the same creature two sessions running. [locale] picks en/pt.
  BeastCard resolve(
    PostSessionState state, {
    required String sessionId,
    required String locale,
    String? lastBeastSlug,
  }) {
    final dominant = _dominantLine(state);
    // Dominant line's rank league (spec §3). `bpRankAfter[dominant]` is the
    // absolute 1–99 rank after the save; missing/0 floors to E.
    final rank = (dominant == null) ? 0 : (state.bpRankAfter[dominant] ?? 0);
    final tier = BeastTier.fromRankLeague(rank);
    final specimen = _specimen(state.totalXpEarned, tier);
    final hash = _hash(sessionId);

    // Significantly-trained parts (chimera trigger), ordered dominant-first
    // by descending session XP so [BeastCard.trainedParts] / [hues] put the
    // dominant line at index 0 (the rail + multi-hue gradient read it that
    // way). Ties break alphabetically on `dbValue` for determinism.
    final trainedParts =
        state.bpXpDeltas.entries
            .where((e) => e.value >= _significantXpFloor)
            .map((e) => e.key)
            .toList()
          ..sort((a, b) {
            final xpCmp = (state.bpXpDeltas[b] ?? 0).compareTo(
              state.bpXpDeltas[a] ?? 0,
            );
            if (xpCmp != 0) return xpCmp;
            return a.dbValue.compareTo(b.dbValue);
          });

    final hasPr = state.prResult?.hasNewRecords ?? false;
    final hasRankUp = state.queueResult.queue.any((e) => e is RankUpEvent);
    final legendary = _legendaryFor(state.sagaNumber);

    // Kind precedence: legendary > boss (PR/rank-up) > chimera (3+ parts) >
    // base. Resolved as the first matching branch (spec §4/§5, Slice 1).
    if (legendary != null) {
      return _legendaryCard(
        state: state,
        legendary: legendary,
        dominant: dominant,
        tier: tier,
        specimen: specimen,
        trainedParts: trainedParts,
        sessionId: sessionId,
        locale: locale,
        hash: hash,
      );
    }

    if (hasPr || hasRankUp) {
      return _bossCard(
        state: state,
        dominant: dominant,
        tier: tier,
        specimen: specimen,
        trainedParts: trainedParts,
        sessionId: sessionId,
        locale: locale,
        hash: hash,
        lastBeastSlug: lastBeastSlug,
      );
    }

    if (trainedParts.length >= 3) {
      return _chimeraCard(
        state: state,
        dominant: dominant,
        tier: tier,
        specimen: specimen,
        trainedParts: trainedParts,
        sessionId: sessionId,
        locale: locale,
        hash: hash,
        lastBeastSlug: lastBeastSlug,
      );
    }

    return _baseCard(
      state: state,
      dominant: dominant,
      tier: tier,
      specimen: specimen,
      trainedParts: trainedParts,
      sessionId: sessionId,
      locale: locale,
      hash: hash,
      lastBeastSlug: lastBeastSlug,
    );
  }

  // ─── Line + tier + specimen ──────────────────────────────────────────────

  /// Dominant body part — highest XP delta, ties broken by higher rank then
  /// alphabetical `dbValue` (matches `SharePayload.fromPostSessionState` so
  /// the bestiary's line tracks the cinematic Beat 2 dominant BP). `null`
  /// when no BP earned XP (pathological — defended downstream).
  BodyPart? _dominantLine(PostSessionState state) {
    final deltas = state.bpXpDeltas;
    if (deltas.isEmpty) return null;
    final keys = deltas.keys.toList()
      ..sort((a, b) {
        final xpCmp = deltas[b]!.compareTo(deltas[a]!);
        if (xpCmp != 0) return xpCmp;
        // Missing rank → 0 ("no rank yet"), matching the `resolve` sentinel
        // (I1: unify the no-rank default to 0 across the resolver).
        final rankCmp = (state.bpRankAfter[b] ?? 0).compareTo(
          state.bpRankAfter[a] ?? 0,
        );
        if (rankCmp != 0) return rankCmp;
        return a.dbValue.compareTo(b.dbValue);
      });
    return keys.first;
  }

  BeastSpecimen _specimen(int sessionXp, BeastTier tier) {
    final median = referenceMedianXp[tier]!;
    final ratio = sessionXp / median;
    if (ratio >= _fierceX) return BeastSpecimen.fierce;
    if (ratio >= _notableX) return BeastSpecimen.notable;
    return BeastSpecimen.base;
  }

  LegendaryEntry? _legendaryFor(int sagaNumber) {
    for (final l in _catalog.legendaries) {
      // Exact `sessionCount == sagaNumber` match is deliberate for Slice 1:
      // sagaNumber increments by exactly 1 per finished session, so the
      // milestone session lands on the exact count (no "≥" needed, and "≥"
      // would re-fire the legendary on every session past the milestone).
      if (l.sessionCount == sagaNumber) return l;
    }
    return null;
  }

  // ─── Card builders ───────────────────────────────────────────────────────

  BeastCard _baseCard({
    required PostSessionState state,
    required BodyPart? dominant,
    required BeastTier tier,
    required BeastSpecimen specimen,
    required List<BodyPart> trainedParts,
    required String sessionId,
    required String locale,
    required int hash,
    required String? lastBeastSlug,
  }) {
    final line = dominant ?? BodyPart.chest;
    final entry = _pickBaseCreature(
      line: line,
      tier: tier,
      hash: hash,
      lastBeastSlug: lastBeastSlug,
    );
    return BeastCard(
      line: line,
      tier: tier,
      kind: BeastKind.base,
      specimen: specimen,
      name: entry.name.forLocale(locale),
      slug: entry.slug,
      hues: [BodyPartHues.hueFor(line)],
      // A focused beast widens only the dominant line on the rail (spec §2).
      trainedParts: [line],
      achievementPhrase: _phrase(
        state: state,
        dominant: line,
        tier: tier,
        trainedParts: trainedParts,
        locale: locale,
      ),
      sigil: _baseSigil,
      sourceSessionId: sessionId,
    );
  }

  BeastCard _bossCard({
    required PostSessionState state,
    required BodyPart? dominant,
    required BeastTier tier,
    required BeastSpecimen specimen,
    required List<BodyPart> trainedParts,
    required String sessionId,
    required String locale,
    required int hash,
    required String? lastBeastSlug,
  }) {
    final line = dominant ?? BodyPart.chest;
    // A boss = the dominant line's creature PROMOTED one tier (spec §4), then
    // prefixed (en) / suffixed (pt) with a gold epithet.
    final bossTier = tier.promoted;
    final entry = _pickBaseCreature(
      line: line,
      tier: bossTier,
      hash: hash,
      lastBeastSlug: lastBeastSlug,
    );
    final epithet = _catalog.epithets[hash % _catalog.epithets.length];
    final creatureName = entry.name.forLocale(locale);
    final epithetText = epithet.name.forLocale(locale);
    // en: "[Epithet], [Creature]" · pt: "[Creature], [Epithet]". The epithet
    // pool already carries its article ("the Unbroken", "o Inquebrável"), so
    // the composer never injects a separate "the" (nit fix: comment now
    // matches the emitted "[Epithet], [Creature]" shape).
    final isPt = locale.toLowerCase().startsWith('pt');
    final composed = isPt
        ? '$creatureName, $epithetText'
        : '$epithetText, $creatureName';
    return BeastCard(
      line: line,
      tier: bossTier,
      kind: BeastKind.boss,
      specimen: specimen,
      name: composed,
      slug: entry.slug,
      epithet: epithetText,
      hues: [BodyPartHues.hueFor(line)],
      // A boss is a single-line elite — widen only the dominant line.
      trainedParts: [line],
      achievementPhrase: _phrase(
        state: state,
        dominant: line,
        tier: tier,
        trainedParts: trainedParts,
        locale: locale,
      ),
      sigil: _bossSigil,
      sourceSessionId: sessionId,
    );
  }

  BeastCard _chimeraCard({
    required PostSessionState state,
    required BodyPart? dominant,
    required BeastTier tier,
    required BeastSpecimen specimen,
    required List<BodyPart> trainedParts,
    required String sessionId,
    required String locale,
    required int hash,
    required String? lastBeastSlug,
  }) {
    final line = dominant ?? BodyPart.chest;
    final partCount = trainedParts.length;

    // Order parts by descending XP so the top-2 are the dominant + secondary.
    final ordered = [...trainedParts]
      ..sort(
        (a, b) =>
            (state.bpXpDeltas[b] ?? 0).compareTo(state.bpXpDeltas[a] ?? 0),
      );

    ChimeraEntry? named;
    String? generativeName;

    if (partCount >= 5) {
      named = _pickChimeraVariant(
        _catalog.chimerasByCount[5] ?? const [],
        hash,
        lastBeastSlug,
      );
    } else if (partCount == 4) {
      named = _pickChimeraVariant(
        _catalog.chimerasByCount[4] ?? const [],
        hash,
        lastBeastSlug,
      );
    } else {
      // 3 parts: prefer a curated 2-part override on the top-2 lines, else
      // the generative fusion-lexicon hybrid (spec §3b), else the fixed
      // 3-fanged chimera.
      final pairKey = _pairKey(ordered[0], ordered[1]);
      final curated = _catalog.curatedChimeras[pairKey];
      if (curated != null && curated.isNotEmpty) {
        named = _pickChimeraVariant(curated, hash, lastBeastSlug);
      } else {
        generativeName = _generativeChimeraName(
          dominant: ordered[0],
          secondary: ordered[1],
          hash: hash,
          locale: locale,
        );
      }
    }

    final hues = _chimeraHues(ordered);
    final phrase = _chimeraPhrase(locale);

    if (named != null) {
      return BeastCard(
        line: line,
        tier: tier,
        kind: BeastKind.chimera,
        specimen: specimen,
        name: named.name.forLocale(locale),
        slug: named.slug,
        hues: hues,
        // A chimera widens EVERY trained part on the rail (spec §5). [ordered]
        // is index-aligned with [hues] (both dominant-first).
        trainedParts: ordered,
        achievementPhrase: phrase,
        sigil: _chimeraSigil,
        sourceSessionId: sessionId,
      );
    }

    // Generative hybrid — slug encodes the pair so the no-repeat guard still
    // discriminates it from other beasts.
    final slug = 'chimera_gen_${ordered[0].dbValue}_${ordered[1].dbValue}';
    return BeastCard(
      line: line,
      tier: tier,
      kind: BeastKind.chimera,
      specimen: specimen,
      name: generativeName!,
      slug: slug,
      hues: hues,
      trainedParts: ordered,
      achievementPhrase: phrase,
      sigil: _chimeraSigil,
      sourceSessionId: sessionId,
    );
  }

  BeastCard _legendaryCard({
    required PostSessionState state,
    required LegendaryEntry legendary,
    required BodyPart? dominant,
    required BeastTier tier,
    required BeastSpecimen specimen,
    required List<BodyPart> trainedParts,
    required String sessionId,
    required String locale,
    required int hash,
  }) {
    final line = dominant ?? BodyPart.chest;
    return BeastCard(
      line: line,
      tier: tier,
      kind: BeastKind.legendary,
      specimen: specimen,
      name: legendary.name.forLocale(locale),
      slug: legendary.slug,
      hues: [BodyPartHues.hueFor(line)],
      // A legendary is a single named encounter — widen only the dominant
      // line (it borrows the boss styling, not the chimera multi-hue rail).
      trainedParts: [line],
      achievementPhrase: _phrase(
        state: state,
        dominant: line,
        tier: tier,
        trainedParts: trainedParts,
        locale: locale,
      ),
      sigil: _bossSigil,
      sourceSessionId: sessionId,
    );
  }

  // ─── Variant picks (deterministic + 1-deep no-repeat) ────────────────────

  /// Pick a base creature for (line, tier), choosing a variant by hash and
  /// skipping the [lastBeastSlug] when the hash lands on a repeat (spec §5).
  BaseCreatureEntry _pickBaseCreature({
    required BodyPart line,
    required BeastTier tier,
    required int hash,
    required String? lastBeastSlug,
  }) {
    final variants =
        _catalog.baseCreatures
            .where((c) => c.line == line && c.tier == tier)
            .toList(growable: false)
          ..sort((a, b) => a.variant.compareTo(b.variant));
    return _noRepeatPick(variants, hash, lastBeastSlug, (e) => e.slug);
  }

  ChimeraEntry _pickChimeraVariant(
    List<ChimeraEntry> variants,
    int hash,
    String? lastBeastSlug,
  ) {
    return _noRepeatPick(variants, hash, lastBeastSlug, (e) => e.slug);
  }

  /// Deterministic `hash mod count` pick with a 1-deep no-repeat guard: if the
  /// chosen entry's slug equals [lastBeastSlug] AND there is more than one
  /// option, advance to the next variant (wrapping). Same session id →
  /// same pick (the guard only fires on an actual collision).
  T _noRepeatPick<T>(
    List<T> options,
    int hash,
    String? lastBeastSlug,
    String Function(T) slugOf,
  ) {
    assert(options.isNotEmpty, 'no catalog options to pick from');
    final n = options.length;
    var idx = hash % n;
    if (n > 1 && slugOf(options[idx]) == lastBeastSlug) {
      idx = (idx + 1) % n;
    }
    return options[idx];
  }

  // ─── Generative chimera (non-curated 2-line fallback) ────────────────────

  String _generativeChimeraName({
    required BodyPart dominant,
    required BodyPart secondary,
    required int hash,
    required String locale,
  }) {
    final domLex = _lexiconFor(dominant);
    final secLex = _lexiconFor(secondary);
    final adj = secLex.adjectives[hash % secLex.adjectives.length];
    final isPt = locale.toLowerCase().startsWith('pt');
    // en: "The [adj of 2nd] [noun of dominant]"
    // pt: "O [Noun do dominante] [adj da 2ª]" (spec §3b).
    if (isPt) {
      return 'O ${domLex.noun.pt} ${adj.pt}';
    }
    return 'The ${adj.en} ${domLex.noun.en}';
  }

  ChimeraLexiconEntry _lexiconFor(BodyPart line) {
    return _catalog.lexicon.firstWhere((e) => e.line == line);
  }

  /// Sorted, `+`-joined pair key for curated-chimera lookup (the catalog keys
  /// pairs as unordered `lineA+lineB`).
  String _pairKey(BodyPart a, BodyPart b) {
    final names = [a.dbValue, b.dbValue]..sort();
    return '${names[0]}+${names[1]}';
  }

  List<Color> _chimeraHues(List<BodyPart> ordered) {
    return ordered.map(BodyPartHues.hueFor).toList(growable: false);
  }

  // ─── Achievement phrase (spec §6) ────────────────────────────────────────

  /// Highest-priority applicable trait wins. Slice 1 triggers: pr → sRank →
  /// (chimera handled in its own builder) → dominant-line fallback. Comeback
  /// and high-volume traits are content-only this slice (no signal threaded).
  String _phrase({
    required PostSessionState state,
    required BodyPart dominant,
    required BeastTier tier,
    required List<BodyPart> trainedParts,
    required String locale,
  }) {
    final hasPr = state.prResult?.hasNewRecords ?? false;
    if (hasPr) return _phraseByTrait('pr', locale: locale);
    if (tier == BeastTier.s) return _phraseByTrait('sRank', locale: locale);
    // A boss/legendary spread across 3+ parts intentionally borrows the
    // chimera "you faced many at once" phrase line — the kind branch already
    // rendered it as a single-line elite, but the phrase still honours the
    // breadth of the session (spec §6 priority order: chimera > line).
    if (trainedParts.length >= 3) {
      return _phraseByTrait('chimera', locale: locale);
    }
    return _lineFallbackPhrase(dominant, locale);
  }

  String _chimeraPhrase(String locale) =>
      _phraseByTrait('chimera', locale: locale);

  String _phraseByTrait(String trait, {required String locale}) {
    final entry = _catalog.phrases.firstWhere((p) => p.trait == trait);
    return entry.name.forLocale(locale);
  }

  String _lineFallbackPhrase(BodyPart line, String locale) {
    final entry = _catalog.phrases.firstWhere(
      (p) => p.trait == 'line' && p.line == line,
    );
    return entry.name.forLocale(locale);
  }

  // ─── Sigils ──────────────────────────────────────────────────────────────

  static const String _baseSigil = '◈';
  static const String _bossSigil = '⚜';
  static const String _chimeraSigil = '◬';

  // ─── Hash ────────────────────────────────────────────────────────────────

  /// FNV-1a 32-bit over the session id — a stable, fast, non-cryptographic
  /// hash so the variant/epithet/adjective picks are deterministic across
  /// runs and platforms (Dart's `String.hashCode` is NOT stable across
  /// isolates/runs and must not be used for content selection).
  int _hash(String s) {
    var h = 0x811c9dc5;
    for (var i = 0; i < s.length; i++) {
      h ^= s.codeUnitAt(i);
      h = (h * 0x01000193) & 0xffffffff;
    }
    return h;
  }
}
