import 'package:flutter/material.dart';

/// Shared style for dialog `TextButton` actions; ensures a 48dp tap-target
/// floor regardless of theme defaults.
///
/// Scope: dialog actions only — not for app-wide TextButtons. Inline body
/// buttons have their own ergonomic budgets.
///
/// For destructive variants, compose on top:
/// ```dart
/// TextButton(
///   style: dialogTextButtonStyle.copyWith(
///     foregroundColor: WidgetStatePropertyAll(theme.colorScheme.error),
///   ),
///   onPressed: ...,
///   child: Text(l10n.discard),
/// );
/// ```
final ButtonStyle dialogTextButtonStyle = TextButton.styleFrom(
  minimumSize: const Size(64, 48),
);

/// Shared style for dialog `FilledButton` actions; mirrors the 48dp floor
/// used by [dialogTextButtonStyle] so confirm-and-text actions land at the
/// same minimum hit-test height. Compose with `.copyWith(...)` if a caller
/// needs a custom foreground/background.
final ButtonStyle dialogFilledButtonStyle = FilledButton.styleFrom(
  minimumSize: const Size(64, 48),
);
