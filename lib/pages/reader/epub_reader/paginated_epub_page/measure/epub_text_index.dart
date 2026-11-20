import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/utils/constants/html_constants.dart';

/// Resolved inline widget metadata recorded for an element during layout.
typedef EpubInlineMeta = ({bool hidden, bool solo, int pre, int post});

/// A position inside the DOM that corresponds to a character of the flattened
/// inline text.
class const EpubTextPosition({
  required final dom.Node node,
  final int offset = 0,
  final bool afterNode = false,
});

/// Thrown when the flattened text of a block cannot be mapped back to its DOM
/// nodes.
class EpubTextIndexMismatch implements Exception {
  const EpubTextIndexMismatch(this.reason);

  final String reason;

  @override
  String toString() => 'EpubTextIndexMismatch: $reason';
}

class const EpubTextIndex._(final List<EpubTextPosition> _positions) {
  /// Returns the DOM position of the visible character at [offset].
  EpubTextPosition? positionAt(int offset) {
    if (offset < 0 || offset >= _positions.length) return null;
    return _positions[offset];
  }

  /// Aligns the flattened inline text of [block] with its DOM nodes, so line
  /// start offsets can be turned  back into DOM break points.
  ///
  /// The alignment is greedy: whitespace runs in the DOM may collapse or vanish,
  /// so a normalized space consumes a raw whitespace run and a non-space
  /// character skips collapsed whitespace before matching. Inline widgets
  /// injected by fwfh (indent spans, anchors, inline-block elements, sup/sub,
  /// horizontal margins/padding) are represented by `U+FFFC` in the flattened
  /// text and are consumed as single tokens. Anything that does not line up
  /// throws [EpubTextIndexMismatch].
  factory build({
    required dom.Element block,
    Map<dom.Element, EpubInlineMeta> inlineMeta = const {},
    required CssWhitespace whitespace,
    required String plainText,
  }) {
    final tokens = <_Token>[];

    _collect(
      block: block,
      node: block,
      inlineMeta: inlineMeta,
      whitespace: whitespace,
      tokens: tokens,
    );

    final positions = <EpubTextPosition>[];
    var index = 0;

    for (var i = 0; i < plainText.length; i++) {
      final char = plainText[i];
      final isNewline = char == '\n';
      final isPlaceholder = char == '\uFFFC';
      final isSpace = char == ' ' || char == '\u00A0';

      if (isPlaceholder) {
        // The widget factory prepends a synthetic inline widget for a positive
        // CSS text-indent. It has no DOM node of its own, so the leading
        // placeholder maps to the block start. Handle it before looking at the
        // DOM tokens: the paragraph may start with an inline widget (for
        // example an anchor), which must not be mistaken for the indent.
        if (i == 0 &&
            block.attributes.containsKey(
              HtmlConstants.textIndentAttribute,
            )) {
          positions.add(EpubTextPosition(node: block, offset: 0));
          continue;
        }

        while (_peek(tokens, index) is _WhitespaceToken) {
          index++;
        }
        final token = _peek(tokens, index);
        if (token is! _InlineToken) {
          throw EpubTextIndexMismatch('expected inline widget at $i');
        }
        positions.add(token.position);
        index++;
        continue;
      }

      if (isNewline) {
        while (_peek(tokens, index) is _WhitespaceToken) {
          index++;
        }
        final token = _peek(tokens, index);
        if (token is _BreakToken) {
          positions.add(
            EpubTextPosition(
              node: token.element,
              offset: 0,
              afterNode: true,
            ),
          );
          index++;
          continue;
        }
        if (whitespace != .pre) {
          throw EpubTextIndexMismatch('expected <br> at $i');
        }
      }

      if (whitespace == .pre) {
        final token = _peek(tokens, index);
        if (token is! _CharToken || token.char != char) {
          throw EpubTextIndexMismatch('pre text mismatch at $i');
        }
        positions.add(EpubTextPosition(node: token.node, offset: token.offset));
        index++;
        continue;
      }

      if (isSpace) {
        final token = _peek(tokens, index);
        if (token is _WhitespaceToken) {
          positions.add(
            EpubTextPosition(node: token.node, offset: token.offset),
          );
          index++;
          continue;
        }
        if (token is _CharToken &&
            (token.char == ' ' || token.char == '\u00A0')) {
          positions.add(
            EpubTextPosition(node: token.node, offset: token.offset),
          );
          index++;
          continue;
        }
        throw EpubTextIndexMismatch('expected whitespace at $i');
      }

      while (_peek(tokens, index) is _WhitespaceToken) {
        index++;
      }

      final token = _peek(tokens, index);
      if (token is! _CharToken || token.char != char) {
        throw EpubTextIndexMismatch('expected "$char" at $i');
      }
      positions.add(EpubTextPosition(node: token.node, offset: token.offset));
      index++;
    }

    for (var i = index; i < tokens.length; i++) {
      final token = tokens[i];
      if (token is _WhitespaceToken ||
          token is _BreakToken ||
          token is _InlineToken) {
        continue;
      }
      throw const EpubTextIndexMismatch('trailing content after text');
    }

    return ._(positions);
  }
}

