import 'package:html/dom.dart';
import 'package:kover/utils/extensions/document_fragment.dart';
import 'package:kover/utils/html_constants.dart';

abstract class ReflowEngine {
  /// The current buffer element that is being built.
  Element get buffer;

  /// Adds the next node from the source tree to the buffer.
  /// Returns true when a node was added, false if there are no more nodes to add.
  bool addNext();

  /// Marks the current buffer as overflowing.
  bool overflow();

  /// Commits the current buffer and returns a new buffer for further additions.
  Element commitSplit();
}

/// Exponential + binary search based reflow engine. Each tree level probes
/// exponential prefixes (1, 2, 4, ...) until the content overflows, then binary
/// searches between the last known fit and that overflow. When the boundary
/// unit is found, the engine descends one level and repeats, until the unit is
/// unsplittable (same end condition as the previous linear cursor).
class ExponentialBinaryReflowEngine implements ReflowEngine {
  static const _leafTags = {'img', 'svg', 'ruby', 'sup', 'sub'};
  static const _cjk =
      r'\u3007\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff\uac00-\ud7af';
  static const _cjkOpen = r'‘“〈《「『【〔〖〘〚〝﹙﹛﹝（［｛｟｢\([\{';
  static const _closePunct =
      r'·‐–-―’”‥…‰′″‼⁇-⁉、。々〉》」』】〕〗〙〛〜〞〟〰-〵〻〼ぁぃぅぇぉっゃゅょゎゕ-ゞ'
      r'゠ァィゥェォッャュョヮヵヶ・-ヾㇰ-ㇿ﹐-﹗﹚﹜﹞！％），．：；？］｝～｠｡｣-ｰﾞﾟ.,;:!?\x27"\)\]\}>';
  static final _wordsReg = RegExp(
    '(?<!\\s)(?=\\s)|(?<![\\s$_cjkOpen])(?:(?![$_closePunct])(?=[$_cjk])|(?=[$_cjkOpen]+[$_cjk]))|(?<=[$_cjk][$_closePunct]*)(?=[^\\s$_closePunct])',
  );
  static final _closingPunctOnlyReg = RegExp('^[$_closePunct]+\$');

  final Element _root;
  final Element _buffer;
  final List<_Frame> _frames = [];

  ExponentialBinaryReflowEngine({required Element root})
    : _root = root.clone(true),
      _buffer = root.clone(false) {
    _frames.add(_Frame(target: _buffer, pending: List.of(_root.nodes)));
  }

  @override
  Element get buffer => _buffer;

  @override
  bool addNext() {
    if (_frames.isEmpty) {
      for (final p in _buffer.querySelectorAll('p')) {
        if (!p.hasVisibleNodes) p.remove();
      }
      return false;
    }

    final frame = _frames.last;

    // Level exhausted: pop and continue the parent level.
    if (frame.pending.isEmpty) {
      _frames.removeLast();
      return addNext();
    }

    // The current probe fits.
    frame.lo = frame.p;

    if (frame.p == frame.pending.length) {
      // The whole level fits: pop. The parent resumes past the straddler
      // slot, which permanently shows the child shell from now on.
      _frames.removeLast();
      if (_frames.isEmpty) return addNext();

      final parent = _frames.last;
      final slot = parent.splitAt!;
      parent.pending[slot] = frame.target;
      parent.splitAt = null;
      parent.lo = slot + 1;
      if (parent.hi <= parent.lo) {
        parent.exponential = true;
      }
      _advance(parent);
      return true;
    }

    _advance(frame);
    return true;
  }

  /// Mirrors the next probe of [frame]: exponential while no
  /// overflow bound is known, otherwise binary searching the bounded range.
  void _advance(_Frame frame) {
    if (frame.exponential) {
      final grown = frame.lo < 1 ? 1 : frame.lo * 2;
      frame.p = grown < frame.pending.length ? grown : frame.pending.length;
    } else {
      // The range is bounded by a probe that overflowed: binary-search it.
      // When the range collapsed (hi == lo + 1) this re-appends the known
      // overflower so the driver reports overflow and the boundary handling
      // kicks in.
      frame.p = frame.lo + ((frame.hi - frame.lo + 1) >> 1);
    }
    _rebuild(frame);
  }

