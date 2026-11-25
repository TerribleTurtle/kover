import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/node_indexing_operation.dart';
import 'package:kover/utils/constants/html_constants.dart';
import 'package:kover/utils/extensions/document_fragment.dart';

final _inlineDisplayNoneRegExp = RegExp(
  r'display\s*:\s*none\s*;?',
  caseSensitive: false,
);
final _whitespaceRegExp = RegExp(r'\s+');

const _inlineTags = {'a', 'span', 'sup', 'sub'};
const _tightBlockTags = {'p', 'li', 'dd', 'dt', 'tr', 'blockquote'};

/// Extracts and sanitizes a single footnote subtree from preprocessed EPUB HTML.
sealed class EpubFootnoteExtractor {
  /// Returns sanitized HTML for the footnote identified by [rawRef] inside
  /// [root], or null if the target cannot be resolved or has no visible content.
  static String? extractFromRoot(
    dom.DocumentFragment root,
    String rawRef, {
    CssEngine? cssEngine,
  }) {
    final trimmed = rawRef.trim();
    final id = trimmed.startsWith('#') ? trimmed.substring(1) : trimmed;
    if (id.isEmpty) return null;

    final targetElement = root.findByAttribute('id', id);
    if (targetElement == null) return null;

    final footnoteElement = _resolveFootnoteElement(targetElement);
    if (footnoteElement.classes.contains(HtmlConstants.kavitaWrapperClass) ||
        footnoteElement.classes.contains(HtmlConstants.koverWrapperClass)) {
      return null;
    }

    final cloned = footnoteElement.clone(true);
    _cleanSubtree(cloned, cssEngine: cssEngine);
    if (!cloned.hasVisibleNodes) return null;

    _markTrimEdge(cloned, isStart: true);
    _markTrimEdge(cloned, isStart: false);

    return cloned.outerHtml;
  }

  /// Preprocesses [remoteHtml] and extracts the footnote referenced by [rawRef]
  /// along with a [CssEngine] built from [remoteHtml]'s stylesheets.
  static ({String html, CssEngine cssEngine})? extractRemote(
    dom.DocumentFragment remoteHtml,
    String rawRef, {
    Map<String, Map<String, String>> additionalStyles = const {},
  }) {
    final root = EpubPagePreprocessor(
      html: remoteHtml,
      operations: [NodeIndexingOperation()],
    ).process();

    final remoteCssEngine = CssEngine(
      root: root,
      additionalStyles: additionalStyles,
    );
    final footnoteHtml = extractFromRoot(
      root,
      rawRef,
      cssEngine: remoteCssEngine,
    );
    if (footnoteHtml == null) return null;

    return (html: footnoteHtml, cssEngine: remoteCssEngine);
  }

  static dom.Element _resolveFootnoteElement(dom.Element targetElement) {
    final targetTag = targetElement.localName;
    if (targetTag == null || !_inlineTags.contains(targetTag)) {
      return _promoteTightBlock(targetElement);
    }

    for (
      dom.Element? ancestor = targetElement.parent;
      ancestor != null;
      ancestor = ancestor.parent
    ) {
      if (ancestor.classes.contains(HtmlConstants.kavitaWrapperClass) ||
          ancestor.classes.contains(HtmlConstants.koverWrapperClass)) {
        break;
      }

      final ancestorTag = ancestor.localName;
      if (_tightBlockTags.contains(ancestorTag)) {
        return _promoteTightBlock(ancestor);
      }

      if (_isContainerTag(ancestorTag)) {
        if (_hasSiblingAnchor(ancestor, targetElement)) break;
        return ancestor;
      }
    }

    if (!targetElement.hasText && targetElement.nextElementSibling != null) {
      return targetElement.nextElementSibling!;
    }
    return targetElement;
  }

  static dom.Element _promoteTightBlock(dom.Element ancestor) {
    final parent = ancestor.parent;
    if (ancestor.localName != 'p' || parent == null) return ancestor;
    if (!_isContainerTag(parent.localName)) return ancestor;

    final isAside = parent.localName == 'aside';
    if (!isAside && !_hasNoteMarker(parent)) return ancestor;

    return _hasSiblingAnchor(parent, ancestor) ? ancestor : parent;
  }

  static bool _hasNoteMarker(dom.Element element) {
    final raw =
        '${element.attributes['class'] ?? ''} '
        '${element.attributes[HtmlConstants.epubTypeAttribute] ?? ''}';
    for (final token in raw.toLowerCase().split(_whitespaceRegExp)) {
      if (token.endsWith('note') || token.endsWith('notes')) return true;
    }
    return false;
  }

  static bool _isContainerTag(String? tag) {
    return tag == 'div' ||
        tag == 'article' ||
        tag == 'section' ||
        tag == 'aside';
  }

  static bool _hasSiblingAnchor(dom.Element container, dom.Element child) {
    for (final sibling in container.children) {
      if (identical(sibling, child)) continue;
      if (sibling.id.isNotEmpty) return true;
      if (sibling.querySelector('[id]') != null) return true;
    }

    return false;
  }

  static void _markTrimEdge(dom.Element rootEdge, {required bool isStart}) {
    final attribute = isStart
        ? HtmlConstants.trimStartAttribute
        : HtmlConstants.trimEndAttribute;
    for (
      dom.Element? edge = rootEdge;
      edge != null &&
          (_tightBlockTags.contains(edge.localName) ||
              _isContainerTag(edge.localName));
    ) {
      edge.attributes[attribute] = '';
      final children = isStart ? edge.children : edge.children.reversed;
      dom.Element? nextEdge;
      for (final child in children) {
        if (!_inlineTags.contains(child.localName)) {
          nextEdge = child;
          break;
        }
      }
      edge = nextEdge;
    }
  }

  static void _cleanSubtree(
    dom.Element rootElement, {
    CssEngine? cssEngine,
  }) {
    for (final element in [
      rootElement,
      ...rootElement.querySelectorAll('*'),
    ]) {
      final attributes = element.attributes;
      attributes.remove('id');

      final rawStyle = attributes['style'] ?? '';
      final hadInlineDisplayNone = _inlineDisplayNoneRegExp.hasMatch(rawStyle);
      final computedStyles = cssEngine?.stylesFor(element: element);
      final isDisplayNone =
          hadInlineDisplayNone ||
          computedStyles?['display']?.trim().toLowerCase() == 'none';
      if (!isDisplayNone) continue;

      attributes.remove(HtmlConstants.nodeIndexAttribute);
      if (!hadInlineDisplayNone) continue;

      final cleanedStyle = rawStyle
          .replaceAll(_inlineDisplayNoneRegExp, '')
          .trim();
      if (cleanedStyle.isEmpty) {
        attributes.remove('style');
      } else {
        attributes['style'] = cleanedStyle;
      }
    }
  }
}