_Token? _peek(List<_Token> tokens, int index) => tokens.elementAtOrNull(index);

void _collect({
  required dom.Element block,
  required dom.Node node,
  required Map<dom.Element, EpubInlineMeta> inlineMeta,
  required CssWhitespace whitespace,
  required List<_Token> tokens,
}) {
  if (node is dom.Text) {
    final data = node.data;
    if (whitespace == .pre) {
      tokens.addAll([
        for (var i = 0; i < data.length; i++)
          _CharToken(node: node, offset: i, char: data[i]),
      ]);
      return;
    }

    var i = 0;
    while (i < data.length) {
      final char = data[i];
      if (_isWhitespace(char)) {
        final start = i;
        while (i < data.length && _isWhitespace(data[i])) {
          i++;
        }
        tokens.add(_WhitespaceToken(node: node, offset: start));
        continue;
      }

      tokens.add(_CharToken(node: node, offset: i, char: char));
      i++;
    }
    return;
  }

  if (node is! dom.Element) return;

  final localName = node.localName;
  final isChild = !identical(node, block);
  final meta = isChild ? inlineMeta[node] : null;
  if (meta?.hidden == true) return;
  final before = _InlineToken(EpubTextPosition(node: node));
  if (meta?.solo == true) {
    tokens.add(before);
    return;
  }
  if (isChild && localName == 'ruby') {
    tokens.addAll(_rubyTokens(node, inlineMeta, whitespace));
    return;
  }
  tokens.addAll(List.filled(meta?.pre ?? 0, before));
  if (isChild && localName == 'br') {
    tokens.add(_BreakToken(node));
  }
  for (final child in node.nodes) {
    _collect(
      block: block,
      node: child,
      inlineMeta: inlineMeta,
      whitespace: whitespace,
      tokens: tokens,
    );
  }
  final after = _InlineToken(EpubTextPosition(node: node, afterNode: true));
  tokens.addAll(List.filled(meta?.post ?? 0, after));
}

List<_Token> _rubyTokens(
  dom.Element ruby,
  Map<dom.Element, EpubInlineMeta> inlineMeta,
  CssWhitespace space,
) {
  final out = <_Token>[];
  final base = <_Token>[];
  _InlineToken? pairStart = _InlineToken(EpubTextPosition(node: ruby));
  for (final child in ruby.nodes) {
    final part = <_Token>[];
    _collect(
      block: ruby,
      node: child,
      inlineMeta: inlineMeta,
      whitespace: space,
      tokens: part,
    );
    final isRt = child is dom.Element && child.localName == 'rt';
    if (base.isNotEmpty && isRt && part.isNotEmpty) {
      out.add(pairStart!);
      base.clear();
      pairStart = null;
      continue;
    }
    for (final token in part) {
      if (base.isEmpty && token is _WhitespaceToken) {
        out.add(token);
        continue;
      }
      final pos = child is dom.Text && token is _CharToken ? token.offset : 0;
      pairStart ??= _InlineToken(EpubTextPosition(node: child, offset: pos));
      base.add(token);
    }
  }
  return out..addAll(base);
}

bool _isWhitespace(String char) =>
    char == ' ' || char == '\t' || char == '\n' || char == '\r' || char == '\f';

sealed class _Token {
  const _Token();
}

final class _CharToken extends _Token {
  const _CharToken({
    required this.node,
    required this.offset,
    required this.char,
  });

  final dom.Text node;
  final int offset;
  final String char;
}

final class _WhitespaceToken extends _Token {
  const _WhitespaceToken({required this.node, required this.offset});

  final dom.Text node;
  final int offset;
}

final class _BreakToken extends _Token {
  const _BreakToken(this.element);

  final dom.Element element;
}

final class const _InlineToken(final EpubTextPosition position) extends _Token;
