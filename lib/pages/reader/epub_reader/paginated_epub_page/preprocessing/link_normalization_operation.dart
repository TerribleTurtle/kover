import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor_operation.dart';
import 'package:kover/utils/html_constants.dart';

final _xpathIdRegExp = RegExp(r'''@id\s*=\s*['"]([^'"]+)['"]''');
final _whitespaceRegExp = RegExp(r'\s+');
final _pageAnchorRegExp = RegExp(r'^page[_-]?\d+$', caseSensitive: false);
final _inlineFootnoteMarkerRegExp = RegExp(
  r'^(\[\d+\]|\(\d+\)|\d{1,3}|[\u00B9\u00B2\u00B3\u2070-\u2079]+|[\u2460-\u249B\u2776-\u2793]|[*†‡§‖¶※]+\d*|\[[a-zA-Z]+\]|\([a-zA-Z]\)|[［（【〔][^］）】〕]{1,6}[］）】〕])$',
);
final _proseCharRegExp = RegExp(r'\p{L}', unicode: true);

const _noteRefTypes = {'noteref', 'annoref', 'biblioref'};
const _noteRefRoles = {'doc-noteref', 'doc-biblioref'};
const _noteRefTokens = {
  'noteref',
  'note-ref',
  'note_ref',
  'annoref',
  'biblioref',
  'fnref',
  'fn-ref',
  'fn_ref',
  'fnanchor',
  'fn-anchor',
  'footnoteref',
  'footnote-ref',
  'footnote_ref',
  'footnote-link',
  'footnote_link',
  '_idfootnotelink',
  'endnoteref',
  'endnote-ref',
  'endnote_ref',
  'endnote-link',
  'endnote_link',
  '_idendnotelink',
  'note-d',
  'duokan-footnote',
};
const _backlinkTypes = {'backlink'};
const _backlinkRoles = {'doc-backlink'};
const _backlinkTokens = {
  'backlink',
  'footnote-back',
  'footnote_back',
  '_idfootnoteanchor',
  '_idendnoteanchor',
};
const _footnoteTypes = {
  'footnote',
  'footnotes',
  'note',
  'notes',
  'endnote',
  'endnotes',
  'rearnote',
  'rearnotes',
  'annotation',
};
const _footnoteRoles = {
  'doc-footnote',
  'doc-endnote',
  'doc-footnotes',
  'note',
};
const _footnoteTokens = {
  'fn',
  'footnote',
  'footnotes',
  '_idfootnote',
  '_idfootnotes',
  'endnote',
  'endnotes',
  '_idendnote',
  '_idendnotes',
  'rearnote',
  'rearnotes',
  'note',
  'notes',
};
const _headingTags = {'h1', 'h2', 'h3', 'h4', 'h5', 'h6'};
const _blockBoundaryTags = {
  'p',
  'li',
  'dd',
  'dt',
  'blockquote',
  'div',
  'section',
  'article',
  'aside',
  'td',
  'th',
  'h1',
  'h2',
  'h3',
  'h4',
  'h5',
  'h6',
  'body',
};

sealed class EpubLinkTarget {
  const EpubLinkTarget();

