import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_anchor_target.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/factories/paginated_epub_widget_factory.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/utils/constants/layout_constants.dart';
import 'package:material_ui/material_ui.dart';

/// Opens a modal bottom sheet previewing footnote [html] using [settings].
Future<void> showEpubFootnoteBottomSheet({
  required BuildContext context,
  required String html,
  required PaginatedEpubPageSettings settings,
  required CssEngine cssEngine,
  ValueChanged<EpubAnchorTarget>? onAnchorTap,
}) {
  final maxHeight = MediaQuery.sizeOf(context).height * 0.6;
  final animation = settings.reduceAnimations
      ? const AnimationStyle(duration: .zero, reverseDuration: .zero)
      : null;

  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: maxHeight,
      maxWidth: LayoutBreakpoints.medium,
    ),
    sheetAnimationStyle: animation,
    builder: (sheetContext) => EpubFootnoteBottomSheet(
      html: html,
      settings: settings,
      cssEngine: cssEngine,
      maxHeight: maxHeight,
      onAnchorTap: onAnchorTap == null
          ? null
          : (target) {
              if (sheetContext.mounted) {
                Navigator.of(sheetContext).pop();
              }
              onAnchorTap(target);
            },
    ),
  );
}

/// Modal bottom sheet body that renders a selectable EPUB footnote subtree.
class EpubFootnoteBottomSheet extends StatelessWidget {
  final String html;
  final PaginatedEpubPageSettings settings;
  final CssEngine cssEngine;
  final double maxHeight;
  final ValueChanged<EpubAnchorTarget>? onAnchorTap;

  const new({
    super.key,
    required this.html,
    required this.settings,
    required this.cssEngine,
    required this.maxHeight,
    this.onAnchorTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurface,
      fontSize: settings.fontSize,
      height: settings.lineHeight,
      wordSpacing: settings.wordSpacing,
      letterSpacing: settings.letterSpacing,
      fontFamily: settings.fontFamily,
    );

    return SelectionArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const .only(
            left: LayoutConstants.largePadding,
            right: LayoutConstants.largePadding,
            bottom: LayoutConstants.largePadding,
          ),
          child: LayoutBuilder(
            builder: (context, constraints) => HtmlWidget(
              html,
              factoryBuilder: () => PaginatedEpubWidgetFactory(
                viewport: Size(constraints.maxWidth, maxHeight),
                removeParagraphIndent: settings.removeParagraphIndent,
                onAnchorTap: onAnchorTap,
              ),
              customStylesBuilder: (element) =>
                  cssEngine.stylesFor(element: element),
              textStyle: textStyle,
              rebuildTriggers: [cssEngine.stylesRevision],
            ),
          ),
        ),
      ),
    );
  }
}
