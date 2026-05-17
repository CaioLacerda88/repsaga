/// Unit tests for [TitlesRepository] — focused on the asset-loading +
/// catalog-shape contract. The Supabase plumbing (earned_titles SELECT/UPDATE)
/// mirrors patterns already covered by analytics/profile repository tests
/// and is exercised end-to-end in the Phase 18c E2E suite (rank-up
/// celebration spec). Re-faking it here would only test the fake.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repsaga/core/exceptions/app_exception.dart';
import 'package:repsaga/features/rpg/data/titles_repository.dart';
import 'package:repsaga/features/rpg/models/body_part.dart';
import 'package:repsaga/features/rpg/models/title.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

/// Test bundle that routes asset lookups to per-key payloads. The body-part
/// loader uses the legacy schema (no `kind` field, injected by the loader),
/// while the character-level + cross-build loaders expect entries with the
/// `kind` discriminator already present. A single-payload fake would feed
/// the wrong shape into the discriminated loaders and trigger
/// "Invalid union type 'null'" — keep the per-key map explicit.
class _FakeBundle extends CachingAssetBundle {
  _FakeBundle({String? bodyPart, String? characterLevel, String? crossBuild})
    : _payloads = {
        kTitlesCatalogAsset: bodyPart ?? _emptyCatalog(),
        kCharacterLevelTitlesCatalogAsset: characterLevel ?? _emptyCatalog(),
        kCrossBuildTitlesCatalogAsset: crossBuild ?? _emptyCatalog(),
      };

  final Map<String, String> _payloads;
  int loadStringCalls = 0;

  @override
  Future<ByteData> load(String key) async {
    throw UnimplementedError('not used by these tests');
  }

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    loadStringCalls += 1;
    final payload = _payloads[key];
    if (payload == null) {
      throw StateError('Unmocked asset key in test fake: $key');
    }
    return payload;
  }
}

String _emptyCatalog() => jsonEncode({'version': 1, 'titles': <dynamic>[]});

/// Minimal fake — TitlesRepository extends BaseRepository, so the constructor
/// must accept a SupabaseClient. The catalog tests never invoke any client
/// method, so the fake only needs to exist (not respond).
class _UnusedClient extends Fake implements supabase.SupabaseClient {}

// ---------------------------------------------------------------------------
// Fake plumbing for `equipTitle`.
//
// equipTitle calls:
//   1. _client.auth.currentUser           → needs a fake GoTrueClient
//   2. _client.from('earned_titles')
//        .update({'is_active': false})
//        .eq('user_id', uid).eq('is_active', true)
//   3. _client.from('earned_titles')
//        .update({'is_active': true})
//        .eq('user_id', uid).eq('title_id', slug)
//
// We capture every `update` payload and every `upsert` invocation so the
// contract test can assert: TWO updates fired AND zero upserts fired.
// ---------------------------------------------------------------------------

class _FakeAuthClient extends Fake implements supabase.GoTrueClient {
  _FakeAuthClient(this._user);
  final supabase.User? _user;

  @override
  supabase.User? get currentUser => _user;
}

class _FakeAuthSupabaseClient extends Fake implements supabase.SupabaseClient {
  _FakeAuthSupabaseClient(this._builder, this._auth);
  final _EquipFakeQueryBuilder _builder;
  final _FakeAuthClient _auth;

  @override
  supabase.GoTrueClient get auth => _auth;

  @override
  supabase.SupabaseQueryBuilder from(String table) => _builder;
}

// ignore: must_be_immutable
class _EquipFakeQueryBuilder extends Fake
    implements supabase.SupabaseQueryBuilder {
  final List<Map<String, dynamic>> capturedUpdates = [];
  final List<Map<String, dynamic>> capturedUpserts = [];

  @override
  _EquipFakeFilterBuilder update(Map values) {
    capturedUpdates.add(Map<String, dynamic>.from(values));
    return _EquipFakeFilterBuilder();
  }

  @override
  _EquipFakeFilterBuilder upsert(
    dynamic values, {
    String? onConflict,
    bool ignoreDuplicates = false,
    bool defaultToNull = true,
  }) {
    capturedUpserts.add(Map<String, dynamic>.from(values as Map));
    return _EquipFakeFilterBuilder();
  }
}

