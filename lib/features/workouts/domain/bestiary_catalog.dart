import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../rpg/models/body_part.dart';
import 'beast_card.dart';

// ─── Asset paths ─────────────────────────────────────────────────────────────

const String kBestiaryBaseAsset = 'assets/bestiary/bestiary.json';
const String kBestiaryEpithetsAsset = 'assets/bestiary/epithets.json';
const String kBestiaryChimerasAsset = 'assets/bestiary/chimeras.json';
const String kBestiaryLegendariesAsset = 'assets/bestiary/legendaries.json';
const String kBestiaryPhrasesAsset = 'assets/bestiary/achievement_phrases.json';

// ─── Entry value classes ─────────────────────────────────────────────────────

/// Parse a tier token (`"E".."S"`) into a [BeastTier]. Throws on an unknown
/// token — a malformed asset is a build-time bug, not a runtime fallback.
BeastTier _tierFromToken(String token) {
  for (final t in BeastTier.values) {
    if (t.label == token) return t;
  }
  throw ArgumentError.value(token, 'tier', 'unknown bestiary tier token');
}

/// An inline `{en, pt}` content pair. The bestiary ships bulk content this way
/// (not ARB) — see `docs/WIP.md` boundary inventory. [forLocale] resolves the
/// language with a graceful `en` fallback for any unknown locale.
@immutable
class LocalizedText {
  const LocalizedText({required this.en, required this.pt});

  factory LocalizedText.fromJson(Map<String, dynamic> json) {
    return LocalizedText(en: json['en'] as String, pt: json['pt'] as String);
  }

  final String en;
  final String pt;

  /// Resolve for a BCP-47-ish locale string. Only the primary subtag matters
  /// (`pt`, `pt_BR`, `pt-BR` all map to pt); everything else falls back to en.
  String forLocale(String locale) {
    final primary = locale.toLowerCase().split(RegExp('[-_]')).first;
    return primary == 'pt' ? pt : en;
  }
}

/// A base creature: 7 lines × 6 tiers × 2 variants = 84.
@immutable
class BaseCreatureEntry {
  const BaseCreatureEntry({
    required this.slug,
    required this.line,
    required this.tier,
    required this.variant,
    required this.name,
  });

  factory BaseCreatureEntry.fromJson(Map<String, dynamic> json) {
    return BaseCreatureEntry(
      slug: json['slug'] as String,
      line: BodyPart.fromDbValue(json['line'] as String),
      tier: _tierFromToken(json['tier'] as String),
      variant: json['variant'] as int,
      name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
    );
  }

  final String slug;
  final BodyPart line;
  final BeastTier tier;
  final int variant;
  final LocalizedText name;
}

/// A boss epithet fragment (composed into the full boss name by the resolver).
@immutable
class EpithetEntry {
  const EpithetEntry({required this.slug, required this.name});

  factory EpithetEntry.fromJson(Map<String, dynamic> json) {
    return EpithetEntry(
      slug: json['slug'] as String,
      name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
    );
  }

  final String slug;
  final LocalizedText name;
}

/// A named chimera (curated 2-part override, fixed 3/4-part, or full-body).
@immutable
class ChimeraEntry {
  const ChimeraEntry({required this.slug, required this.name});

  factory ChimeraEntry.fromJson(Map<String, dynamic> json) {
    return ChimeraEntry(
      slug: json['slug'] as String,
      name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
    );
  }

  final String slug;
  final LocalizedText name;
}

/// A session-count milestone legendary (Slice 1 ships these only).
@immutable
class LegendaryEntry {
  const LegendaryEntry({
    required this.slug,
    required this.sessionCount,
    required this.name,
  });

  factory LegendaryEntry.fromJson(Map<String, dynamic> json) {
    return LegendaryEntry(
      slug: json['slug'] as String,
      sessionCount: json['sessionCount'] as int,
      name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
    );
  }

  final String slug;
  final int sessionCount;
  final LocalizedText name;
}

/// An achievement phrase keyed by trait (+ line for the dominant-line
/// fallbacks). Lower [priority] = higher selection priority (spec §6).
@immutable
class PhraseEntry {
  const PhraseEntry({
    required this.trait,
    required this.priority,
    required this.name,
    this.line,
  });

  factory PhraseEntry.fromJson(Map<String, dynamic> json) {
    final lineToken = json['line'] as String?;
    return PhraseEntry(
      trait: json['trait'] as String,
      priority: json['priority'] as int,
      line: lineToken == null ? null : BodyPart.fromDbValue(lineToken),
      name: LocalizedText.fromJson(json['name'] as Map<String, dynamic>),
    );
  }

  final String trait;
  final int priority;
  final BodyPart? line;
  final LocalizedText name;
}

// ─── Catalog ─────────────────────────────────────────────────────────────────

/// The fully-parsed bestiary content, loaded once from the shipped JSON
/// assets and held in-process. Pure data — the [BestiaryResolver] takes a
/// loaded [BestiaryCatalog] so unit tests never touch `rootBundle`.
///
/// Mirrors `TitlesRepository`'s loader pattern: `rootBundle.loadString` +
/// `jsonDecode`, an injectable [AssetBundle] test seam, and a process-scoped
/// cache (the content never mutates at runtime).
@immutable
class BestiaryCatalog {
  const BestiaryCatalog({
    required this.baseCreatures,
    required this.epithets,
    required this.lexicon,
    required this.curatedChimeras,
    required this.chimerasByCount,
    required this.legendaries,
    required this.phrases,
  });

  /// All 84 base creatures.
  final List<BaseCreatureEntry> baseCreatures;

