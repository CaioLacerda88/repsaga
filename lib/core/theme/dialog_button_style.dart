import 'package:flutter/material.dart';

/// Shared `ButtonStyle` for dialog action buttons across the app.
///
/// Pins a Material 2.5.5 AAA-compliant minimum tap target (64w × 48h dp) on
/// every dialog action — Cancel/OK/Discard/Save/etc. — so the contract
/// survives in face of someone overriding `materialTapTargetSize` on an
/// ancestor button theme. Material 3's default already inflates the
/// hit-test region to 48dp via `MaterialTapTargetSize.padded`, but that's
/// implicit; declaring `minimumSize` here makes the floor a structural
/// guarantee at the call site.
///
/// **Scope:** dialog `TextButton` / `FilledButton` actions only. Do NOT
/// apply to inline body buttons or non-dialog surfaces — those have their
/// own ergonomic budgets (some intentionally smaller, e.g. inline "fill
/// remaining" affordance in the active-workout flow).
///
/// Usage:
/// ```dart
/// TextButton(
///   onPressed: ...,
///   style: dialogTextButtonStyle,
///   child: Text(l10n.cancel),
/// );
/// ```
///
/// Composes safely with caller overrides:
/// ```dart
/// TextButton(
///   style: dialogTextButtonStyle.copyWith(
///     foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error),
///   ),
///   ...
/// );
/// ```
///
/// Closes Family 4 of the active-workout exploratory pass (AW-EX-F-BR1-09).
final ButtonStyle dialogTextButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(64, 48),
);