  @override
  bool overflow() {
    if (_frames.isEmpty) return false;

    final frame = _frames.last;
    if (frame.p == 0) return false;

    frame.hi = frame.p;
    // Once a probe overflows, stop exponential probing and binary-search the range.
    frame.exponential = false;

    // Range not collapsed: shrink the probe to the midpoint.
    if (frame.hi - frame.lo > 1) {
      frame.p = (frame.lo + frame.hi) >> 1;
      _rebuild(frame);
      return true;
    }

    // Boundary found: pending[lo] is the overflower. Descend.
    final unit = frame.pending[frame.lo];

    if (unit is Text) {
      final segments = _textSegments(unit.text);
      if (segments == null) {
        return _resolveUnsplittable(frame, unit);
      }

      frame.pending
        ..removeAt(frame.lo)
        ..insertAll(frame.lo, segments.map(Text.new));
      frame.hi = frame.lo + segments.length;
      frame.p = frame.lo;
      _rebuild(frame);
      return true;
    }

    if (unit is! Element ||
        _leafTags.contains(unit.localName) ||
        _isStickyMarker(unit) ||
        unit.nodes.isEmpty ||
        unit.isIndentSpan) {
      return _resolveUnsplittable(frame, unit);
    }

    // Descend one level: swap the tree node for an empty shell clone. The
    // unit itself stays untouched in pending until the child level pops.
    final shell = unit.clone(false);
    frame.target.nodes.last.replaceWith(shell);
    frame.splitAt = frame.lo;
    _frames.add(_Frame(target: shell, pending: List.of(unit.nodes)));

    return true;
  }

  @override
  Element commitSplit() {
    var frame = _frames.last;

    // Backtrack the overflower so it resumes on the next page. An accepted
    // unsplittable overflower (p == lo) stays on the committed page.
    if (frame.p > frame.lo && frame.target.nodes.isNotEmpty) {
      _rebuild(frame..p = frame.lo);
    }
    if (frame.lo > 0 && !frame.target.hasVisibleNodes) {
      _rebuild(frame..p = frame.lo = 0);
    }
    while (_frames.length > 1 && !frame.target.hasVisibleNodes) {
      final child = _frames.removeLast().pending;
      ((frame = _frames.last).pending[frame.splitAt!] as Element).nodes
        ..clear()
        ..addAll(child);
      if (!frame.target.hasVisibleNodes) frame.lo = 0;
      _rebuild(frame..p = (frame..splitAt = null).lo);
    }

    frame.pending.removeRange(0, frame.lo);
    while (_frames.length > 1 && !frame.pending.any((n) => n.hasVisibleNodes)) {
      _frames.removeLast();
      (frame = _frames.last)
        ..pending.removeRange(0, frame.splitAt! + 1)
        ..splitAt = null;
    }

    // Drop whitespace at the start of the next page.
    if (frame.pending.isNotEmpty && frame.pending.first is Text) {
      final first = frame.pending.first as Text;
      first.data = first.data.trimLeft();
    }

    // Ancestors committed everything before the straddler unit. The unit
    // itself stays (hollow) so the child shell swap keeps its slot.
    for (final f in _frames.take(_frames.length - 1)) {
      f.pending.removeRange(0, f.splitAt!);
      f.splitAt = 0;
    }

    final result = _buffer.clone(true);

    // Remove empty paragraph shells.
    result
        .querySelectorAll('p')
        .where((p) => !p.hasVisibleNodes)
        .forEach((p) => p.remove());

    // Mark a trailing split paragraph so the renderer can omit its bottom
    // margin: the split halves should read as one paragraph.
    final hasSplitParagraph = _frames.any(
      (f) => f.target.localName == 'p' && f.target.hasVisibleNodes,
    );
    if (hasSplitParagraph) {
      final trailing = result.localName == 'p'
          ? result
          : result.querySelectorAll('p').lastOrNull;
      trailing?.attributes[HtmlConstants.splitParagraphAttribute] = '';
    }

    // Reconstruct a clear tree up to the deepest target.
    Element? parent;
    for (final f in _frames) {
      f.target.nodes.clear();
      if (parent != null) parent.append(f.target);
      parent = f.target;
    }

    // The fresh page re-measures everything: reset the bounds.
    for (final f in _frames) {
      f.p = 0;
      f.lo = 0;
      f.hi = f.pending.length;
      f.exponential = true;
    }

    return result;
  }

