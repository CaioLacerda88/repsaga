import '../../../core/format/number_format.dart';

/// Pure formatting / conversion helpers for the cardio logging surface
/// (Phase 38b). Kept widget-free so unit tests run without a pump and the
/// Phase 38c earning pipeline can reuse the same conversions.
abstract final class CardioFormat {
  /// Meters per mile — the international mile, exact by definition.
  static const double metersPerMile = 1609.344;

  /// Meters per kilometer.
  static const double metersPerKm = 1000.0;

  /// Formats a duration as `m:ss` / `mm:ss` (e.g. `30:00`, `8:05`,
  /// `125:30`). Minutes are NOT wrapped into hours — a 95-minute ride reads
  /// `95:00`, matching the stepper's single mm:ss register (the locked
  /// mockup has no hour grammar).
  static String duration(int totalSeconds) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final minutes = clamped ~/ 60;
    final seconds = clamped % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Parses user input from the duration dialog back to seconds.
  ///
  /// Accepts `mm:ss` (`28:45`), bare minutes (`28` → 1680s), and the pt-BR
  /// comma habit for the colon position is NOT supported (a comma in a
  /// duration is ambiguous). Returns null for anything unparseable,
  /// negative, or with seconds >= 60.
  static int? parseDuration(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains(':')) {
      final parts = trimmed.split(':');
      if (parts.length != 2) return null;
      final minutes = int.tryParse(parts[0]);
      final seconds = int.tryParse(parts[1]);
      if (minutes == null || seconds == null) return null;
      if (minutes < 0 || seconds < 0 || seconds >= 60) return null;
      return minutes * 60 + seconds;
    }
    final minutes = int.tryParse(trimmed);
    if (minutes == null || minutes < 0) return null;
    return minutes * 60;
  }

  /// The display distance unit derived from the profile weight unit:
  /// metric lifters (`kg`) log kilometers, imperial lifters (`lbs`) log
  /// miles. No separate distance-unit preference exists (deliberate — one
  /// unit-system toggle, not two).
  static String distanceUnitFor(String weightUnit) =>
      weightUnit == 'lbs' ? 'mi' : 'km';

  /// Converts canonical meters to the display unit value.
  static double metersToDisplay(double meters, String distanceUnit) =>
      distanceUnit == 'mi' ? meters / metersPerMile : meters / metersPerKm;

  /// Converts a display-unit value back to canonical meters.
  static double displayToMeters(double value, String distanceUnit) =>
      distanceUnit == 'mi' ? value * metersPerMile : value * metersPerKm;

  /// Formats a distance (canonical meters) in the display unit with the
  /// locale decimal separator — `5.2` (en) / `5,2` (pt). One decimal when
  /// fractional, integer otherwise (reuses the weight formatter's rules).
  static String distanceValue(
    double meters, {
    required String distanceUnit,
    required String locale,
  }) {
    return AppNumberFormat.weight(
      metersToDisplay(meters, distanceUnit),
      locale: locale,
    );
  }

  /// Parses a user-entered distance (display unit) accepting `.` or `,` as
  /// the decimal separator, returning canonical METERS. Null for invalid /
  /// negative input.
  static double? parseDistanceToMeters(String text, String distanceUnit) {
    final normalised = text.trim().replaceAll(',', '.');
    if (normalised.isEmpty) return null;
    final parsed = double.tryParse(normalised);
    if (parsed == null || parsed < 0) return null;
    return displayToMeters(parsed, distanceUnit);
  }
}
