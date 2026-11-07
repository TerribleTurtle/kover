import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';

class RenderHtml extends StatelessWidget {
  final String html;
  final WidgetFactory Function() factoryBuilder;
  final CssEngine cssEngine;
  final TextStyle? textStyle;
  final FutureOr<bool> Function(String url)? onTapUrl;
  const new({
    super.key,
    required this.html,
    required this.factoryBuilder,
    required this.cssEngine,
    this.textStyle,
    this.onTapUrl,
  });

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      html,
      factoryBuilder: factoryBuilder,
      customStylesBuilder: (element) => cssEngine.stylesFor(element),
      textStyle: textStyle,
      onTapUrl: onTapUrl,
      rebuildTriggers: [cssEngine.stylesRevision],
    );
  }
}
