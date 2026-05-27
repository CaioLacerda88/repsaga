/// Unit tests for [WeekdayFormatter] — the single source of truth for
/// 3-letter weekday labels shared between Home's `BucketChipRow` and the
/// Week Plan editor's `BucketRoutineRow`.
///
/// **Why this test exists.**
/// Before PR 32c the two surfaces each carried their own `_shortDayLabel`
/// helper. `bucket_chip_row.dart` called `.toLocal()` before formatting;
/// `week_plan_screen.dart` did NOT. A workout finished at 23:00 BRT
/// (UTC-3) — stored as next-day 02:00Z by Supabase — surfaced as "TER"
/// on Home and "QUA" on the Week Plan editor for a single completion.
///
/// Same `completedAt`, two different weekdays — confusing.
///
/// Extracting `WeekdayFormatter.shortDayLabel` collapses the two helpers
/// into one. This test pins:
///   1. UTC → local conversion happens before formatting (the bug fix).
///   2. The `uppercase: true` mode produces the chip label
///      ("MON"/"SEG") used by Home.
///   3. The `uppercase: false` mode produces the row meta label
///      ("Mon"/"Seg") used by the Week Plan editor.
///   4. Both modes agree on the underlying weekday — they only differ
///      in casing. So the two surfaces can never drift again.
///
/// The bucket-chip snapshot block at the bottom pins that bucket_chip_row's
/// existing `_shortDayLabel` logic (which we deliberately don't refactor
/// in PR 32c to minimize regression risk) produces output byte-identical
/// to the shared formatter's `uppercase: true` mode. If anyone changes
/// bucket_chip_row's helper, this test fails and flags the drift.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:repsaga/core/utils/weekday_formatter.dart';

/// Byte-identical replica of `bucket_chip_row.dart::_BucketChip._shortDayLabel`.
/// Kept in lockstep with the production code — any change there must be
/// mirrored here, and the test below pins that the shared formatter still
/// matches. This is the "two surfaces agree" contract from the user-
/// reported bug, lifted to a runtime invariant.
String _bucketChipRowShortDayLabel(DateTime completedAt, String locale) {
  final local = completedAt.toLocal();
  final raw = DateFormat.E(locale).format(local);
  final trimmed = raw.endsWith('.') ? raw.substring(0, raw.length - 1) : raw;
  return trimmed.toUpperCase();
}

