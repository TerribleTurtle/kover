import 'dart:async';

import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/factories/paginated_epub_widget_factory.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/render_html.dart';
import 'package:material_ui/material_ui.dart';

Future<void> showEpubFootnoteBottomSheet(
  BuildContext context, {
  required String html,
  required PaginatedEpubPageSettings settings,
  required CssEngine cssEngine,
  FutureOr<bool> Function(String url)? onTapUrl,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: false,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => EpubFootnoteBottomSheet(
      html: html,
      settings: settings,
      cssEngine: cssEngine,
      onTapUrl: onTapUrl,
    ),
  );
}

class EpubFootnoteBottomSheet extends StatelessWidget {
  final String html;
  final PaginatedEpubPageSettings settings;
  final CssEngine cssEngine;
  final FutureOr<bool> Function(String url)? onTapUrl;

  const new({
    super.key,
    required this.html,
    required this.settings,
    required this.cssEngine,
    this.onTapUrl,
  });

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurface,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      wordSpacing: settings.wordSpacing,
      letterSpacing: settings.letterSpacing,
      fontFamily: settings.fontFamily,
    );

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.6,
        ),
        child: SingleChildScrollView(
          padding: const .all(16),
          child: RenderHtml(
            html: html,
            cssEngine: cssEngine,
            textStyle: textStyle,
            onTapUrl: onTapUrl,
            factoryBuilder: () => PaginatedEpubWidgetFactory(
              viewport: MediaQuery.sizeOf(context),
              removeParagraphIndent: settings.removeParagraphIndent,
            ),
          ),
        ),
      ),
    );
  }
}
