import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';

/// A reusable section header label used across the app.
///
/// Renders the title in [AppTextStyles.label] at 13dp — Inter 600 with the
/// canonical eyebrow tracking (+0.12em) — at 85% onSurface alpha for WCAG
/// AA contrast on the dark theme. The call site is responsible for passing
/// an already-uppercased string (the ARB key supplies the casing).
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    required this.title,
    this.semanticsIdentifier,
    super.key,
  });

  final String title;

  /// Optional Semantics identifier for locale-independent E2E selectors.
  final String? semanticsIdentifier;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Text(
      title,
      style: AppTextStyles.label.copyWith(
        fontSize: 13,
        letterSpacing: 0.12 * 13,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
      ),
    );
    if (semanticsIdentifier != null) {
      return Semantics(
        container: true,
        identifier: semanticsIdentifier,
        child: text,
      );
    }
    return text;
  }
}