  /// Rewinds sticky trailing nodes or accepts an unsplittable overflower.
  bool _resolveUnsplittable(_Frame frame, Node unit) {
    if (_isStickyTrailing(unit) && frame.lo > 0) {
      var i = frame.lo - 1;
      while (i > 0 &&
          _isStickyTrailing(frame.pending[i]) &&
          !_endsWithSpace(frame.pending[i - 1])) {
        i--;
      }
      final prev = frame.pending[i];
      if (!_endsWithSpace(prev)) {
        var e = prev;
        while (e is Element && e.nodes.length == 1 && e.children.isNotEmpty) {
          e = e.children.first;
        }
        final canSplit =
            e is Text ||
            (e is Element &&
                !_leafTags.contains(e.localName) &&
                e.nodes.every((n) => n is Text));
        final words = canSplit ? _textSegments(e.text!) : null;
        if (words != null) {
          e.text = words.take(words.length - 1).join();
          frame.pending.replaceRange(i, i + 1, [prev.clone(true), prev]);
          e.text = words.last.trimLeft();
          frame.hi++;
          _rebuild(frame..lo = frame.p = i + 1);
          return false;
        }
        if (_hasVisibleBefore(frame, i)) frame.lo = i;
      }
    }
    if (!_hasVisibleBefore(frame, frame.lo)) frame.lo = frame.p;
    return false;
  }

  bool _endsWithSpace(Node n) => (n.text ?? '').trimRight() != (n.text ?? '');

  bool _isStickyMarker(Element el) =>
      el.attributes['epub:type'] == 'noteref' ||
      el.attributes['role'] == 'doc-noteref' ||
      switch (el.localName) {
        'sup' || 'sub' => true,
        'a' => el.hasText && _textSegments(el.text) == null,
        'span' => el.nodes.length == 1 && _isStickyTrailing(el.nodes.first),
        _ => false,
      };

  bool _isStickyTrailing(Node n) => switch (n) {
    Text(:final text) => _closingPunctOnlyReg.hasMatch(text.trim()),
    Element() => (!n.hasVisibleNodes && !n.isIndentSpan) || _isStickyMarker(n),
    _ => false,
  };

  bool _hasVisibleBefore(_Frame frame, int index) =>
      frame.pending.take(index).any((n) => n.hasVisibleNodes) ||
      _frames.any(
        (f) => f.pending.take(f.splitAt ?? 0).any((n) => n.hasVisibleNodes),
      );

  /// Splits [text] into words and CJK units. Returns null for a single unit.
  List<String>? _textSegments(String text) {
    final words = text
        .split(_wordsReg)
        .where((word) => word.isNotEmpty)
        .toList();

    return words.length > 1 ? words : null;
  }

  /// Mirrors the first [_Frame.p] units of [frame] into its target.
  void _rebuild(_Frame frame) {
    frame.target.nodes
      ..clear()
      ..addAll(frame.pending.take(frame.p));
  }
}

/// One binary search level: the units of a single target element.
class _Frame {
  _Frame({required this.target, required this.pending}) : hi = pending.length;

  /// The element in the buffer tree units are mirrored into.
  final Element target;

  /// The units of this level; the first [p] are mirrored into [target].
  final List<Node> pending;

  /// Binary search pivot point. Matches units currently mirrored into [target].
  int p = 0;

  /// Binary search lower bound. Matches units known to fit into [target].
  int lo = 0;

  /// Binary search upper bound. Matches units known to overflow [target].
  int hi;

  /// Whether the search is still in the exponential probing phase
  /// or has an overflow bound and can halve the range.
  bool exponential = true;

  /// Index of the straddler unit a child frame descended into, if any.
  int? splitAt;
}
