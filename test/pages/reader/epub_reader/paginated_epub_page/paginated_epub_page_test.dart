import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/epub_theme_override.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_footnote_bottom_sheet.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_paginator.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/factories/paginated_epub_widget_factory.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_break.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_break_unit.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_measurements_collector.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_controller_status.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/link_normalization_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/node_indexing_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/render_html.dart';
import 'package:kover/pages/reader/overlay/overlay_gestures.dart';
import 'package:kover/pages/reader/overlay/overlay_gestures_provider.dart';
import 'package:kover/riverpod/providers/settings/epub_reader_settings.dart';
import 'package:kover/utils/html_constants.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('EpubPaginator', () {
    test('renders a document that fits on a single page', () {
      final paginator = _paginator('<div><p>Only page</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(nodeIndex: block, bottom: 10),
      ], 100);

      expect(paginator.subpageCount, 1);
      expect(paginator.getSubpage(0), contains('Only page'));
    });

    test('starts the first page at the document origin', () {
      final paginator = _paginator('<div><p>AAAA BBBB</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(nodeIndex: block, top: 32, bottom: 42, childPath: const [0]),
        _line(
          nodeIndex: block,
          top: 42,
          bottom: 52,
          offset: 4,
          childPath: const [0],
        ),
      ], 42);

      expect(paginator.subpageCount, 2);
      expect(paginator.getSubpage(0), isNot(contains('BBBB')));
      expect(paginator.getSubpage(1), contains('BBBB'));
    });

    test('splits a paragraph at line offsets', () {
      final paginator = _paginator('<div><p>AAAA BBBB CCCC</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(
          nodeIndex: block,
          top: 0,
          bottom: 10,
          offset: 0,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 10,
          bottom: 20,
          offset: 5,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 20,
          bottom: 30,
          offset: 10,
          childPath: const [0],
        ),
      ], 25);

      expect(paginator.subpageCount, 2);

      final first = paginator.getSubpage(0);
      final second = paginator.getSubpage(1);

      expect(first, contains('AAAA BBBB'));
      expect(first, isNot(contains('CCCC')));

      expect(second, contains('CCCC'));
      expect(second, isNot(contains('AAAA')));
    });

    test('marks a paragraph continued from the previous page', () {
      final paginator = _paginator('<div><p>AAAA BBBB CCCC</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(
          nodeIndex: block,
          top: 0,
          bottom: 10,
          offset: 0,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 10,
          bottom: 20,
          offset: 5,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 20,
          bottom: 30,
          offset: 10,
          childPath: const [0],
        ),
      ], 25);

      final first = dom.DocumentFragment.html(paginator.getSubpage(0));
      final second = dom.DocumentFragment.html(paginator.getSubpage(1));

      expect(
        first
            .querySelector('p')!
            .attributes
            .containsKey(HtmlConstants.splitParagraphAttribute),
        isFalse,
      );
      expect(
        second
            .querySelector('p')!
            .attributes
            .containsKey(HtmlConstants.splitParagraphAttribute),
        isTrue,
      );
    });

    test('keeps page boundaries between consecutive subpages', () {
      final paginator = _paginator(
        '<div><p>ONE TWO THREE FOUR FIVE SIX</p></div>',
      );
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(
          nodeIndex: block,
          top: 0,
          bottom: 10,
          offset: 0,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 10,
          bottom: 20,
          offset: 4,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 20,
          bottom: 30,
          offset: 8,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 30,
          bottom: 40,
          offset: 14,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 40,
          bottom: 50,
          offset: 19,
          childPath: const [0],
        ),
        _line(
          nodeIndex: block,
          top: 50,
          bottom: 60,
          offset: 24,
          childPath: const [0],
        ),
      ], 20);

      expect(paginator.subpageCount, 3);

      final pages = [
        paginator.getSubpage(0),
        paginator.getSubpage(1),
        paginator.getSubpage(2),
      ];

      expect(pages[0], contains('ONE TWO'));
      expect(pages[0], isNot(contains('THREE')));

      expect(pages[1], contains('THREE FOUR'));
      expect(pages[1], isNot(contains('ONE')));
      expect(pages[1], isNot(contains('FIVE')));

      expect(pages[2], contains('FIVE SIX'));
      expect(pages[2], isNot(contains('THREE')));
    });

    test('accounts for preserved spacing at split boundaries', () {
      final paginator = _paginator('<div><p>AAAA BBBB</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(
          nodeIndex: block,
          top: 32,
          bottom: 42,
          topInset: 32,
          bottomInset: 32,
        ),
        _line(
          nodeIndex: block,
          top: 42,
          bottom: 52,
          topInset: 32,
          bottomInset: 32,
        ),
      ], 74);

      expect(paginator.subpageCount, 2);
    });

    test('splits at a block boundary and keeps wrappers', () {
      final paginator = _paginator(
        '<div class="kavita-wrapper">'
        '<div class="kover-wrapper">'
        '<p>Intro</p>'
        '<p>Second</p>'
        '</div>'
        '</div>',
      );
      final paragraphs = paginator.root.querySelectorAll('p');
      final firstBlock = _nodeIndex(paragraphs[0]);
      final secondBlock = _nodeIndex(paragraphs[1]);

      paginator.paginate([
        _line(nodeIndex: firstBlock, top: 0, bottom: 10),
        _line(nodeIndex: secondBlock, top: 20, bottom: 30),
      ], 20);

      expect(paginator.subpageCount, 2);

      final first = paginator.getSubpage(0);
      final last = paginator.getSubpage(1);

      expect(first, contains('Intro'));
      expect(first, isNot(contains('Second')));
      expect(first, contains('kover-wrapper'));

      expect(last, contains('Second'));
      expect(last, isNot(contains('Intro')));
      expect(last, contains('kover-wrapper'));
      expect(
        dom.DocumentFragment.html(
              last,
            )
            .querySelector('p')!
            .attributes
            .containsKey(
              HtmlConstants.splitParagraphAttribute,
            ),
        isFalse,
      );
    });

    test('handles a break after a line break', () {
      final paginator = _paginator('<div><p>aa<br>bb</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(nodeIndex: block, bottom: 10, childPath: const [0]),
        _line(
          nodeIndex: block,
          top: 10,
          bottom: 20,
          childPath: const [1],
          afterNode: true,
        ),
      ], 15);

      expect(paginator.subpageCount, 2);

      final first = paginator.getSubpage(0);
      final last = paginator.getSubpage(1);

      expect(first, contains('aa'));
      expect(first, isNot(contains('bb')));

      expect(last, contains('bb'));
      expect(last, isNot(contains('aa')));
    });

    test('splits before a leaf element', () {
      final paginator = _paginator(
        '<div><p>Before</p><img src="image.png"></div>',
      );
      final image = _nodeIndexOf(paginator.root, 'img');

      paginator.paginate([
        _line(nodeIndex: _nodeIndexOf(paginator.root, 'p'), top: 0, bottom: 10),
        _line(nodeIndex: image, top: 20, bottom: 30, isLeaf: true),
      ], 15);

      expect(paginator.subpageCount, 2);

      final first = paginator.getSubpage(0);
      final last = paginator.getSubpage(1);

      expect(first, contains('Before'));
      expect(first, isNot(contains('<img')));

      expect(last, contains('<img'));
      expect(last, isNot(contains('Before')));
    });

    test('returns no subpage before pagination and for invalid indices', () {
      final paginator = _paginator('<div><p>Text</p></div>');

      expect(paginator.subpageCount, 0);
      expect(paginator.getSubpage(0), isEmpty);

      final block = _nodeIndexOf(paginator.root, 'p');
      paginator.paginate([_line(nodeIndex: block, bottom: 10)], 100);

      expect(paginator.getSubpage(-1), isEmpty);
      expect(paginator.getSubpage(1), isEmpty);
    });
  });

  group('PaginatedEpubPageController', () {
    test('paginates against the viewport height, not the content height', () {
      final controller = PaginatedEpubPageController();
      final paginator = _paginator('<div><p>AAAA BBBB CCCC</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      controller.attachRoot(paginator.root, settings: _pageSettings());
      controller.processMeasurements(
        EpubMeasurements(
          // The whole document is much taller than the viewport.
          contentSize: const Size(100, 1000),
          units: [
            _line(
              nodeIndex: block,
              top: 0,
              bottom: 10,
              offset: 0,
              childPath: const [0],
            ),
            _line(
              nodeIndex: block,
              top: 10,
              bottom: 20,
              offset: 5,
              childPath: const [0],
            ),
            _line(
              nodeIndex: block,
              top: 20,
              bottom: 30,
              offset: 10,
              childPath: const [0],
            ),
          ],
        ),
        viewport: const Size(100, 25),
      );

      expect(controller.status, PaginatedEpubPageControllerStatus.ready);
      expect(controller.subpageCount, 2);
      expect(controller.getSubpage(0), isNotEmpty);
      expect(controller.currentSubpage, 0);

      controller.nextSubpage();
      expect(controller.currentSubpage, 1);

      controller.nextSubpage();
      expect(controller.currentSubpage, 1);
    });

    test('does not re-notify when jumping to the current subpage', () {
      final changes = <int>[];
      final controller = PaginatedEpubPageController(
        onSubpageChanged: (subpage, _) => changes.add(subpage),
      );
      final paginator = _paginator('<div><p>AAAA BBBB CCCC</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      controller.attachRoot(paginator.root, settings: _pageSettings());
      controller.processMeasurements(
        EpubMeasurements(
          contentSize: const Size(100, 1000),
          units: [
            _line(nodeIndex: block, bottom: 10, childPath: const [0]),
            _line(
              nodeIndex: block,
              top: 10,
              bottom: 20,
              offset: 5,
              childPath: const [0],
            ),
            _line(
              nodeIndex: block,
              top: 20,
              bottom: 30,
              offset: 10,
              childPath: const [0],
            ),
          ],
        ),
        viewport: const Size(100, 25),
      );
      changes.clear();

      var notifications = 0;
      controller.addListener(() => notifications++);

      // The navigation provider re-syncs the current subpage on every state
      // change; this must not notify back or the two loop forever.
      controller.jumpToSubpage(0);

      expect(notifications, 0);
      expect(changes, isEmpty);

      controller.nextSubpage();

      expect(controller.currentSubpage, 1);
      expect(notifications, 1);
      expect(changes, [1]);

      controller.jumpToSubpage(1);

      expect(notifications, 1);
      expect(changes, [1]);
    });

    test('viewportChanged only notifies when leaving the ready state', () {
      final controller = PaginatedEpubPageController();
      final paginator = _paginator('<div><p>Only page</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');

      controller.attachRoot(paginator.root, settings: _pageSettings());

      var notifications = 0;
      controller.addListener(() => notifications++);

      controller.viewportChanged(const Size(100, 10));

      expect(notifications, 0);
      expect(controller.status, PaginatedEpubPageControllerStatus.measuring);

      controller.processMeasurements(
        EpubMeasurements(
          contentSize: const Size(100, 10),
          units: [_line(nodeIndex: block, bottom: 10)],
        ),
        viewport: const Size(100, 100),
      );

      expect(notifications, 1);
      expect(controller.status, PaginatedEpubPageControllerStatus.ready);

      controller.viewportChanged(const Size(100, 120));

      expect(notifications, 2);
      expect(controller.status, PaginatedEpubPageControllerStatus.measuring);

      controller.viewportChanged(const Size(100, 120));

      expect(notifications, 2);
    });

    test('applies a pending subpage after pagination', () {
      final controller = PaginatedEpubPageController();
      final paginator = _paginator(
        '<div><p>First</p><p>Second</p></div>',
      );
      final blocks = [
        for (final paragraph in paginator.root.querySelectorAll('p'))
          _nodeIndex(paragraph),
      ];

      controller.attachRoot(paginator.root, settings: _pageSettings());
      controller.setPendingSubpage(1);
      controller.processMeasurements(
        EpubMeasurements(
          contentSize: const Size(100, 20),
          units: [
            _line(nodeIndex: blocks[0], bottom: 10),
            _line(nodeIndex: blocks[1], top: 10, bottom: 20),
          ],
        ),
        viewport: const Size(100, 10),
      );

      expect(controller.currentSubpage, 1);
    });

    test('resumes at the initial xpath and reports its scroll id', () {
      final html = dom.DocumentFragment.html(
        '<div><p>first</p><p>second</p><p>third</p></div>',
      );
      final probe = PaginatedEpubPageController()
        ..attachRoot(html, settings: _pageSettings());
      final paragraphs = probe.root!.querySelectorAll('p');
      final secondScrollId =
          paragraphs[1].attributes[HtmlConstants.scrollIdAttribute]!;

      final changes = <(int, String?)>[];
      final controller = PaginatedEpubPageController(
        onSubpageChanged: (subpage, scrollId) {
          changes.add((subpage, scrollId));
        },
      );

      controller.attachRoot(
        html,
        settings: _pageSettings(highlightResumePoint: true),
        initialXpath: secondScrollId,
        additionalStyles: {
          '.${HtmlConstants.resumeClass}': {'background-color': 'red'},
        },
      );

      final blocks = [
        for (final paragraph in controller.root!.querySelectorAll('p'))
          _nodeIndex(paragraph),
      ];

      controller.processMeasurements(
        EpubMeasurements(
          contentSize: const Size(100, 30),
          units: [
            _line(nodeIndex: blocks[0], bottom: 10),
            _line(nodeIndex: blocks[1], top: 10, bottom: 20),
            _line(nodeIndex: blocks[2], top: 20, bottom: 30),
          ],
        ),
        viewport: const Size(100, 10),
      );

      expect(controller.currentSubpage, 1);
      expect(changes, [(1, secondScrollId)]);
      expect(controller.scrollIdForSubpage(1), secondScrollId);
      expect(
        controller.root!.querySelector('.${HtmlConstants.resumeClass}'),
        isNotNull,
      );
      expect(
        controller.cssEngine.stylesFor(
          controller.root!.querySelectorAll('p')[1],
        )?['background-color'],
        'red',
      );
    });

    test('updateSettings toggles the resume highlight class', () {
      final html = dom.DocumentFragment.html('<div><p>first</p></div>');
      final probe = PaginatedEpubPageController()
        ..attachRoot(html, settings: _pageSettings());
      final scrollId = probe.root!
          .querySelector('p')!
          .attributes[HtmlConstants.scrollIdAttribute]!;

      final controller = PaginatedEpubPageController()
        ..attachRoot(
          html,
          settings: _pageSettings(),
          initialXpath: scrollId,
        );

      expect(
        controller.root!.querySelector('.${HtmlConstants.resumeClass}'),
        isNull,
      );

      controller.updateSettings(
        _pageSettings(highlightResumePoint: true),
      );
      expect(
        controller.root!.querySelectorAll('p').first.classes,
        contains(HtmlConstants.resumeClass),
      );

      controller.updateSettings(_pageSettings());
      expect(
        controller.root!.querySelectorAll('p').first.classes,
        isNot(contains(HtmlConstants.resumeClass)),
      );
    });

    test('jumpToAnchor jumps to target subpage when ready', () {
      final controller = PaginatedEpubPageController();
      final html = dom.DocumentFragment.html(
        '<div><p id="first">First</p><p id="second">Second</p></div>',
      );

      controller.attachRoot(html, settings: _pageSettings());
      final blocks = [
        for (final paragraph in controller.root!.querySelectorAll('p'))
          _nodeIndex(paragraph),
      ];

      controller.processMeasurements(
        EpubMeasurements(
          contentSize: const Size(100, 20),
          units: [
            _line(nodeIndex: blocks[0], bottom: 10),
            _line(nodeIndex: blocks[1], top: 10, bottom: 20),
          ],
        ),
        viewport: const Size(100, 10),
      );

      expect(controller.currentSubpage, 0);

      final jumped = controller.jumpToAnchor('second');
      expect(jumped, isTrue);
      expect(controller.currentSubpage, 1);
    });

    test(
      'setPendingAnchor resolves anchor when measurements are processed',
      () {
        final controller = PaginatedEpubPageController();
        final html = dom.DocumentFragment.html(
          '<div><p id="first">First</p><p id="second">Second</p></div>',
        );

        controller.attachRoot(html, settings: _pageSettings());
        controller.setPendingAnchor('second');

        final blocks = [
          for (final paragraph in controller.root!.querySelectorAll('p'))
            _nodeIndex(paragraph),
        ];

        controller.processMeasurements(
          EpubMeasurements(
            contentSize: const Size(100, 20),
            units: [
              _line(nodeIndex: blocks[0], bottom: 10),
              _line(nodeIndex: blocks[1], top: 10, bottom: 20),
            ],
          ),
          viewport: const Size(100, 10),
        );

        expect(controller.currentSubpage, 1);
      },
    );
  });

  group('subpageForAnchor', () {
    test('resolves anchor directly on measured block node (tier 1)', () {
      final paginator = _paginator(
        '<div><p id="first">First</p><p id="second">Second</p></div>',
      );
      final paragraphs = paginator.root.querySelectorAll('p');
      final firstBlock = _nodeIndex(paragraphs[0]);
      final secondBlock = _nodeIndex(paragraphs[1]);

      paginator.paginate([
        _line(nodeIndex: firstBlock, top: 0, bottom: 10),
        _line(nodeIndex: secondBlock, top: 20, bottom: 30),
      ], 15);

      expect(paginator.subpageForAnchor('first'), 0);
      expect(paginator.subpageForAnchor('#second'), 1);
    });

    test('resolves anchor on child element via ancestor block (tier 1)', () {
      final paginator = _paginator(
        '<div><p><span id="target">Span inside</span></p></div>',
      );
      final block = _nodeIndexOf(paginator.root, 'p');

      paginator.paginate([
        _line(nodeIndex: block, bottom: 10),
      ], 100);

      expect(paginator.subpageForAnchor('target'), 0);
    });

    test(
      'resolves anchor preceding measured block via next smallest node index (tier 2)',
      () {
        final paginator = _paginator(
          '<div><p>Intro</p><a id="fn1"></a><p>Target note</p></div>',
        );
        final paragraphs = paginator.root.querySelectorAll('p');
        final firstBlock = _nodeIndex(paragraphs[0]);
        final secondBlock = _nodeIndex(paragraphs[1]);

        paginator.paginate([
          _line(nodeIndex: firstBlock, top: 0, bottom: 10),
          _line(nodeIndex: secondBlock, top: 20, bottom: 30),
        ], 15);

        expect(paginator.subpageForAnchor('fn1'), 1);
      },
    );

    test('resolves anchor via subpage html scan fallback (tier 3)', () {
      final paginator = _paginator(
        '<div><p>Page 1</p><p>Page 2</p><div id="fallback"><p>Notes</p></div></div>',
      );
      final paragraphs = paginator.root.querySelectorAll('p');
      final firstBlock = _nodeIndex(paragraphs[0]);
      final secondBlock = _nodeIndex(paragraphs[1]);

      paginator.paginate([
        _line(nodeIndex: firstBlock, top: 0, bottom: 10),
        _line(nodeIndex: secondBlock, top: 20, bottom: 30),
      ], 15);

      expect(paginator.subpageForAnchor('fallback'), 1);
    });

    test('returns null for missing or empty anchor', () {
      final paginator = _paginator('<div><p>Text</p></div>');
      final block = _nodeIndexOf(paginator.root, 'p');
      paginator.paginate([_line(nodeIndex: block, bottom: 10)], 100);

      expect(paginator.subpageForAnchor('missing'), isNull);
      expect(paginator.subpageForAnchor(''), isNull);
      expect(paginator.subpageForAnchor('#'), isNull);
    });
  });

  group('LinkNormalizationOperation', () {
    test('normalizes kavita note reference into kover://note', () {
      final processed = _processHtml(
        '<div><a href="javascript:void(0)" kavita-note-ref="fn1">1</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(link.attributes['href'], 'kover://note?ref=fn1');
    });

    test('normalizes kavita note reference with page into kover://note', () {
      final processed = _processHtml(
        '<div><a href="javascript:void(0)" kavita-note-ref="fn1" kavita-page="5">1</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(link.attributes['href'], 'kover://note?ref=fn1&page=5');
    });

    test('normalizes epub:type noteref with anchor href into kover://note', () {
      final processed = _processHtml(
        '<div><a href="#fn1" epub:type="noteref">1</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(link.attributes['href'], 'kover://note?ref=fn1');
    });

    test(
      'normalizes kavita-rewritten epub3 noteref, cross-page superscript, and inline footnote markers while keeping backlinks as kover://link',
      () {
        final processed = _processHtml(
          '<div>'
          '<p>Text<a epub:type="noteref" kavita-page="0" kavita-part="n1" href="javascript:void(0)">1</a>'
          '<a kavita-page="8" kavita-part="d5e1640" href="javascript:void(0)"><sup>2</sup></a>'
          '<a id="fn-back" kavita-page="0" kavita-part="fn-body" href="javascript:void(0)">[3]</a>'
          '<a class="calibre16" kavita-page="15" kavita-part="filepos806267" href="javascript:void(0)"><sup class="calibre7"><span class="calibre17">4</span></sup></a>'
          '<a class="calibre16" kavita-page="8" kavita-part="calibre-fn" href="javascript:void(0)"><span class="calibre7">[5]</span></a>'
          '<a class="_idFootnoteLink" kavita-page="9" kavita-part="indesign-fn" href="javascript:void(0)">6</a>'
          '<a kavita-page="9" kavita-part="unicode-fn" href="javascript:void(0)">¹</a></p>'
          '<aside epub:type="footnote" id="n1"><p>Corrected.</p></aside>'
          '<p class="fn" id="d5e1640">2. Strange history.</p>'
          '<aside id="footnotes"><article id="fn-body"><p><a kavita-page="0" kavita-part="fn-back" href="javascript:void(0)">3</a> Body.</p></article></aside>'
          '<p class="calibre31" id="calibre-fn"><a kavita-page="8" kavita-part="fn-back" href="javascript:void(0)">[5]</a> Calibre note.</p>'
          '</div>',
        );
        final links = processed.querySelectorAll('a');

        expect(links[0].attributes['href'], 'kover://note?ref=n1');
        expect(links[1].attributes['href'], 'kover://note?ref=d5e1640&page=8');
        expect(links[2].attributes['href'], 'kover://note?ref=fn-body');
        expect(
          links[3].attributes['href'],
          'kover://note?ref=filepos806267&page=15',
        );
        expect(
          links[4].attributes['href'],
          'kover://note?ref=calibre-fn&page=8',
        );
        expect(
          links[5].attributes['href'],
          'kover://note?ref=indesign-fn&page=9',
        );
        expect(
          links[6].attributes['href'],
          'kover://note?ref=unicode-fn&page=9',
        );
        expect(links[7].attributes['href'], 'kover://link?part=fn-back');
        expect(
          links[8].attributes['href'],
          'kover://link?page=8&part=fn-back',
        );
      },
    );

    test('normalizes kavita cross-page link into kover://link', () {
      final processed = _processHtml(
        '<div><a href="javascript:void(0)" kavita-page="2" kavita-part="ch02.xhtml">Chapter 2</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(link.attributes['href'], 'kover://link?page=2');
    });

    test('normalizes kavita cross-page link with anchor into kover://link', () {
      final processed = _processHtml(
        '<div><a href="javascript:void(0)" kavita-page="2" kavita-part="#sec1">Section 1</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(
        link.attributes['href'],
        'kover://link?page=2&part=sec1',
      );
    });

    test('normalizes internal anchor link into kover://link', () {
      final processed = _processHtml(
        '<div><a href="#sec1">Section 1</a></div>',
      );
      final link = processed.querySelector('a')!;

      expect(link.attributes['href'], 'kover://link?part=sec1');
    });

    test('leaves external URLs and raw javascript links untouched', () {
      final processed = _processHtml(
        '<div>'
        '<a href="https://example.com/doc">External</a>'
        '<a href="javascript:void(0)">Noop</a>'
        '</div>',
      );
      final links = processed.querySelectorAll('a');

      expect(links[0].attributes['href'], 'https://example.com/doc');
      expect(links[1].attributes['href'], 'javascript:void(0)');
    });

    test('parses all link target types', () {
      expect(
        EpubLinkTarget.parse('kover://note?ref=fn1&page=5'),
        const EpubFootnoteLinkTarget(ref: 'fn1', page: 5),
      );
      expect(
        EpubLinkTarget.parse('kover://link?page=2&part=sec1'),
        const EpubInternalLinkTarget(
          page: 2,
          anchorId: 'sec1',
        ),
      );
      expect(
        EpubLinkTarget.parse('#sec1'),
        const EpubInternalLinkTarget(anchorId: 'sec1'),
      );
      expect(
        EpubLinkTarget.parse('https://example.com'),
        const EpubExternalLinkTarget(url: 'https://example.com'),
      );
      expect(EpubLinkTarget.parse('javascript:void(0)'), isNull);
    });
  });

  group('extractFootnoteHtml', () {
    test(
      'extracts block footnote and strips id and visually-hidden while preserving original DOM',
      () {
        final controller = PaginatedEpubPageController();
        final fragment = dom.DocumentFragment.html(
          '<div>'
          '<p>Main text</p>'
          '<aside id="fn1" class="visually-hidden">Footnote content</aside>'
          '</div>',
        );
        controller.attachRoot(fragment, settings: _pageSettings());

        final footnoteHtml = controller.extractFootnoteHtml('fn1');
        expect(footnoteHtml, isNotNull);
        expect(footnoteHtml, contains(HtmlConstants.koverWrapperClass));
        expect(footnoteHtml, contains('Footnote content'));
        expect(
          footnoteHtml,
          isNot(contains(HtmlConstants.visuallyHiddenClass)),
        );
        expect(footnoteHtml, isNot(contains('id="fn1"')));

        final originalAside = controller.root?.querySelector('aside');
        expect(originalAside?.id, 'fn1');
        expect(
          originalAside?.classes.contains(HtmlConstants.visuallyHiddenClass),
          isTrue,
        );

        expect(controller.extractFootnoteHtml('#fn1'), footnoteHtml);
      },
    );

    test('promotes inline marker to parent paragraph', () {
      final controller = PaginatedEpubPageController();
      final fragment = dom.DocumentFragment.html(
        '<div>'
        '<p>Chapter body</p>'
        '<p>Note prefix: <a id="fn1">1.</a> Note body text</p>'
        '</div>',
      );
      controller.attachRoot(fragment, settings: _pageSettings());

      final footnoteHtml = controller.extractFootnoteHtml('fn1');
      expect(footnoteHtml, isNotNull);
      expect(footnoteHtml, contains('<p'));
      expect(footnoteHtml, contains('Note body text'));
      expect(footnoteHtml, contains('<a'));
      expect(footnoteHtml, isNot(contains('id="fn1"')));

      final originalAnchor = controller.root?.querySelector('a');
      expect(originalAnchor?.id, 'fn1');
    });

    test('promotes inline marker to parent list item', () {
      final controller = PaginatedEpubPageController();
      final fragment = dom.DocumentFragment.html(
        '<div>'
        '<ol>'
        '<li><a id="fn2">2.</a> List note body</li>'
        '</ol>'
        '</div>',
      );
      controller.attachRoot(fragment, settings: _pageSettings());

      final footnoteHtml = controller.extractFootnoteHtml('fn2');
      expect(footnoteHtml, isNotNull);
      expect(footnoteHtml, contains('<li'));
      expect(footnoteHtml, contains('List note body'));
      expect(footnoteHtml, isNot(contains('id="fn2"')));
    });

    test('returns null for missing, empty, or whitespace-only footnotes', () {
      final controller = PaginatedEpubPageController();
      expect(controller.extractFootnoteHtml('fn1'), isNull);

      final fragment = dom.DocumentFragment.html(
        '<style>.hidden { display: none; } p { color: green; }</style>'
        '<div>'
        '<p id="blank">   </p>'
        '<p id="valid">Valid content</p>'
        '<p class="fn" id="multi">1. First paragraph.</p>'
        '<p class="fn1" id="multi-cont">Second paragraph.</p>'
        '<dl><dt id="dl-fn">[1]</dt><dd>Definition note body.</dd></dl>'
        '<div class="footnote"><p><a id="pg-fn">[2]</a> Gutenberg first.</p><p>Gutenberg second.</p></div>'
        '<article id="hr-fn" class="hidden"><hr><p>Article note.</p></article>'
        '</div>',
      );
      controller.attachRoot(fragment, settings: _pageSettings());

      expect(controller.extractFootnoteHtml(''), isNull);
      expect(controller.extractFootnoteHtml('#'), isNull);
      expect(controller.extractFootnoteHtml('missing'), isNull);
      expect(controller.extractFootnoteHtml('blank'), isNull);
      expect(controller.extractFootnoteHtml('valid'), isNotNull);

      final multiHtml = controller.extractFootnoteHtml('multi');
      expect(multiHtml, contains('First paragraph.'));
      expect(multiHtml, contains('Second paragraph.'));

      final dlHtml = controller.extractFootnoteHtml('dl-fn');
      expect(dlHtml, contains('[1]'));
      expect(dlHtml, contains('Definition note body.'));

      final pgHtml = controller.extractFootnoteHtml('pg-fn');
      expect(pgHtml, contains('Gutenberg first.'));
      expect(pgHtml, contains('Gutenberg second.'));

      final hrHtml = controller.extractFootnoteHtml('hr-fn');
      expect(hrHtml, isNotNull);
      expect(hrHtml, isNot(contains('<hr')));
      final hrFragment = dom.DocumentFragment.html(hrHtml!);
      expect(
        controller.cssEngine.stylesFor(hrFragment.querySelector('article')!),
        isNull,
      );
      expect(
        controller.cssEngine.stylesFor(
          hrFragment.querySelector('p')!,
        )?['color'],
        '#008000',
      );

      final remote = controller.extractRemoteFootnote(
        dom.DocumentFragment.html(
          '<style>.calibre31 { color: blue; }</style>'
          '<div><p class="calibre31" id="filepos806267"><sup>1</sup><span>Remote note body</span></p></div>',
        ),
        'filepos806267',
      );
      expect(remote, isNotNull);
      expect(remote!.html, contains('Remote note body'));
      final remoteParagraph = dom.DocumentFragment.html(
        remote.html,
      ).querySelector('p')!;
      expect(remote.cssEngine.stylesFor(remoteParagraph)?['color'], '#00f');
    });
  });

  group('RenderHtml onTapUrl', () {
    test(
      'onTapUrl return contract returns true for kover and javascript, false for external urls',
      () {
        bool handleUrl(String url) {
          final target = EpubLinkTarget.parse(url);
          if (target == null) return true;
          return switch (target) {
            EpubFootnoteLinkTarget() || EpubInternalLinkTarget() => true,
            EpubExternalLinkTarget() => false,
          };
        }

        expect(handleUrl('kover://note?ref=fn1'), isTrue);
        expect(handleUrl('kover://link?page=2'), isTrue);
        expect(handleUrl('#anchor1'), isTrue);
        expect(handleUrl('javascript:void(0)'), isTrue);
        expect(handleUrl('https://example.com/guide'), isFalse);
        expect(handleUrl('http://example.com/'), isFalse);
      },
    );

    testWidgets('attaches onTapUrl callback to HtmlWidget', (
      tester,
    ) async {
      String? tappedUrl;
      const html = '<div><a href="kover://note?ref=fn1">Note Link</a></div>';
      final cssEngine = CssEngine(root: dom.DocumentFragment.html(html));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RenderHtml(
              html: html,
              cssEngine: cssEngine,
              factoryBuilder: () => PaginatedEpubWidgetFactory(),
              onTapUrl: (url) {
                tappedUrl = url;
                return true;
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final linkFinder = find.text('Note Link', findRichText: true);
      await tester.tapAt(tester.getTopLeft(linkFinder) + const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(tappedUrl, 'kover://note?ref=fn1');
    });

    testWidgets(
      'tapping links in PaginatedEpubPage under OverlayGestures fires onTapUrl without firing overlay tap callbacks',
      (tester) async {
        final controller = PaginatedEpubPageController();
        addTearDown(controller.dispose);
        final tappedUrls = <String>[];
        var centerTaps = 0;
        var leftTaps = 0;
        var rightTaps = 0;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              overlayGesturesProvider(seriesId: 1).overrideWithValue(
                AsyncData(
                  OverlayGesturesModel(
                    navigationGestures: true,
                    readDirection: .leftToRight,
                  ),
                ),
              ),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: SizedBox(
                  width: 400,
                  height: 600,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PaginatedEpubPage(
                          controller: controller,
                          html: dom.DocumentFragment.html(
                            '<div>'
                            '<p><a href="#sec1">Jump to Section</a></p>'
                            '<p>Body text<sup><a href="javascript:void(0)" kavita-note-ref="fn1">[1]</a></sup></p>'
                            '</div>',
                          ),
                          settings: _pageSettings(),
                          onTapUrl: (url) {
                            tappedUrls.add(url);
                            return true;
                          },
                        ),
                      ),
                      Positioned.fill(
                        child: OverlayGestures(
                          seriesId: 1,
                          onCenterTap: () => centerTaps++,
                          onLeftTap: () => leftTaps++,
                          onRightTap: () => rightTaps++,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        final linkFinder = find.text('Jump to Section', findRichText: true);
        await tester.tapAt(tester.getCenter(linkFinder));
        await tester.pumpAndSettle();

        expect(tappedUrls, ['kover://link?part=sec1']);
        expect(centerTaps, 0);
        expect(leftTaps, 0);
        expect(rightTaps, 0);

        final supLinkFinder = find.text('[1]', findRichText: true);
        await tester.tapAt(tester.getCenter(supLinkFinder));
        await tester.pumpAndSettle();

        expect(tappedUrls, [
          'kover://link?part=sec1',
          'kover://note?ref=fn1',
        ]);
        expect(centerTaps, 0);
        expect(leftTaps, 0);
        expect(rightTaps, 0);
      },
    );
  });

  group('showEpubFootnoteBottomSheet', () {
    testWidgets(
      'renders below EpubThemeOverride without nested scaffold and reuses cssEngine',
      (tester) async {
        final controller = PaginatedEpubPageController();
        final fragment = dom.DocumentFragment.html(
          '<style>.footnote-text { color: red; }</style>'
          '<div>'
          '<p>Main text</p>'
          '<p id="fn1" class="footnote-text">Footnote with style</p>'
          '</div>',
        );
        controller.attachRoot(fragment, settings: _pageSettings());

        final footnoteHtml = controller.extractFootnoteHtml('fn1');
        expect(footnoteHtml, isNotNull);

        BuildContext? capturedContext;

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              epubReaderSettingsProvider(seriesId: 1).overrideWithBuild(
                (_, _) => const EpubReaderSettingsState(),
              ),
            ],
            child: MaterialApp(
              home: EpubThemeOverride(
                seriesId: 1,
                child: Builder(
                  builder: (context) {
                    capturedContext = context;
                    return const SizedBox.shrink();
                  },
                ),
              ),
            ),
          ),
        );

        expect(find.byType(Scaffold), findsOneWidget);

        unawaited(
          showEpubFootnoteBottomSheet(
            capturedContext!,
            html: footnoteHtml!,
            settings: _pageSettings(),
            cssEngine: controller.cssEngine,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(EpubFootnoteBottomSheet), findsOneWidget);
        expect(find.byType(Scaffold), findsOneWidget);
        expect(find.byType(RenderHtml), findsOneWidget);
        expect(
          find.text('Footnote with style', findRichText: true),
          findsOneWidget,
        );

        final footnoteElement = dom.DocumentFragment.html(footnoteHtml)
            .querySelector('p')!;
        final styles = controller.cssEngine.stylesFor(footnoteElement);
        expect(styles?['color'], '#f00');
      },
    );

    testWidgets('tapping internal link in bottom sheet invokes onTapUrl', (
      tester,
    ) async {
      final controller = PaginatedEpubPageController();
      final fragment = dom.DocumentFragment.html(
        '<div>'
        '<p id="fn1"><a href="#ref1">Back</a></p>'
        '</div>',
      );
      controller.attachRoot(fragment, settings: _pageSettings());

      final footnoteHtml = controller.extractFootnoteHtml('fn1')!;
      String? tappedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  unawaited(
                    showEpubFootnoteBottomSheet(
                      context,
                      html: footnoteHtml,
                      settings: _pageSettings(),
                      cssEngine: controller.cssEngine,
                      onTapUrl: (url) {
                        tappedUrl = url;
                        Navigator.of(context).pop();
                        return true;
                      },
                    ),
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.byType(EpubFootnoteBottomSheet), findsOneWidget);

      final backFinder = find.text('Back', findRichText: true);
      await tester.tapAt(tester.getTopLeft(backFinder) + const Offset(10, 10));
      await tester.pumpAndSettle();

      expect(tappedUrl, 'kover://link?part=ref1');
      expect(
        EpubLinkTarget.parse(tappedUrl!),
        const EpubInternalLinkTarget(anchorId: 'ref1'),
      );
      expect(find.byType(EpubFootnoteBottomSheet), findsNothing);
    });
  });
}

PaginatedEpubPageSettings _pageSettings({
  bool highlightResumePoint = false,
}) {
  return PaginatedEpubPageSettings(
    horizontalMarginSize: 0,
    verticalMarginSize: 0,
    fontSize: 14,
    paragraphSpacing: 0,
    lineHeight: 1.5,
    wordSpacing: 0,
    letterSpacing: 0,
    fontFamily: null,
    removeParagraphIndent: false,
    highlightResumePoint: highlightResumePoint,
    canScroll: true,
    reduceAnimations: false,
    textAlignment: .left,
    mode: .horizontal,
  );
}

EpubPaginator _paginator(String html) {
  final root = EpubPagePreprocessor(
    html: dom.DocumentFragment.html(html),
    operations: [NodeIndexingOperation()],
  ).process();
  return EpubPaginator(root: root);
}

dom.DocumentFragment _processHtml(String html) {
  return EpubPagePreprocessor(
    html: dom.DocumentFragment.html(html),
    operations: [
      NodeIndexingOperation(),
      LinkNormalizationOperation(),
    ],
  ).process();
}

int _nodeIndexOf(dom.DocumentFragment root, String selector) =>
    _nodeIndex(root.querySelector(selector)!);

int _nodeIndex(dom.Element element) =>
    int.parse(element.attributes[HtmlConstants.nodeIndexAttribute]!);

EpubBreakUnit _line({
  required int nodeIndex,
  double top = 0,
  required double bottom,
  int offset = 0,
  List<int> childPath = const [],
  bool afterNode = false,
  bool isLeaf = false,
  double topInset = 0,
  double bottomInset = 0,
}) {
  final start = EpubBreak(
    blockNodeIndex: nodeIndex,
    childPath: childPath,
    offset: offset,
    afterNode: afterNode,
  );

  return isLeaf
      ? EpubLeafUnit(
          start: start,
          nodeIndex: nodeIndex,
          top: top,
          bottom: bottom,
          topInset: topInset,
          bottomInset: bottomInset,
        )
      : EpubLineUnit(
          start: start,
          nodeIndex: nodeIndex,
          top: top,
          bottom: bottom,
          topInset: topInset,
          bottomInset: bottomInset,
        );
}
