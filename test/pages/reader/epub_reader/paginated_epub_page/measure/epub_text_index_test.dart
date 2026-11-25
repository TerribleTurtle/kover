import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_text_index.dart';
import 'package:kover/utils/constants/html_constants.dart';

void main() {
  group('EpubTextIndex', () {
    group('plain text', () {
      test('maps a character to its DOM position', () {
        final block = _block('<p>Alpha</p>');
        final index = _build(block, 'Alpha');

        expect(_at(index, 4), (block.firstChild, 4, false));
      });

      test('returns null outside the text', () {
        final block = _block('<p>Alpha</p>');
        final index = _build(block, 'Alpha');

        expect(
          [index.positionAt(-1), index.positionAt(5)],
          everyElement(isNull),
        );
      });

      test('throws when the text does not match the block', () {
        final block = _block('<p>Alpha</p>');

        expect(
          () => _build(block, 'Bravo'),
          throwsA(isA<EpubTextIndexMismatch>()),
        );
      });
    });

    group('whitespace', () {
      test('maps a collapsed whitespace run to the start of the run', () {
        final block = _block('<p>a   b</p>');
        final index = _build(block, 'a b');

        expect(_at(index, 1), (block.firstChild, 1, false));
      });

      test('maps characters after a whitespace run to their raw offset', () {
        final block = _block('<p>a   b</p>');
        final index = _build(block, 'a b');

        expect(_at(index, 2), (block.firstChild, 4, false));
      });

      test('preserves newlines in pre mode', () {
        final block = _block('<p>a\nb</p>');
        final index = _build(block, 'a\nb', whitespace: .pre);

        expect(_at(index, 1), (block.firstChild, 1, false));
      });
    });

    group('inline widgets', () {
      test('maps a placeholder to its element', () {
        final block = _block('<p><a id="morson">Morson</a></p>');
        final anchor = block.querySelector('a')!;
        final index = _build(
          block,
          '\uFFFCMorson',
          inlineMeta: {anchor: _meta(pre: 1)},
        );

        expect(_at(index, 0), (anchor, 0, false));
      });

      test("maps text after a placeholder to that element's text", () {
        final block = _block('<p><a id="morson">Morson</a></p>');
        final anchor = block.querySelector('a')!;
        final index = _build(
          block,
          '\uFFFCMorson',
          inlineMeta: {anchor: _meta(pre: 1)},
        );

        expect(_at(index, 1), (anchor.firstChild, 0, false));
      });

      test('maps an indent placeholder to the block start', () {
        final block = _block(
          '<p ${HtmlConstants.textIndentAttribute}>Alpha</p>',
        );
        final index = _build(block, '\uFFFCAlpha');

        expect(_at(index, 0), (block, 0, false));
      });

      test('maps text after an indent placeholder to the block text', () {
        final block = _block(
          '<p ${HtmlConstants.textIndentAttribute}>Alpha</p>',
        );
        final index = _build(block, '\uFFFCAlpha');

        expect(_at(index, 1), (block.firstChild, 0, false));
      });

      test('maps solo inline widgets and skips hidden subtrees', () {
        final block = _block('<p><sub>2</sub><span class="h">b</span>x</p>');
        final sub = block.querySelector('sub')!;
        final hidden = block.querySelector('span')!;
        final index = _build(
          block,
          '\uFFFCx',
          inlineMeta: {
            sub: _meta(solo: true),
            hidden: _meta(hidden: true),
          },
        );

        expect(_at(index, 0), (sub, 0, false));
        expect(_at(index, 1), (block.nodes.last, 0, false));
      });

      test('maps pre and post inline spacing placeholders', () {
        final block = _block('<p><span>A</span><span>B</span></p>');
        final spans = block.querySelectorAll('span');
        final index = _build(
          block,
          'A\uFFFCB\uFFFC',
          inlineMeta: {spans[1]: _meta(pre: 1, post: 1)},
        );

        expect(_at(index, 0), (spans[0].firstChild!, 0, false));
        expect(_at(index, 1), (spans[1], 0, false));
        expect(_at(index, 2), (spans[1].firstChild!, 0, false));
        expect(_at(index, 3), (spans[1], 0, true));
      });

      test('maps multi-pair and solo ruby annotations', () {
        final block = _block('<p><ruby>漢<rt>か</rt>字<rt>じ</rt></ruby>x</p>');
        final ruby = block.querySelector('ruby')!;
        final multi = _build(block, '\uFFFC\uFFFCx');
        final solo = _build(
          block,
          '\uFFFCx',
          inlineMeta: {ruby: _meta(solo: true)},
        );

        expect(_at(multi, 0), (ruby, 0, false));
        expect(_at(multi, 1), (ruby.nodes[2], 0, false));
        expect(_at(multi, 2), (block.nodes.last, 0, false));
        expect(_at(solo, 0), (ruby, 0, false));
        expect(_at(solo, 1), (block.nodes.last, 0, false));
      });
    });

    group('line breaks', () {
      test('maps a newline after its br', () {
        final block = _block('<p>a<br>b</p>');
        final br = block.querySelector('br')!;
        final index = _build(block, 'a\nb');

        expect(_at(index, 1), (br, 0, true));
      });

      test('maps text after a br to the following text node', () {
        final block = _block('<p>a<br>b</p>');
        final index = _build(block, 'a\nb');

        expect(_at(index, 2), (block.nodes.last, 0, false));
      });
    });
  });
}

(Object, int, bool) _at(EpubTextIndex index, int offset) {
  final position = index.positionAt(offset)!;
  return (position.node, position.offset, position.afterNode);
}

EpubTextIndex _build(
  dom.Element block,
  String plainText, {
  Map<dom.Element, EpubInlineMeta> inlineMeta = const {},
  CssWhitespace whitespace = .normal,
}) {
  return EpubTextIndex.build(
    block: block,
    inlineMeta: inlineMeta,
    whitespace: whitespace,
    plainText: plainText,
  );
}

dom.Element _block(String html) {
  return dom.DocumentFragment.html(html).querySelector('p')!;
}

EpubInlineMeta _meta({
  bool hidden = false,
  bool solo = false,
  int pre = 0,
  int post = 0,
}) => (hidden: hidden, solo: solo, pre: pre, post: post);
