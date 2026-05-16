import 'package:intl/intl.dart';

/// Locale-aware number formatting helpers.
///
/// All helpers take [locale] as an explicit parameter (typically the language
/// code read from `Localizations.localeOf(context).languageCode`). This keeps
/// the helpers decoupled from any provider or global state so callers can
/// thread the active locale through their widget tree without worrying about
/// what happens if the locale system is refactored.
///
/// pt-BR expectations:
///   - `80.5 kg` (en) vs `80,5 kg` (pt) — comma as decimal separator.
///   - `1,234 kg` (en) vs `1.234 kg` (pt) — dot as thousands separator.
class AppNumberFormat {
  AppNumberFormat._();

  /// Format a weight value. Integer weights render without a decimal
  /// (e.g. `80`); fractional weights render with one decimal place using the
  /// locale's decimal separator (`80.5` en / `80,5` pt).
  static String weight(double value, {required String locale}) {
    if (value == value.roundToDouble()) {
      return NumberFormat.decimalPattern(locale).format(value.toInt());
    }
    final fmt = NumberFormat.decimalPattern(locale)
      ..minimumFractionDigits = 1
      ..maximumFractionDigits = 1;
    return fmt.format(value);
  }

  /// Format a weight with its unit suffix, e.g. `80,5 kg` / `80.5 lbs`.
  static String weightWithUnit(
    double value, {
    required String locale,
    required String unit,
  }) {
    return '${weight(value, locale: locale)} $unit';
  }

  /// Format a volume value (thousands separator, no decimals), e.g. `1.234`
  /// (pt) / `1,234` (en). Rounds to nearest integer before formatting.
  static String volume(double value, {required String locale}) {
    return NumberFormat('#,##0', locale).format(value.round());
  }

  /// Locale-aware thousand-separator integer formatting. Semantically
  /// equivalent to [volume]; named for callsites that aren't formatting
  /// set-volume specifically (XP counts, rank thresholds, etc.).
  static String integer(double value, {required String locale}) =>
      volume(value, locale: locale);

  /// Format a compact volume (e.g. `1.2k` for volumes >= 1000, `1234` below).
  /// Uses locale-appropriate decimal separator for the fractional part.
  static String compactVolume(double value, {required String locale}) {
    if (value >= 1000) {
      final fmt = NumberFormat.decimalPattern(locale)
        ..minimumFractionDigits = 1
        ..maximumFractionDigits = 1;
      return '${fmt.format(value / 1000)}k';
    }
    return NumberFormat('0', locale).format(value.round());
  }
}
