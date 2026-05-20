import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../core/theme/app_theme.dart';
import '../../l10n/app_localizations.dart';

/// A scrollable screen that loads a markdown document from an asset and
/// renders it with the app theme.
///
/// Used for Privacy Policy and Terms of Service screens — pass the asset
/// path of the markdown file (e.g. `assets/legal/privacy_policy.md`) and a
/// title for the app bar.
///
/// The asset is loaded via [DefaultAssetBundle.of], so tests can inject a
/// fake bundle by wrapping the widget with [DefaultAssetBundle]. The future
/// is cached in state so rebuilds do not re-trigger the load.
class LegalDocScreen extends StatefulWidget {
  const LegalDocScreen({
    super.key,
    required this.title,
    required this.assetPath,
  });

  final String title;
  final String assetPath;

  @override
  State<LegalDocScreen> createState() => _LegalDocScreenState();
}

class _LegalDocScreenState extends State<LegalDocScreen> {
  Future<String>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= DefaultAssetBundle.of(context).loadString(widget.assetPath);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: FutureBuilder<String>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Text(AppLocalizations.of(context).failedToLoadDocument),
            );
          }
          return Markdown(
            data: snapshot.data!,
            padding: const EdgeInsets.all(20),
            selectable: true,
            styleSheet: MarkdownStyleSheet.fromTheme(theme).copyWith(
              // H1/H2/H3 of legal docs are content headings — Rajdhani
              // [headline] register sized down for inline hierarchy. H2/H3
              // drop to [title] (Inter→Barlow) for paragraph-tier readability.
              h1: AppTextStyles.headline.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              h2: AppTextStyles.title.copyWith(fontSize: 20),
              h3: AppTextStyles.title,
              p: AppTextStyles.body,
              listBullet: AppTextStyles.body,
              blockSpacing: 12,
            ),
          );
        },
      ),
    );
  }
}
