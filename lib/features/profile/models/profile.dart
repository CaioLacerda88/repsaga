// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'profile.freezed.dart';
part 'profile.g.dart';

/// User-declared gender. Phase 29 v2 Refinement #1 uses this to pick the
/// per-lift Symmetric Strength tier table (male tables = Symmetric Strength
/// reference data; female tables = strengthlevel.com snapshot 2026-05-20).
///
/// NULL on the [Profile] (`gender == null`) and [Gender.other] both fall
/// back to the male tier table — this is the documented backward-compat
/// path for users who haven't set their gender yet. Documented in
/// `docs/PROJECT.md` Phase 29 PR 2 inventory.
///
/// Serialized as the snake-case string token (`male` / `female` / `other`)
/// matching the SQL `profiles.gender` CHECK constraint.
enum Gender {
  @JsonValue('male')
  male,
  @JsonValue('female')
  female,
  @JsonValue('other')
  other,
}

@freezed
abstract class Profile with _$Profile {
  @JsonSerializable(fieldRename: FieldRename.snake)
  const factory Profile({
    required String id,
    String? displayName,
    String? fitnessLevel,
    @Default('kg') String weightUnit,
    @Default(3) int trainingFrequencyPerWeek,
    @Default('en') String locale,
    DateTime? createdAt,
    // Phase 24c — opt-in bodyweight (user-supplied via profile settings or
    // active-workout lazy prompt). Nullable: a missing value means the user
    // has not provided one yet, in which case `record_xp` falls back to a
    // bodyweight contribution of zero (entered weight only). Stored as kg
    // server-side regardless of `weightUnit` (UI layer handles conversion).
    double? bodyweightKg,
    // Phase 29 v2 — user-declared gender. Drives the per-lift Symmetric
    // Strength tier table selection (male = Symmetric Strength; female =
    // strengthlevel.com snapshot). NULL and [Gender.other] both fall back
    // to the male table — same backward-compat semantics as the Python
    // sim's `female=False` default. Settable from profile settings.
    Gender? gender,
    // Phase 32 PR 32e — public URL of the user's uploaded avatar (lives in
    // the public `avatars` Supabase Storage bucket at path
    // `{userId}.jpg`). NULL when the user has not uploaded one yet — the
    // `ProfileAvatar` widget falls back to the dominant-body-part hue
    // gradient + monogram in that case.
    //
    // Per `cluster_jsonb_payload_vs_typed_dart`: the SQL column
    // `profiles.avatar_url text` is nullable, so the Dart field mirrors
    // that with `String?`. Reads/writes route through
    // `AvatarRepository.uploadAvatar` which stamps a `?v=<timestamp>`
    // cache-bust suffix into the URL before persisting it here.
    String? avatarUrl,
    // PR 1 — canonical onboarding-completion anchor. Stamped to
    // `DateTime.now()` when [ProfileNotifier.saveOnboardingProfile] writes
    // the user's first profile row; remains NULL until then. The router
    // gate derives `needsOnboarding := session != null && profile?.onboardedAt
    // == null`, so this column is the structural guarantee that survives
    // process restart (the old `needsOnboardingProvider` StateProvider was
    // an in-memory flag that drifted on relaunch — audit defects D1/D2/D11).
    //
    // Per `cluster_jsonb_payload_vs_typed_dart`: the SQL column
    // `profiles.onboarded_at timestamptz` is nullable, so the Dart field
    // mirrors that with `DateTime?`.
    DateTime? onboardedAt,
    // Phase 38d — user-declared birth date. Drives cardio scoring against
    // the correct age-decade fitness norms server-side; NULL falls back to
    // the age-35 baseline (a valid steady state — DOB never gates cardio
    // XP). The UI captures birth-YEAR only and stores `YYYY-01-01` (LGPD
    // data-minimization — the cardio formula keys on age-decade, so the
    // year is the minimal stable representation).
    //
    // ⚠ Serialization differs from [createdAt] / [onboardedAt]: the SQL
    // column `profiles.date_of_birth` is a Postgres `date` (NOT
    // `timestamptz`), so PostgREST returns a bare `YYYY-MM-DD` string and
    // expects the same on write. A full `.toIso8601String()` timestamp
    // would be rejected by the `date` column / drift the stored value, so
    // this field routes through the date-only [_dateFromJson] / [_dateToJson]
    // converters instead of the default `DateTime` codec.
    @JsonKey(fromJson: _dateFromJson, toJson: _dateToJson)
    DateTime? dateOfBirth,
  }) = _Profile;

  factory Profile.fromJson(Map<String, dynamic> json) =>
      _$ProfileFromJson(json);
}

/// Parse a Postgres `date` (`YYYY-MM-DD`) into a date-only [DateTime].
///
/// Accepts either a bare `YYYY-MM-DD` (the PostgREST shape for a `date`
/// column) or a fuller ISO-8601 string (defensive — a future column-type
/// change or a hand-rolled fixture won't silently drop the value). Returns
/// a midnight-local [DateTime] truncated to year/month/day so equality +
/// round-trips stay stable regardless of any time component on input.
DateTime? _dateFromJson(Object? value) {
  if (value == null) return null;
  final parsed = DateTime.parse(value as String);
  return DateTime(parsed.year, parsed.month, parsed.day);
}

/// Serialize a date-only [DateTime] back to the Postgres `date` wire shape
/// (`YYYY-MM-DD`) — NOT a full `.toIso8601String()` timestamp, which the
/// `date` column would reject / coerce. Pads month + day to two digits.
String? _dateToJson(DateTime? value) {
  if (value == null) return null;
  final mm = value.month.toString().padLeft(2, '0');
  final dd = value.day.toString().padLeft(2, '0');
  return '${value.year.toString().padLeft(4, '0')}-$mm-$dd';
}
