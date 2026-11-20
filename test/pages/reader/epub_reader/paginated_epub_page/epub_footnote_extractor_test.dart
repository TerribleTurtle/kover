import 'package:flutter_test/flutter_test.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_footnote_extractor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/node_indexing_operation.dart';
import 'package:kover/utils/constants/html_constants.dart';

void main() {
  group('EpubFootnoteExtractor', () {
    test('extracts a tight list item without neighboring items', () {
      // <ol><li id="note-1">...</li><li id="note-2">...</li></ol>
      final root = dom.DocumentFragment.html(
        '<ol>'
        '<li id="note-1">First footnote text.</li>'
        '<li id="note-2">Second footnote text.</li>'
        '</ol>',
      );

      final html = EpubFootnoteExtractor.extractFromRoot(root, '#note-1');
      final parsed = dom.DocumentFragment.html(html!);

      expect(parsed.text, contains('First footnote text.'));
      expect(parsed.text, isNot(contains('Second footnote text.')));
      expect(parsed.querySelector('#note-1'), isNull);
    });

    test('promotes a single-note aside container across paragraphs', () {
      // <aside><p id="fn1">...</p><p>...</p></aside>
      final root = dom.DocumentFragment.html(
        '<aside epub:type="footnote">'
        '<p id="fn1">First paragraph.</p>'
        '<p>Second paragraph.</p>'
        '</aside>',
      );

      final html = EpubFootnoteExtractor.extractFromRoot(root, 'fn1');
      final parsed = dom.DocumentFragment.html(html!);

      expect(parsed.text, contains('First paragraph.'));
      expect(parsed.text, contains('Second paragraph.'));
    });

    test('isolates matching note inside a shared multi-note container', () {
      // <div class="footnote"><p id="fn1">...</p><p id="fn2">...</p></div>
      final root = dom.DocumentFragment.html(
        '<div class="footnote">'
        '<p id="fn1">First entry.</p>'
        '<p id="fn2">Second entry.</p>'
        '</div>',
      );

      final html = EpubFootnoteExtractor.extractFromRoot(root, '#fn2');
      final parsed = dom.DocumentFragment.html(html!);

      expect(parsed.text, contains('Second entry.'));
      expect(parsed.text, isNot(contains('First entry.')));
    });

    test('promotes an empty anchor id target to its following sibling', () {
      // <div class="footnotes"><a id="fn1"></a><p>...</p><a id="fn2"></a><p>...</p></div>
      final root = dom.DocumentFragment.html(
        '<div class="footnotes">'
        '<a id="fn1"></a><p>First note.</p>'
        '<a id="fn2"></a><p>Second note.</p>'
        '</div>',
      );

      final html = EpubFootnoteExtractor.extractFromRoot(root, 'fn1');
      final parsed = dom.DocumentFragment.html(html!);

      expect(parsed.text, contains('First note.'));
      expect(parsed.text, isNot(contains('Second note.')));
    });

    test(
      'unhides display none inline styles and drops node index only there',
      () {
        // <aside id="fn1" style="display: none; color: red;" kover-node-index="1"><p kover-node-index="2">...</p></aside>
        final root = dom.DocumentFragment.html(
          '<aside id="fn1" style="display: none; color: red;" kover-node-index="1">'
          '<p kover-node-index="2">Revealed note.</p>'
          '</aside>',
        );

        final html = EpubFootnoteExtractor.extractFromRoot(root, '#fn1');
        final parsed = dom.DocumentFragment.html(html!);
        final aside = parsed.querySelector('aside')!;

        expect(
          aside.attributes.containsKey(HtmlConstants.nodeIndexAttribute),
          isFalse,
        );
        expect(aside.attributes['style'], 'color: red;');
        expect(
          parsed
              .querySelector('p')!
              .attributes[HtmlConstants.nodeIndexAttribute],
          '2',
        );
      },
    );

    test('unhides computed display none rules while preserving visible children', () {
      // <style>.hidden-note { display: none; }</style><aside id="fn1" class="hidden-note"><p>...</p></aside>
      final root = EpubPagePreprocessor(
        html: dom.DocumentFragment.html(
          '<style>.hidden-note { display: none; }</style>'
          '<aside id="fn1" class="hidden-note"><p>Computed hidden.</p></aside>',
        ),
        operations: [NodeIndexingOperation()],
      ).process();
      final cssEngine = CssEngine(root: root);

      final html = EpubFootnoteExtractor.extractFromRoot(
        root,
        '#fn1',
        cssEngine: cssEngine,
      );
      final parsed = dom.DocumentFragment.html(html!);

      expect(
        parsed
            .querySelector('aside')!
            .attributes
            .containsKey(
              HtmlConstants.nodeIndexAttribute,
            ),
        isFalse,
      );
      expect(
        parsed.querySelector('p')!.attributes[HtmlConstants.nodeIndexAttribute],
        isNotNull,
      );
    });

    test('marks trim start and end edges inside extracted subtree', () {
      // <div id="fn1"><p>First</p><p>Last</p></div>
      final root = dom.DocumentFragment.html(
        '<div id="fn1"><p>First</p><p>Last</p></div>',
      );

      final html = EpubFootnoteExtractor.extractFromRoot(root, '#fn1');
      final paragraphs = dom.DocumentFragment.html(html!).querySelectorAll('p');

      expect(
        paragraphs.first.attributes.containsKey(
          HtmlConstants.trimStartAttribute,
        ),
        isTrue,
      );
      expect(
        paragraphs.last.attributes.containsKey(HtmlConstants.trimEndAttribute),
        isTrue,
      );
    });

    test(
      'extractRemote preprocesses stylesheets and extracts matching note',
      () {
        // <style>.n { color: blue; }</style><aside id="fn1" class="n"><p>...</p></aside>
        final remote = EpubFootnoteExtractor.extractRemote(
          dom.DocumentFragment.html(
            '<style>.n { color: blue; }</style>'
            '<aside id="fn1" class="n"><p>Remote note.</p></aside>',
          ),
          '#fn1',
        );

        expect(remote, isNotNull);
        final parsed = dom.DocumentFragment.html(remote!.html);
        expect(parsed.text, contains('Remote note.'));
        expect(
          remote.cssEngine.stylesFor(
            element: parsed.querySelector('aside')!,
          )?['color'],
          '#00f',
        );
      },
    );

    test('returns null for missing targets, wrappers, or empty notes', () {
      // <div id="wrap" class="kover-content"><aside id="empty"></aside></div>
      final root = dom.DocumentFragment.html(
        '<div id="wrap" class="${HtmlConstants.koverWrapperClass}">'
        '<aside id="empty"></aside>'
        '</div>',
      );

      expect(EpubFootnoteExtractor.extractFromRoot(root, '#missing'), isNull);
      expect(EpubFootnoteExtractor.extractFromRoot(root, '#wrap'), isNull);
      expect(EpubFootnoteExtractor.extractFromRoot(root, '#empty'), isNull);
    });
  });
}
