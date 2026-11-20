import 'package:html/dom.dart' as dom;
import 'package:kover/utils/constants/html_constants.dart';
import 'package:kover/utils/extensions/document_fragment.dart';

final _whitespaceRegExp = RegExp(r'\s+');

const _noterefTokens = {'noteref', 'doc-noteref'};
const _blockBoundaryTags = {
  'p',
  'div',
  'li',
  'blockquote',
  'td',
  'th',
  'dd',
  'dt',
};

/// A navigation target encoded on an EPUB anchor.
///
/// Kavita rewrites internal EPUB links before serving the page:
///
/// - cross-page links get `kavita-page` and optionally `kavita-part`
/// - footnote references get `kavita-note-ref`
/// - links that stay on the current page keep a `#fragment` href
/// - external links keep their original `http(s)` href
class const EpubAnchorTarget({
  /// Zero-based reading-order page within the current chapter.
  final int? page,

  /// Fragment id on [page].
  ///
  /// The backend also uses this attribute for the original file path when it
  /// could not resolve a page mapping. In that case no element will match and
  /// the reader lands at the start of [page].
  final String? part,

  /// External URL that should be opened outside the reader.
  final Uri? externalUri,

  /// Whether tapping this anchor should preview a footnote instead of jumping.
  final bool isFootnote = false,
}) {
  /// Builds a target from the attributes Kavita writes on an `<a>` element.
  static EpubAnchorTarget? fromElement(dom.Element element) {
    if (element.localName != 'a') return null;

    final attributes = element.attributes;
    final href = attributes['href'];
    final page = int.tryParse(
      attributes[HtmlConstants.kavitaPageAttribute] ?? '',
    );
    final noteRef = _normalizePart(
      attributes[HtmlConstants.kavitaNoteRefAttribute],
    );
    final part =
        noteRef ??
        _normalizePart(attributes[HtmlConstants.kavitaPartAttribute]) ??
        _normalizePart(href?.startsWith('#') == true ? href : null);

    if (part != null) {
      return EpubAnchorTarget(
        page: page,
        part: part,
        isFootnote: _isFootnote(element, hasNoteRef: noteRef != null),
      );
    }

    if (page != null) {
      return EpubAnchorTarget(page: page);
    }

    if (href == null) return null;

    final external = _externalUri(href);
    if (external != null) {
      return EpubAnchorTarget(externalUri: external);
    }

    return null;
  }

  static String? _normalizePart(String? value) {
    if (value == null) return null;

    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;

    final withoutHash = trimmed.startsWith('#')
        ? trimmed.substring(1)
        : trimmed;
    return withoutHash.isEmpty ? null : withoutHash;
  }

  static bool _isFootnote(dom.Element element, {required bool hasNoteRef}) {
    if (_isInsideHardExcluded(element)) return false;
    if (hasNoteRef || _hasNoterefOn(element)) return true;
    if (_isInsideNoteContainer(element)) return false;

    final hasSupWrapper =
        element.parent?.localName == 'sup' ||
        element.querySelector('sup') != null;
    return hasSupWrapper && _hasPrecedingText(element);
  }

  static bool _isInsideHardExcluded(dom.Element element) {
    for (
      dom.Element? current = element;
      current != null;
      current = current.parent
    ) {
      final tag = current.localName;
      if (tag == 'nav' || tag == 'aside') return true;
      if (_hasAnyToken(current, _isHardExcludedToken)) return true;
    }

    return false;
  }

  static bool _isInsideNoteContainer(dom.Element element) {
    final parent = element.parent;
    final start = parent?.localName == 'sup' ? parent!.parent : parent;
    for (
      dom.Element? current = start;
      current != null;
      current = current.parent
    ) {
      if (_hasAnyToken(current, _isNoteToken)) return true;
    }

    return false;
  }

  static bool _hasAnyToken(
    dom.Element element,
    bool Function(String token) predicate,
  ) {
    final attributes = element.attributes;
    return _matchesAnyToken(
          attributes[HtmlConstants.epubTypeAttribute],
          predicate,
        ) ||
        _matchesAnyToken(attributes['role'], predicate) ||
        _matchesAnyToken(attributes['class'], predicate);
  }

  static bool _hasNoterefOn(dom.Element element) {
    final attributes = element.attributes;
    return _matchesAnyToken(
          attributes[HtmlConstants.epubTypeAttribute],
          _noterefTokens.contains,
        ) ||
        _matchesAnyToken(attributes['role'], _noterefTokens.contains);
  }

  static bool _matchesAnyToken(
    String? raw,
    bool Function(String token) predicate,
  ) {
    if (raw == null || raw.isEmpty) return false;

    for (final token in raw.toLowerCase().split(_whitespaceRegExp)) {
      if (token.isNotEmpty && predicate(token)) return true;
    }

    return false;
  }

  static bool _isHardExcludedToken(String token) {
    return token.endsWith('backlink') || token == 'toc' || token == 'doc-toc';
  }

  static bool _isNoteToken(String token) {
    return token.endsWith('note') || token.endsWith('notes');
  }

  static bool _hasPrecedingText(dom.Element element) {
    dom.Node current = element;
    for (
      dom.Node? parent = current.parentNode;
      parent != null;
      parent = current.parentNode
    ) {
      for (final sibling in parent.nodes) {
        if (identical(sibling, current)) break;
        if (sibling.hasText) return true;
      }

      if (parent is! dom.Element ||
          _blockBoundaryTags.contains(parent.localName)) {
        break;
      }
      current = parent;
    }

    return false;
  }

  static Uri? _externalUri(String href) {
    final uri = Uri.tryParse(href);
    if (uri == null) return null;

    if (uri.hasScheme) {
      return switch (uri.scheme.toLowerCase()) {
        'http' || 'https' || 'mailto' || 'tel' => uri,
        _ => null,
      };
    }

    if (uri.hasAuthority) {
      return Uri(scheme: 'https').resolveUri(uri);
    }

    return null;
  }
}
