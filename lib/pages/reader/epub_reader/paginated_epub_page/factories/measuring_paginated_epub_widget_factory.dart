import 'package:flutter/widgets.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/factories/paginated_epub_widget_factory.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_probe.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_text_index.dart';
import 'package:kover/utils/constants/html_constants.dart';

/// A [WidgetFactory] used for measuring the epub content.
/// Wraps blocks, text and images in probes that report their size and position.
class MeasuringPaginatedEpubWidgetFactory({
  super.viewport,
  super.removeParagraphIndent,
  final void Function()? onChanged,
}) extends PaginatedEpubWidgetFactory {
  // Matches fwfh's internal Priority.max so _probeOp and _inlineOp run after
  // Late ops.
  static const _afterLateBuildOpPriority = 9007199254740991;

  final Map<dom.Element, EpubInlineMeta> _inlineMeta = {};
  var _isBuildComplete = false;
  int _pendingImages = 0;

  bool get isBuildComplete => _isBuildComplete;
  int get pendingImages => _pendingImages;

  final BuildOp epubBlockProbeOp = .v2(
    alwaysRenderBlock: false,
    debugLabel: 'epub-block-probe',
    priority: 9999,
    onRenderBlock: (tree, placeholder) {
      if (tree.isInline == true) return placeholder;

      final nodeIndex = _nodeIndex(tree.element);
      if (nodeIndex == null) return placeholder;

      return EpubBlockProbe(
        nodeIndex: nodeIndex,
        element: tree.element,
        child: placeholder,
      );
    },
  );

  @override
  void reset(State state) {
    super.reset(state);
    _inlineMeta.clear();
  }

  @override
  void parse(BuildTree meta) {
    meta.register(epubBlockProbeOp);
    meta.register(_probeOp(meta));
    meta.register(_inlineOp(meta));

    super.parse(meta);
  }

  BuildOp _probeOp(BuildTree meta) {
    final node = meta.element;
    final nodeIndex = _nodeIndex(node);
    return .v2(
      priority: _afterLateBuildOpPriority - 1,
      onParsed: (tree) {
        if (identical(tree, meta) || tree.isEmpty || nodeIndex == null) {
          return tree;
        }
        if (meta.isInline == false) {
          tree.register(epubBlockProbeOp);
          return tree;
        }
        if (tree.children.singleOrNull case final WidgetBit<Object?> bit) {
          bit.child.wrapWith(
            (_, child) => EpubLeafProbe(
              nodeIndex: nodeIndex,
              element: node,
              child: child,
            ),
          );
        }
        return tree;
      },
    );
  }

  BuildOp _inlineOp(BuildTree meta) {
    final node = meta.element;
    return .v2(
      priority: _afterLateBuildOpPriority,
      onParsed: (tree) {
        final replaced = !identical(tree, meta);
        final hidden = meta.isInline != true || (replaced && tree.isEmpty);
        final solo =
            !hidden && replaced && tree.children.singleOrNull is WidgetBit;
        _inlineMeta[node] = (hidden: hidden, solo: solo, pre: 0, post: 0);
        return tree;
      },
      onRenderInline: (tree) {
        final bits = tree.children.where((b) => b.isInline != false).toList();
        final pre = bits.takeWhile(_isWidgetBit).length;
        final post = bits.sublist(pre).reversed.takeWhile(_isWidgetBit).length;
        _inlineMeta[node] = (hidden: false, solo: false, pre: pre, post: post);
      },
    );
  }

  @override
  Widget buildBodyWidget(BuildContext context, Widget child) {
    final built = super.buildBodyWidget(context, child);
    _markBuildComplete();
    return built;
  }

  @override
  Widget? onErrorBuilder(
    BuildContext context,
    BuildTree tree, [
    dynamic error,
    dynamic data,
  ]) {
    final built = super.onErrorBuilder(context, tree, error, data);
    _markBuildComplete();
    return built;
  }

  void _markBuildComplete() {
    if (_isBuildComplete) return;
    _isBuildComplete = true;
    onChanged?.call();
  }

  @override
  Widget? buildPadding(
    BuildTree tree,
    Widget child,
    EdgeInsetsGeometry padding,
  ) {
    final built = super.buildPadding(tree, child, padding);
    if (built == null) return null;

    return EpubPaddingProbe(padding: padding, child: built);
  }

  @override
  Widget? buildText(
    BuildTree tree,
    InheritedProperties resolved,
    InlineSpan text,
  ) {
    final child = super.buildText(tree, resolved, text);
    if (tree.isInline != false) return child;

    final nodeIndex = _nodeIndex(tree.element);

    if (child == null || nodeIndex == null) return child;

    return EpubTextProbe(
      nodeIndex: nodeIndex,
      element: tree.element,
      whitespace: resolved.get<CssWhitespace>() ?? CssWhitespace.normal,
      inlineMeta: _inlineMeta,
      child: child,
    );
  }

  @override
  Widget? buildImageWidget(BuildTree meta, ImageSource src) {
    final child = super.buildImageWidget(meta, src);
    final nodeIndex = _nodeIndex(meta.element);
    if (nodeIndex == null) return child;

    var tracked = child ?? const SizedBox.shrink();
    if (child is Image) {
      tracked = _EpubImageLoadTracker(
        key: ValueKey(child.image),
        provider: child.image,
        onEnter: () => _pendingImages++,
        onExit: () {
          _pendingImages--;
          if (_pendingImages == 0) onChanged?.call();
        },
        child: child,
      );
    }

    return EpubLeafProbe(
      nodeIndex: nodeIndex,
      element: meta.element,
      child: tracked,
    );
  }

  static bool _isWidgetBit(BuildBit bit) => bit is WidgetBit;

  static int? _nodeIndex(dom.Element element) {
    final indexAttr =
        element.attributes[HtmlConstants.nodeIndexAttribute] ?? '';
    return int.tryParse(indexAttr);
  }
}

class _EpubImageLoadTracker extends StatefulWidget {
  final ImageProvider provider;
  final void Function() onEnter;
  final void Function() onExit;
  final Widget child;

  const _EpubImageLoadTracker({
    super.key,
    required this.provider,
    required this.onEnter,
    required this.onExit,
    required this.child,
  });

  @override
  State<_EpubImageLoadTracker> createState() => _EpubImageLoadTrackerState();
}

class _EpubImageLoadTrackerState extends State<_EpubImageLoadTracker> {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  var _settled = false;

  @override
  void initState() {
    super.initState();
    widget.onEnter();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_settled || _stream != null) return;

    final stream = widget.provider.resolve(
      createLocalImageConfiguration(context),
    );
    final listener = ImageStreamListener(
      (_, _) => _settle(),
      onError: (_, _) => _settle(),
    );

    _stream = stream;
    _listener = listener;
    stream.addListener(listener);
  }

  void _settle() {
    if (_settled) return;
    _settled = true;
    _removeListener();
    widget.onExit();
  }

  void _removeListener() {
    final stream = _stream;
    final listener = _listener;
    if (stream != null && listener != null) {
      stream.removeListener(listener);
    }
    _stream = null;
    _listener = null;
  }

  @override
  void dispose() {
    _removeListener();
    if (!_settled) {
      _settled = true;
      widget.onExit();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