  static EpubLinkTarget? parse(String rawUrl) {
    final trimmed = rawUrl.trim();
    if (trimmed.isEmpty || trimmed.toLowerCase().startsWith('javascript:')) {
      return null;
    }

    final uri = Uri.tryParse(trimmed);
    if (uri != null && uri.scheme == 'kover') {
      if (uri.host == 'note') {
        final ref = _cleanAnchorId(
          uri.queryParameters['ref'] ??
              (uri.fragment.isNotEmpty ? uri.fragment : ''),
        );
        if (ref.isEmpty) return null;
        final page = int.tryParse(uri.queryParameters['page'] ?? '');
        return EpubFootnoteLinkTarget(ref: ref, page: page);
      }
      if (uri.host == 'link') {
        final page = int.tryParse(uri.queryParameters['page'] ?? '');
        final rawAnchor =
            uri.queryParameters['part'] ??
            uri.queryParameters['anchor'] ??
            uri.queryParameters['anchorId'] ??
            (uri.fragment.isNotEmpty ? uri.fragment : null);
        final cleaned = rawAnchor != null ? _cleanAnchorId(rawAnchor) : '';
        final anchorId = cleaned.isNotEmpty ? cleaned : null;
        if (page == null && anchorId == null) return null;
        return EpubInternalLinkTarget(page: page, anchorId: anchorId);
      }
      return null;
    }

    if (trimmed.startsWith('#')) {
      final anchorId = _cleanAnchorId(trimmed);
      if (anchorId.isEmpty) return null;
      return EpubInternalLinkTarget(anchorId: anchorId);
    }

    if (uri != null && uri.hasScheme) {
      return EpubExternalLinkTarget(url: trimmed);
    }

    if (trimmed.contains('#')) {
      final anchorId = _cleanAnchorId(trimmed);
      if (anchorId.isNotEmpty) {
        return EpubInternalLinkTarget(anchorId: anchorId);
      }
    }

    return null;
  }
}

final class EpubFootnoteLinkTarget extends EpubLinkTarget {
  final String ref;
  final int? page;