  /// Boss epithet pool (deterministic pick by session hash).
  final List<EpithetEntry> epithets;

  /// Per-line fusion lexicon (noun + 2 adjectives) for the generative
  /// non-curated chimera fallback.
  final List<ChimeraLexiconEntry> lexicon;

  /// Curated 2-part hybrids keyed by sorted `lineA+lineB` pair.
  final Map<String, List<ChimeraEntry>> curatedChimeras;

  /// Fixed 3/4-part + full-body chimeras keyed by parts-trained count.
  final Map<int, List<ChimeraEntry>> chimerasByCount;

  /// Session-count milestone legendaries.
  final List<LegendaryEntry> legendaries;

  /// Achievement phrases (spec §6).
  final List<PhraseEntry> phrases;

  // ─── Loader ───────────────────────────────────────────────────────────────

  static BestiaryCatalog? _cache;

  /// Visible-for-test reset hook (mirrors
  /// `TitlesRepository.debugResetCatalogCache`). Production never calls this.
  @visibleForTesting
  static void debugResetCache() {
    _cache = null;
  }

  /// Load + parse all five bestiary assets. Cached after the first call.
  /// Throws from `rootBundle` if any asset is missing (a build-time bug —
  /// the asset isn't declared in `pubspec.yaml`).
  static Future<BestiaryCatalog> load({AssetBundle? bundle}) async {
    final cached = _cache;
    if (cached != null) return cached;

    final loader = bundle ?? rootBundle;
    final catalog = parse(
      baseRaw: await loader.loadString(kBestiaryBaseAsset),
      epithetsRaw: await loader.loadString(kBestiaryEpithetsAsset),
      chimerasRaw: await loader.loadString(kBestiaryChimerasAsset),
      legendariesRaw: await loader.loadString(kBestiaryLegendariesAsset),
      phrasesRaw: await loader.loadString(kBestiaryPhrasesAsset),
    );
    _cache = catalog;
    return catalog;
  }

  /// Pure parse from raw JSON strings — the seam unit tests build against
  /// (no `rootBundle`, no async, no cache touch).
  @visibleForTesting
  static BestiaryCatalog parse({
    required String baseRaw,
    required String epithetsRaw,
    required String chimerasRaw,
    required String legendariesRaw,
    required String phrasesRaw,
  }) {
    final baseJson = jsonDecode(baseRaw) as Map<String, dynamic>;
    final baseCreatures = (baseJson['creatures'] as List)
        .cast<Map<String, dynamic>>()
        .map(BaseCreatureEntry.fromJson)
        .toList(growable: false);

    final epithetsJson = jsonDecode(epithetsRaw) as Map<String, dynamic>;
    final epithets = (epithetsJson['epithets'] as List)
        .cast<Map<String, dynamic>>()
        .map(EpithetEntry.fromJson)
        .toList(growable: false);

    final chimerasJson = jsonDecode(chimerasRaw) as Map<String, dynamic>;
    final lexicon = (chimerasJson['lexicon'] as List)
        .cast<Map<String, dynamic>>()
        .map(ChimeraLexiconEntry.fromJson)
        .toList(growable: false);

    final curated = <String, List<ChimeraEntry>>{};
    for (final row
        in (chimerasJson['curated'] as List).cast<Map<String, dynamic>>()) {
      final pair = row['pair'] as String;
      curated[pair] = (row['variants'] as List)
          .cast<Map<String, dynamic>>()
          .map(ChimeraEntry.fromJson)
          .toList(growable: false);
    }

    final byCount = <int, List<ChimeraEntry>>{};
    for (final row
        in (chimerasJson['byCount'] as List).cast<Map<String, dynamic>>()) {
      final parts = row['parts'] as int;
      byCount[parts] = (row['variants'] as List)
          .cast<Map<String, dynamic>>()
          .map(ChimeraEntry.fromJson)
          .toList(growable: false);
    }

    final legendariesJson = jsonDecode(legendariesRaw) as Map<String, dynamic>;
    final legendaries = (legendariesJson['legendaries'] as List)
        .cast<Map<String, dynamic>>()
        .map(LegendaryEntry.fromJson)
        .toList(growable: false);

    final phrasesJson = jsonDecode(phrasesRaw) as Map<String, dynamic>;
    final phrases = (phrasesJson['phrases'] as List)
        .cast<Map<String, dynamic>>()
        .map(PhraseEntry.fromJson)
        .toList(growable: false);

    return BestiaryCatalog(
      baseCreatures: baseCreatures,
      epithets: epithets,
      lexicon: lexicon,
      curatedChimeras: curated,
      chimerasByCount: byCount,
      legendaries: legendaries,
      phrases: phrases,
    );
  }
}

/// One line's fusion lexicon: a chimera noun + 2 adjectives, for the
/// generative non-curated 2-part fallback (spec §3a/§3b).
@immutable
class ChimeraLexiconEntry {
  const ChimeraLexiconEntry({
    required this.line,
    required this.noun,
    required this.adjectives,
  });

  factory ChimeraLexiconEntry.fromJson(Map<String, dynamic> json) {
    return ChimeraLexiconEntry(
      line: BodyPart.fromDbValue(json['line'] as String),
      noun: LocalizedText.fromJson(json['noun'] as Map<String, dynamic>),
      adjectives: (json['adjectives'] as List)
          .cast<Map<String, dynamic>>()
          .map(LocalizedText.fromJson)
          .toList(growable: false),
    );
  }

  final BodyPart line;
  final LocalizedText noun;
  final List<LocalizedText> adjectives;
}