class _EquipFakeFilterBuilder extends Fake
    implements supabase.PostgrestFilterBuilder<List<Map<String, dynamic>>> {
  @override
  _EquipFakeFilterBuilder eq(String column, Object value) => this;

  @override
  Future<S> then<S>(
    FutureOr<S> Function(List<Map<String, dynamic>>) onValue, {
    Function? onError,
  }) {
    return Future.value(onValue(const <Map<String, dynamic>>[]));
  }
}

supabase.User _fakeUser({String id = 'user-equip-001'}) {
  return supabase.User(
    id: id,
    appMetadata: const {},
    userMetadata: const {},
    aud: 'authenticated',
    createdAt: '2026-01-01T00:00:00Z',
    isAnonymous: false,
  );
}

String _validCatalog() {
  return jsonEncode({
    'version': 1,
    'titles': [
      {'slug': 'chest_r5_initiate', 'body_part': 'chest', 'rank_threshold': 5},
      {'slug': 'chest_r10_plate', 'body_part': 'chest', 'rank_threshold': 10},
      {'slug': 'legs_r5_walker', 'body_part': 'legs', 'rank_threshold': 5},
      {'slug': 'back_r5_lattice', 'body_part': 'back', 'rank_threshold': 5},
    ],
  });
}

void main() {
  setUp(() {
    // The static catalog cache leaks across tests by design (it's an
    // app-lifetime cache in production). Reset between tests so each
    // assertion sees a fresh load.
    TitlesRepository.debugResetCatalogCache();
  });

  group('TitlesRepository.loadCatalog', () {
    test('parses every entry with body_part and rank_threshold', () async {
      final bundle = _FakeBundle(bodyPart: _validCatalog());
      final repo = TitlesRepository(_UnusedClient(), bundle: bundle);

      final catalog = await repo.loadCatalog();

      expect(catalog, hasLength(4));
      expect(catalog.first.slug, 'chest_r5_initiate');
      // Legacy v1 catalog entries deserialize as BodyPartTitle (loader
      // injects `kind: body_part`). Pattern-match instead of using a
      // hypothetical .bodyPart getter — the sealed union exposes variant
      // fields only after destructuring.
      final first = catalog.first;
      expect(first, isA<BodyPartTitle>());
      final bodyPart = first as BodyPartTitle;
      expect(bodyPart.bodyPart, BodyPart.chest);
      expect(bodyPart.rankThreshold, 5);
    });

    test('caches the parsed catalog (second call reuses load)', () async {
      final bundle = _FakeBundle(bodyPart: _validCatalog());
      final repo = TitlesRepository(_UnusedClient(), bundle: bundle);

      await repo.loadCatalog();
      await repo.loadCatalog();

      // The static cache short-circuits the second call. The first call
      // requests 3 assets (body-part + character-level + cross-build); the
      // second call hits the in-memory cache and triggers no further loads.
      expect(bundle.loadStringCalls, 3);
    });
  });

  group('TitlesRepository.lookupBySlug', () {
    test('returns the matching catalog entry', () async {
      final repo = TitlesRepository(
        _UnusedClient(),
        bundle: _FakeBundle(bodyPart: _validCatalog()),
      );

      final title = await repo.lookupBySlug('chest_r10_plate');
      expect(title, isNotNull);
      expect(title, isA<BodyPartTitle>());
      final bodyPart = title! as BodyPartTitle;
      expect(bodyPart.bodyPart, BodyPart.chest);
      expect(bodyPart.rankThreshold, 10);
    });

    test('returns null for an unknown slug', () async {
      final repo = TitlesRepository(
        _UnusedClient(),
        bundle: _FakeBundle(bodyPart: _validCatalog()),
      );

      expect(await repo.lookupBySlug('totally_made_up_slug'), isNull);
    });
  });

  group('TitlesRepository.forBodyPart', () {
    test(
      'returns only entries for the requested body part, ascending',
      () async {
        final repo = TitlesRepository(
          _UnusedClient(),
          bundle: _FakeBundle(bodyPart: _validCatalog()),
        );

        final chest = await repo.forBodyPart(BodyPart.chest);
        expect(chest.cast<BodyPartTitle>().map((t) => t.rankThreshold), [
          5,
          10,
        ]);

        final legs = await repo.forBodyPart(BodyPart.legs);
        expect(legs.map((t) => t.slug), ['legs_r5_walker']);
      },
    );

    test(
      'returns empty list for a body part absent from the catalog',
      () async {
        final repo = TitlesRepository(
          _UnusedClient(),
          bundle: _FakeBundle(bodyPart: _validCatalog()),
        );

        // Cardio has no entries in v1.
        expect(await repo.forBodyPart(BodyPart.cardio), isEmpty);
      },
    );
  });

  group('EarnedTitleRow.fromJson', () {
    Map<String, dynamic> validRow() => <String, dynamic>{
      'user_id': 'u-001',
      'title_id': 'chest_r5_initiate',
      'earned_at': '2026-04-30T12:00:00Z',
      'is_active': true,
    };

    test('parses a well-formed row', () {
      final row = EarnedTitleRow.fromJson(validRow());
      expect(row.userId, 'u-001');
      expect(row.titleId, 'chest_r5_initiate');
      expect(row.isActive, isTrue);
    });

    test('treats missing is_active as false (schema default)', () {
      final json = validRow()..remove('is_active');
      expect(EarnedTitleRow.fromJson(json).isActive, isFalse);
    });

    test('treats null is_active as false', () {
      final json = validRow()..['is_active'] = null;
      expect(EarnedTitleRow.fromJson(json).isActive, isFalse);
    });

    test('throws DatabaseException naming user_id when missing (BUG-010)', () {
      final json = validRow()..remove('user_id');
      expect(
        () => EarnedTitleRow.fromJson(json),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.message,
            'message',
            contains('user_id'),
          ),
        ),
      );
    });

    test('throws DatabaseException naming title_id when missing', () {
      final json = validRow()..remove('title_id');
      expect(
        () => EarnedTitleRow.fromJson(json),
        throwsA(
          isA<DatabaseException>().having(
            (e) => e.message,
            'message',
            contains('title_id'),
          ),
        ),
      );
    });

    test(
      'throws DatabaseException with timestamp code when earned_at malformed',
      () {
        final json = validRow()..['earned_at'] = 'not-a-timestamp';
        expect(
          () => EarnedTitleRow.fromJson(json),
          throwsA(
            isA<DatabaseException>().having(
              (e) => e.code,
              'code',
              'json_bad_timestamp',
            ),
          ),
        );
      },
    );

    test(
      'throws DatabaseException on wrong-typed is_active (schema drift)',
      () {
        final json = validRow()..['is_active'] = 'yes';
        expect(
          () => EarnedTitleRow.fromJson(json),
          throwsA(isA<DatabaseException>()),
        );
      },
    );
  });

  group('Shipped catalogs (integration with rootBundle)', () {
    test('loads, parses, and contains all 90 v1 entries (78 body-part + 7 '
        'character-level + 5 cross-build)', () async {
      // Locks the shipped assets against accidental edits — slug count
      // is a structural invariant of the v1 contract.
      TestWidgetsFlutterBinding.ensureInitialized();
      // Not faking — read the actual assets registered in pubspec.yaml.
      // If any asset is missing or malformed, this fails.
      final repo = TitlesRepository(_UnusedClient());
      final catalog = await repo.loadCatalog();
      expect(catalog, hasLength(90));

      final bodyPartTitles = catalog.whereType<BodyPartTitle>().toList();
      final characterLevelTitles = catalog
          .whereType<CharacterLevelTitle>()
          .toList();
      final crossBuildTitles = catalog.whereType<CrossBuildTitle>().toList();

      expect(bodyPartTitles, hasLength(78));
      expect(characterLevelTitles, hasLength(7));
      expect(crossBuildTitles, hasLength(5));

      // Body-part bucket: six body parts × 13 thresholds
      // (5,10,15,20,25,30,40,50,60,70,80,90,99).
      final perBodyPart = <BodyPart, int>{};
      for (final t in bodyPartTitles) {
        perBodyPart[t.bodyPart] = (perBodyPart[t.bodyPart] ?? 0) + 1;
      }
      expect(perBodyPart[BodyPart.chest], 13);
      expect(perBodyPart[BodyPart.back], 13);
      expect(perBodyPart[BodyPart.legs], 13);
      expect(perBodyPart[BodyPart.shoulders], 13);
      expect(perBodyPart[BodyPart.arms], 13);
      expect(perBodyPart[BodyPart.core], 13);

      // Terminal Rank 99 entry exists for every body part.
      for (final bp in [
        BodyPart.chest,
        BodyPart.back,
        BodyPart.legs,
        BodyPart.shoulders,
        BodyPart.arms,
        BodyPart.core,
      ]) {
        final terminal = bodyPartTitles.where(
          (t) => t.bodyPart == bp && t.rankThreshold == 99,
        );
        expect(terminal, hasLength(1), reason: '${bp.dbValue} R99 missing');
      }

      // Character-level thresholds — exact set per spec §10.2.
      final levels = characterLevelTitles.map((t) => t.levelThreshold).toList()
        ..sort();
      expect(levels, [10, 25, 50, 75, 100, 125, 148]);

      // Cross-build trigger ids — exact set per spec §10.3.
      final triggers = crossBuildTitles.map((t) => t.triggerId).toSet();
      expect(triggers, {
        CrossBuildTriggerId.pillarWalker,
        CrossBuildTriggerId.broadShouldered,
        CrossBuildTriggerId.evenHanded,
        CrossBuildTriggerId.ironBound,
        CrossBuildTriggerId.sagaForged,
      });
    });
  });

  group('TitlesRepository.equipTitle', () {
    test('should toggle is_active without INSERTing', () async {
      // Contract: the `earned_titles` row is guaranteed to exist before
      // equipTitle fires — INSERTed server-side by `record_session_xp_batch`
      // (migration 00060) at detection time, or via the one-shot
      // `backfill_earned_titles` RPC (migration 00061) for pre-26d users.
      //
      // equipTitle must therefore be a PURE two-step UPDATE: clear any active
      // flag, then set the target row's `is_active = true`. A regression that
      // re-introduces an UPSERT would silently re-enable the original
      // "row doesn't exist when equip fires" bug, letting the client equip a
      // title for a row it shouldn't have produced — and re-arming the rare
      // race where a user equips a title they haven't actually earned.
      final builder = _EquipFakeQueryBuilder();
      final auth = _FakeAuthClient(_fakeUser(id: 'user-equip-001'));
      final repo = TitlesRepository(_FakeAuthSupabaseClient(builder, auth));

      await repo.equipTitle('chest_r5_initiate_of_the_forge');

      // No UPSERT path remains; an UPSERT here would be a regression.
      expect(builder.capturedUpserts, isEmpty);

      // Exactly two UPDATEs: one clearing the prior active row, one setting
      // the new active row. Asserting the payload shapes pins the contract
      // against silent refactors (e.g. someone collapsing both into a single
      // statement, which would break the at-most-one-active invariant).
      expect(builder.capturedUpdates, hasLength(2));
      expect(builder.capturedUpdates[0], {'is_active': false});
      expect(builder.capturedUpdates[1], {'is_active': true});
    });

    test('is a no-op when the user is not authenticated', () async {
      // Defensive guard already in the implementation — pinning it so a
      // future refactor doesn't drop the early-return and surface a null
      // user.id to `eq('user_id', …)` (which would map to an opaque
      // PostgrestException at runtime).
      final builder = _EquipFakeQueryBuilder();
      final auth = _FakeAuthClient(null);
      final repo = TitlesRepository(_FakeAuthSupabaseClient(builder, auth));

      await repo.equipTitle('chest_r5_initiate_of_the_forge');

      expect(builder.capturedUpdates, isEmpty);
      expect(builder.capturedUpserts, isEmpty);
    });
  });
}