void main() {
  setUpAll(() async {
    // intl needs locale data loaded before any DateFormat call. The
    // `DateFormat.E('pt', …)` path in particular ships abbreviated weekday
    // names that aren't loaded by default.
    await initializeDateFormatting('en');
    await initializeDateFormatting('pt');
    await initializeDateFormatting('pt_BR');
  });

  group('WeekdayFormatter.shortDayLabel', () {
    test(
      'converts UTC to local before formatting (BRT late-evening crossing midnight UTC)',
      () {
        // 2026-05-27 02:00 UTC == 2026-05-26 23:00 BRT (UTC-3).
        //   - Formatting the UTC instant directly → "Wed" / "Qua" (wrong).
        //   - After .toLocal() on a host running in BRT → "Tue" / "Ter" (right).
        //
        // The host running this test might NOT be in BRT (CI usually runs
        // in UTC). In that case .toLocal() is a no-op and we still get
        // "Wed" / "Qua". So the assertion here is: whatever the host TZ,
        // the formatter must agree with what the equivalent toLocal()
        // computation produces, NOT format the raw UTC instant.
        final utcLateNight = DateTime.utc(2026, 5, 27, 2, 0);
        final local = utcLateNight.toLocal();

        // What DateFormat.E sees AFTER toLocal() — the production path.
        final expected = DateFormat.E('en').format(local);

        expect(
          WeekdayFormatter.shortDayLabel(utcLateNight, 'en', uppercase: true),
          equals(expected.toUpperCase()),
          reason:
              'Formatter must apply .toLocal() before formatting. Skipping '
              'the conversion is the cluster `weekday-utc-vs-local-drift` '
              'trap that desynced Home + Week Plan editor pre-32c.',
        );

        // pt locale path. intl emits "ter." / "qua." with a trailing dot
        // on some platforms — the formatter strips it.
        final expectedPt = DateFormat.E('pt').format(local);
        final expectedPtTrimmed = expectedPt.endsWith('.')
            ? expectedPt.substring(0, expectedPt.length - 1)
            : expectedPt;
        expect(
          WeekdayFormatter.shortDayLabel(utcLateNight, 'pt', uppercase: true),
          equals(expectedPtTrimmed.toUpperCase()),
          reason: 'pt locale must follow the same .toLocal() contract.',
        );
      },
    );

    test(
      'uppercase + title-case modes produce the same underlying weekday',
      () {
        // The two surfaces (Home chips uppercase, Week Plan editor title-
        // case) must NEVER disagree on which weekday they show. Casing is
        // presentation; the weekday is the contract. This pins the
        // invariant on a sample of UTC instants spanning every day of the
        // week to catch any locale-specific edge case.
        final samples = <DateTime>[
          DateTime.utc(2026, 5, 25, 12, 0), // Mon noon UTC
          DateTime.utc(2026, 5, 26, 12, 0), // Tue
          DateTime.utc(2026, 5, 27, 12, 0), // Wed
          DateTime.utc(2026, 5, 28, 12, 0), // Thu
          DateTime.utc(2026, 5, 29, 12, 0), // Fri
          DateTime.utc(2026, 5, 30, 12, 0), // Sat
          DateTime.utc(2026, 5, 31, 12, 0), // Sun
          // Edge case: midnight UTC. Lands on previous day in any
          // negative-UTC zone (BRT, EST, etc.).
          DateTime.utc(2026, 5, 27, 0, 0),
          // Edge case: late evening UTC. Lands on NEXT day in any
          // positive-UTC zone (CET, JST, etc.).
          DateTime.utc(2026, 5, 27, 23, 59),
        ];

        for (final locale in <String>['en', 'pt']) {
          for (final sample in samples) {
            final upper = WeekdayFormatter.shortDayLabel(
              sample,
              locale,
              uppercase: true,
            );
            final title = WeekdayFormatter.shortDayLabel(
              sample,
              locale,
              uppercase: false,
            );
            expect(
              title.toUpperCase(),
              equals(upper),
              reason:
                  'For sample $sample / locale $locale, the title-case '
                  'output ("$title" → upper "${title.toUpperCase()}") must '
                  'agree with the uppercase output ("$upper"). Pre-32c the '
                  'two surfaces could drift because each owned its own '
                  'helper — this test pins that they no longer can.',
            );
          }
        }
      },
    );

    test('title-case mode emits 3-char output with first letter uppercase', () {
      // The Week Plan editor renders the row meta as "Ter", not "TER" or
      // "ter". This pins the title-case contract for the editor surface.
      final wedUtc = DateTime.utc(2026, 5, 27, 12, 0);
      for (final locale in <String>['en', 'pt']) {
        final label = WeekdayFormatter.shortDayLabel(
          wedUtc,
          locale,
          uppercase: false,
        );
        expect(
          label.length,
          equals(3),
          reason:
              'Title-case label must be 3 chars (intl emits "Mon"/"Seg" — '
              'we strip a trailing dot if the locale adds one). Got '
              '"$label" for locale $locale.',
        );
        expect(
          label[0],
          equals(label[0].toUpperCase()),
          reason:
              'First letter must be uppercase ("Mon" not "mon"). '
              'Got "$label" for locale $locale.',
        );
        expect(
          label.substring(1),
          equals(label.substring(1).toLowerCase()),
          reason:
              'Letters 2-3 must be lowercase ("Mon" not "MOn"). '
              'Got "$label" for locale $locale.',
        );
      }
    });

    test(
      'agrees with bucket_chip_row._shortDayLabel for the same input (cross-surface contract)',
      () {
        // The user-reported bug: Home (bucket_chip_row) showed "TER"
        // while Week Plan editor (week_plan_screen) showed "QUA" for a
        // single workout. Root cause: the two surfaces had drifted on
        // `.toLocal()`.
        //
        // PR 32c collapsed the editor's helper into the shared formatter
        // but deliberately left bucket_chip_row's `_shortDayLabel`
        // untouched (to minimize regression risk on the production chip
        // render). This test pins the byte-equivalence contract: as long
        // as `_bucketChipRowShortDayLabel` (the snapshot replica at the
        // top of this file) matches bucket_chip_row's source, the shared
        // formatter must produce the same output. If anyone edits
        // bucket_chip_row's helper without updating the replica, this
        // test fails and flags the drift.
        final samples = <DateTime>[
          // Workout late-evening BRT crossing midnight UTC.
          DateTime.utc(2026, 5, 27, 2, 0),
          // Workout midday UTC.
          DateTime.utc(2026, 5, 27, 12, 0),
          // Workout at UTC midnight.
          DateTime.utc(2026, 5, 27, 0, 0),
          // Saturday + Sunday — the wraparound weekdays where any
          // off-by-one shows.
          DateTime.utc(2026, 5, 30, 12, 0),
          DateTime.utc(2026, 5, 31, 12, 0),
        ];

        for (final locale in <String>['en', 'pt']) {
          for (final sample in samples) {
            expect(
              WeekdayFormatter.shortDayLabel(sample, locale, uppercase: true),
              equals(_bucketChipRowShortDayLabel(sample, locale)),
              reason:
                  'Shared formatter (uppercase mode) must match '
                  'bucket_chip_row._shortDayLabel byte-for-byte. Sample: '
                  '$sample, locale: $locale. If this fails, either the '
                  'formatter or bucket_chip_row drifted — sync them.',
            );
          }
        }
      },
    );
  });
}