  const new({
    required this.ref,
    this.page,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpubFootnoteLinkTarget &&
          runtimeType == other.runtimeType &&
          ref == other.ref &&
          page == other.page;

  @override
  int get hashCode => Object.hash(ref, page);

  @override
  String toString() => 'EpubFootnoteLinkTarget(ref: $ref, page: $page)';
}

final class EpubInternalLinkTarget extends EpubLinkTarget {
  final int? page;
  final String? anchorId;

  const new({
    this.page,
    this.anchorId,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpubInternalLinkTarget &&
          runtimeType == other.runtimeType &&
          page == other.page &&
          anchorId == other.anchorId;

  @override
  int get hashCode => Object.hash(page, anchorId);

  @override
  String toString() =>
      'EpubInternalLinkTarget(page: $page, anchorId: $anchorId)';
}

final class EpubExternalLinkTarget extends EpubLinkTarget {
  final String url;

  const new({
    required this.url,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EpubExternalLinkTarget &&
          runtimeType == other.runtimeType &&
          url == other.url;

  @override
  int get hashCode => url.hashCode;

  @override
  String toString() => 'EpubExternalLinkTarget(url: $url)';
}

/// Rewrites Kavita note references and internal anchor links into `kover://` URIs.
final class LinkNormalizationOperation extends EpubPagePreprocessorOperation {
  final Map<String, dom.Element> _elementsById = {};
  final Map<dom.Element, int> _elementOrder = {};
  final List<dom.Element> _links = [];
  int _nextOrder = 0;

  @override
  void start(dom.DocumentFragment root) {
    _elementsById.clear();
    _elementOrder.clear();
    _links.clear();
    _nextOrder = 0;
  }

  @override
  void enter(dom.Element element) {
    _elementOrder[element] = _nextOrder++;
    final id = element.id.isNotEmpty ? element.id : element.attributes['name'];
    if (id != null && id.isNotEmpty) {
      _elementsById.putIfAbsent(id, () => element);
    }
    if (element.localName == 'a') {
      _links.add(element);
    }
  }

  @override
  void finish(dom.DocumentFragment root) {
    for (final element in _links) {
      _normalizeLink(element);
    }
    _elementsById.clear();
    _elementOrder.clear();
    _links.clear();
    _nextOrder = 0;
  }

  void _normalizeLink(dom.Element element) {
    final rawNoteRef = element.attributes[HtmlConstants.kavitaNoteRefAttribute];
    final kavitaPage = element.attributes[HtmlConstants.kavitaPageAttribute];
    final kavitaPart = element.attributes[HtmlConstants.kavitaPartAttribute];
    final href = element.attributes['href'];
    final epubType = element.attributes[HtmlConstants.epubTypeAttribute];
    final role = element.attributes['role'];

    if (rawNoteRef != null && rawNoteRef.isNotEmpty) {
      final noteRef = _cleanAnchorId(rawNoteRef);
      if (noteRef.isNotEmpty) {
        final effectivePage = _resolvePage(kavitaPage, noteRef);
        final query = <String, String>{
          'ref': noteRef,
          'page': ?effectivePage,
        };
        element.attributes['href'] = Uri(
          scheme: 'kover',
          host: 'note',
          queryParameters: query,
        ).toString();
        return;
      }
    }

    final part = switch ((kavitaPart, href)) {
      (final kp?, _) when kp.isNotEmpty => _cleanAnchorId(kp),
      (_, final h?) when h.startsWith('#') && h.length > 1 => _cleanAnchorId(h),
      _ => '',
    };
    final effectivePage = _resolvePage(kavitaPage, part);

    if (part.isNotEmpty &&
        _isFootnoteLink(element, part, epubType: epubType, role: role)) {
      final query = <String, String>{
        'ref': part,
        'page': ?effectivePage,
      };
      element.attributes['href'] = Uri(
        scheme: 'kover',
        host: 'note',
        queryParameters: query,
      ).toString();
      return;
    }

    if (effectivePage != null || part.isNotEmpty) {
      final query = <String, String>{
        'page': ?effectivePage,
        if (part.isNotEmpty) 'part': part,
      };
      element.attributes['href'] = Uri(
        scheme: 'kover',
        host: 'link',
        queryParameters: query,
      ).toString();
    }
  }

  String? _resolvePage(String? kavitaPage, String part) {
    if (kavitaPage == null || kavitaPage.isEmpty) return null;
    if (kavitaPage == '0' &&
        part.isNotEmpty &&
        _elementsById.containsKey(part)) {
      return null;
    }
    return kavitaPage;
  }

  bool _isFootnoteLink(
    dom.Element element,
    String part, {
    String? epubType,
    String? role,
  }) {
    if (_isInsideNavigationOrFootnoteContainer(element)) return false;

    final target = _elementsById[part];
    if (target != null) {
      if (target == element || _isAncestor(target, element)) return false;
      final linkOrder = _elementOrder[element];
      final targetOrder = _elementOrder[target];
      if (linkOrder != null && targetOrder != null && targetOrder < linkOrder) {
        return false;
      }
    }

    if (_hasNoteRefSemantics(element, epubType: epubType, role: role)) {
      return true;
    }
    if (target != null && _isInsideFootnoteContainer(target)) return true;
    if (_hasSuperscriptMarker(element)) return true;

    return _isInlineFootnoteNumber(element, part, target);
  }
}

bool _isInsideNavigationOrFootnoteContainer(dom.Element element) {
  if (_hasToken(
        element.attributes[HtmlConstants.epubTypeAttribute],
        _backlinkTypes,
      ) ||
      _hasToken(element.attributes['role'], _backlinkRoles) ||
      element.classes.any(
        (cls) => _backlinkTokens.contains(cls.toLowerCase()),
      )) {
    return true;
  }
  dom.Element? current = element;
  while (current != null) {
    if (current.localName == 'nav') return true;
    final parent = current.parent;
    current = parent is dom.Element ? parent : null;
  }
  return _isInsideFootnoteContainer(element);
}

bool _hasNoteRefSemantics(
  dom.Element element, {
  String? epubType,
  String? role,
}) {
  if (_hasToken(epubType, _noteRefTypes) || _hasToken(role, _noteRefRoles)) {
    return true;
  }
  if (_hasNoteRefTokenOnElement(element)) return true;

  dom.Element? parent = element.parent is dom.Element
      ? element.parent as dom.Element
      : null;
  while (parent != null &&
      !_blockBoundaryTags.contains(parent.localName?.toLowerCase())) {
    if (_hasToken(
          parent.attributes[HtmlConstants.epubTypeAttribute],
          _noteRefTypes,
        ) ||
        _hasToken(parent.attributes['role'], _noteRefRoles) ||
        _hasNoteRefTokenOnElement(parent)) {
      return true;
    }
    parent = parent.parent is dom.Element ? parent.parent as dom.Element : null;
  }

  for (final child in element.querySelectorAll('*')) {
    if (_hasToken(
          child.attributes[HtmlConstants.epubTypeAttribute],
          _noteRefTypes,
        ) ||
        _hasToken(child.attributes['role'], _noteRefRoles) ||
        _hasNoteRefTokenOnElement(child)) {
      return true;
    }
  }
  return false;
}

bool _hasNoteRefTokenOnElement(dom.Element element) {
  if (element.classes.any(
    (cls) => _noteRefTokens.contains(cls.toLowerCase()),
  )) {
    return true;
  }
  return _noteRefTokens.contains(element.id.toLowerCase());
}

bool _isInsideFootnoteContainer(dom.Element element) {
  dom.Element? current = element;
  while (current != null) {
    if (current.localName == 'aside') return true;
    if (_hasToken(
          current.attributes[HtmlConstants.epubTypeAttribute],
          _footnoteTypes,
        ) ||
        _hasToken(current.attributes['role'], _footnoteRoles)) {
      return true;
    }
    if (current.classes.any(
          (cls) => _footnoteTokens.contains(cls.toLowerCase()),
        ) ||
        _footnoteTokens.contains(current.id.toLowerCase())) {
      return true;
    }
    final parent = current.parent;
    current = parent is dom.Element ? parent : null;
  }
  return false;
}

bool _hasSuperscriptMarker(dom.Element element) {
  dom.Element? current = element.parent is dom.Element
      ? element.parent as dom.Element
      : null;
  while (current != null &&
      !_blockBoundaryTags.contains(current.localName?.toLowerCase())) {
    if (current.localName == 'sup') return true;
    current = current.parent is dom.Element
        ? current.parent as dom.Element
        : null;
  }
  if (element.querySelector('sup') == null) return false;
  return element.text.trim().length <= 16;
}

bool _isInlineFootnoteNumber(
  dom.Element element,
  String part,
  dom.Element? target,
) {
  if (_pageAnchorRegExp.hasMatch(part)) return false;
  if (target != null &&
      _headingTags.contains(target.localName?.toLowerCase())) {
    return false;
  }

  final text = element.text.trim();
  if (!_inlineFootnoteMarkerRegExp.hasMatch(text)) return false;

  return _hasPrecedingInlineProse(element);
}

bool _hasPrecedingInlineProse(dom.Element element) {
  dom.Element? block = element.parent is dom.Element
      ? element.parent as dom.Element
      : null;
  while (block != null &&
      !_blockBoundaryTags.contains(block.localName?.toLowerCase())) {
    block = block.parent is dom.Element ? block.parent as dom.Element : null;
  }
  if (block == null) return false;
  if (_headingTags.contains(block.localName?.toLowerCase())) return false;

  final buffer = StringBuffer();
  _collectTextBefore(block, element, buffer);
  return _proseCharRegExp.hasMatch(buffer.toString());
}

bool _collectTextBefore(
  dom.Node node,
  dom.Element stopElement,
  StringBuffer buffer,
) {
  if (identical(node, stopElement)) return true;
  if (node is dom.Text) {
    buffer.write(node.text);
    return false;
  }
  for (final child in node.nodes) {
    if (_collectTextBefore(child, stopElement, buffer)) {
      return true;
    }
  }
  return false;
}

bool _isAncestor(dom.Element ancestor, dom.Element node) {
  dom.Node? current = node.parent;
  while (current != null) {
    if (current == ancestor) return true;
    current = current.parent;
  }
  return false;
}

bool _hasToken(String? value, Set<String> tokens) {
  if (value == null || value.isEmpty) return false;
  for (final token in value.toLowerCase().split(_whitespaceRegExp)) {
    if (tokens.contains(token)) return true;
  }
  return false;
}

String _cleanAnchorId(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '';

  final xpathMatch = _xpathIdRegExp.firstMatch(trimmed);
  if (xpathMatch != null) {
    return xpathMatch.group(1)!.trim();
  }

  if (trimmed.contains('#')) {
    return trimmed.split('#').last.trim();
  }

  if (trimmed.endsWith('.xhtml') ||
      trimmed.endsWith('.html') ||
      trimmed.endsWith('.htm')) {
    return '';
  }

  return trimmed;
}
