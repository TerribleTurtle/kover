import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_anchor_target.dart';

void main() {
  group('EpubAnchorTarget', () {
    test('parses a same-page fragment', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<a href="#note">note</a>'),
      );

      expect(target?.page, isNull);
      expect(target?.part, 'note');
      expect(target?.externalUri, isNull);
    });

    test('parses backend page and part attributes', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html(
          '<a href="javascript:void(0)" '
          'kavita-page="8" kavita-part="page_8">chapter</a>',
        ),
      );

      expect(target?.page, 8);
      expect(target?.part, 'page_8');
    });

    test('prefers kavita-note-ref over the rewritten href', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html(
          '<a href="javascript:void(0)" '
          'kavita-note-ref="#_footnote_1">*</a>',
        ),
      );

      expect(target?.page, isNull);
      expect(target?.part, '_footnote_1');
    });

    test('parses external links', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<a href="https://example.com/path">external</a>'),
      );

      expect(target?.externalUri, Uri.parse('https://example.com/path'));
    });

    test('normalizes protocol-relative links', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<a href="//example.com/path">external</a>'),
      );

      expect(target?.externalUri, Uri.parse('https://example.com/path'));
    });

    test('ignores no-op javascript links', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<a href="javascript:void(0)">noop</a>'),
      );

      expect(target, isNull);
    });

    test('ignores non-anchor elements', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<span kavita-page="8">chapter</span>'),
      );

      expect(target, isNull);
    });

    test('marks kavita-note-ref links as footnotes', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html(
          '<a href="javascript:void(0)" kavita-page="15" '
          'kavita-part="fn1" kavita-note-ref="fn1">1</a>',
        ),
      );

      expect(target?.page, 15);
      expect(target?.part, 'fn1');
      expect(target?.isFootnote, isTrue);
    });

    test('marks epub:type noteref links as footnotes even with note class', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html(
          '<a class="footnote" epub:type="noteref" href="#n1">1</a>',
        ),
      );

      expect(target?.isFootnote, isTrue);
    });

    test('marks role doc-noteref links as footnotes', () {
      final target = EpubAnchorTarget.fromElement(
        dom.Element.html('<a role="doc-noteref" href="#n2">2</a>'),
      );

      expect(target?.isFootnote, isTrue);
    });

    test('marks inline sup links with preceding text as footnotes', () {
      final fragment = dom.DocumentFragment.html(
        '<p>Claim<sup class="footnote"><a href="#fn1">1</a></sup> '
        'and<a href="#fn2"><sup>2</sup></a>.</p>',
      );
      final links = fragment.querySelectorAll('a');

      expect(EpubAnchorTarget.fromElement(links[0])?.isFootnote, isTrue);
      expect(EpubAnchorTarget.fromElement(links[1])?.isFootnote, isTrue);
    });

    test('excludes start-of-block sup links without preceding text', () {
      final fragment = dom.DocumentFragment.html(
        '<p><sup><a href="#fn1">1</a></sup> Note body at block start.</p>',
      );
      final link = fragment.querySelector('a')!;

      expect(EpubAnchorTarget.fromElement(link)?.isFootnote, isFalse);
    });

    test('excludes backlink anchors inside footnotes', () {
      final fragment = dom.DocumentFragment.html(
        '<p><a role="doc-backlink" epub:type="noteref" href="#ref1">back</a></p>',
      );
      final link = fragment.querySelector('a')!;

      expect(EpubAnchorTarget.fromElement(link)?.isFootnote, isFalse);
    });

    test('excludes links inside aside, nav, and div.footnotes containers', () {
      final fragment = dom.DocumentFragment.html(
        '<div>'
        '<aside><p><sup><a href="#ref1">1</a></sup></p></aside>'
        '<nav epub:type="toc"><p>Part <sup><a href="#ch1">1</a></sup></p></nav>'
        '<div class="footnotes"><p>Lead <sup><a href="#self">1</a></sup></p></div>'
        '</div>',
      );
      final links = fragment.querySelectorAll('a');

      expect(EpubAnchorTarget.fromElement(links[0])?.isFootnote, isFalse);
      expect(EpubAnchorTarget.fromElement(links[1])?.isFootnote, isFalse);
      expect(EpubAnchorTarget.fromElement(links[2])?.isFootnote, isFalse);
    });
  });
}
