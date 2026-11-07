import 'package:html/dom.dart' as dom;
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/css_engine.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_paginator.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/measure/epub_measurements_collector.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/epub_page_preprocessor.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/link_normalization_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/node_indexing_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/resume_highlight_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/scroll_id_operation.dart';
import 'package:kover/utils/html_constants.dart';
import 'package:material_ui/material_ui.dart';

enum PaginatedEpubPageControllerStatus { measuring, ready }

/// Controls the state of a [PaginatedEpubPage].
class PaginatedEpubPageController({
  final void Function(int subpage, String? scrollId)? onSubpageChanged,
  final void Function(int)? onSubpagesCountChanged,
}) extends ChangeNotifier {
  EpubPaginator? _paginator;
  CssEngine? _cssEngine;
  PaginatedEpubPageControllerStatus _status = .measuring;
  int _currentSubpage = 0;
  Size? _contentViewport;
  String? _initialXpath;
  dom.Element? _highlightedElement;
  bool _resumePending = false;
  int? _pendingSubpage;
  String? _pendingAnchorId;
  PaginatedEpubPageSettings? _settings;
  Map<String, Map<String, String>> _additionalStyles = const {};

  PaginatedEpubPageControllerStatus get status => _status;
  dom.DocumentFragment? get root => _paginator?.root;
  Size? get contentViewport => _contentViewport;
  String? get initialXpath => _initialXpath;

  int get currentSubpage => _currentSubpage;
  int get subpageCount => _paginator?.subpageCount ?? 0;
  CssEngine get cssEngine =>
      _cssEngine ?? (throw Exception('CSS engine is not initialized'));

  void nextSubpage() {
    jumpToSubpage(_currentSubpage + 1);
  }

  void previousSubpage() {
    jumpToSubpage(_currentSubpage - 1);
  }

  void jumpToSubpage(int index) {
    final paginator = _paginator;
    if (paginator == null || index < 0 || index >= paginator.subpageCount) {
      return;
    }

    if (index == _currentSubpage) return;

    _currentSubpage = index;
    onSubpageChanged?.call(
      _currentSubpage,
      scrollIdForSubpage(_currentSubpage),
    );
    notifyListeners();
  }

  void attachRoot(
    dom.DocumentFragment html, {
    required PaginatedEpubPageSettings settings,
    String? initialXpath,
    Map<String, Map<String, String>> additionalStyles = const {},
  }) {
    final root = EpubPagePreprocessor(
      html: html,
      operations: [
        NodeIndexingOperation(),
        ScrollIdOperation(),
        ResumeHighlightOperation(
          scrollId: settings.highlightResumePoint ? initialXpath : null,
        ),
        LinkNormalizationOperation(),
      ],
    ).process();

    _paginator = EpubPaginator(root: root);
    _cssEngine = CssEngine(
      root: root,
      additionalStyles: additionalStyles,
    );
    _additionalStyles = additionalStyles;
    _settings = settings;
    _initialXpath = initialXpath;
    _highlightedElement = settings.highlightResumePoint
        ? _findByScrollId(root, initialXpath)
        : null;
    _resumePending = initialXpath != null;
    _currentSubpage = 0;
    _contentViewport = null;
    _status = .measuring;
    notifyListeners();
  }

  void updateStyles(Map<String, Map<String, String>> additionalStyles) {
    _additionalStyles = additionalStyles;
    _cssEngine?.updateAdditionalStyles(additionalStyles);
    notifyListeners();
  }

  void updateSettings(PaginatedEpubPageSettings settings) {
    final wasHighlighting = _settings?.highlightResumePoint ?? false;
    _settings = settings;

    if (wasHighlighting == settings.highlightResumePoint) return;

    if (settings.highlightResumePoint) {
      final root = _paginator?.root;
      _highlightedElement ??= root == null
          ? null
          : _findByScrollId(root, _initialXpath);
      _highlightedElement?.classes.add(HtmlConstants.resumeClass);
    } else {
      _highlightedElement?.classes.remove(HtmlConstants.resumeClass);
    }

    _cssEngine?.updateAdditionalStyles(_additionalStyles);
    notifyListeners();
  }

  /// Sets the subpage to use as soon as pagination completes.
  ///
  /// Used while a page is still measuring and the caller already knows which
  /// subpage should become visible (for example when navigating back to the
  /// last subpage of the previous page).
  void setPendingSubpage(int? subpage) {
    _pendingSubpage = subpage;
  }

  /// Sets the anchor to jump to as soon as pagination completes.
  void setPendingAnchor(String? anchorId) {
    _pendingAnchorId = anchorId;
  }

  /// Returns the subpage containing [anchorId] when pagination is ready.
  int? subpageForAnchor(String anchorId) {
    final paginator = _paginator;
    if (paginator == null || _status != .ready) return null;
    return paginator.subpageForAnchor(anchorId);
  }

  /// Jumps to the subpage containing [anchorId], or defers until pagination completes.
  bool jumpToAnchor(String anchorId) {
    final paginator = _paginator;
    if (paginator == null || _status != .ready) {
      _pendingAnchorId = anchorId;
      return false;
    }

    final subpage = paginator.subpageForAnchor(anchorId);
    if (subpage == null) return false;

    jumpToSubpage(subpage);
    return true;
  }

  /// Extracts the HTML markup for the footnote referenced by [rawRef].
  String? extractFootnoteHtml(String rawRef) {
    final cleanId = rawRef.startsWith('#') ? rawRef.substring(1) : rawRef;
    if (cleanId.isEmpty) return null;

    final paginator = _paginator;
    if (paginator == null) return null;

    return _extractFootnoteFromRoot(paginator.root, cleanId);
  }

  /// Preprocesses [remoteHtml] and extracts the footnote referenced by [rawRef]
  /// along with a [CssEngine] built against [remoteHtml]'s stylesheets.
  ({String html, CssEngine cssEngine})? extractRemoteFootnote(
    dom.DocumentFragment remoteHtml,
    String rawRef,
  ) {
    final cleanId = rawRef.startsWith('#') ? rawRef.substring(1) : rawRef;
    if (cleanId.isEmpty) return null;

    final root = EpubPagePreprocessor(
      html: remoteHtml,
      operations: [
        NodeIndexingOperation(),
        LinkNormalizationOperation(),
      ],
    ).process();

    final footnoteHtml = _extractFootnoteFromRoot(root, cleanId);
    if (footnoteHtml == null) return null;

    return (
      html: footnoteHtml,
      cssEngine: CssEngine(
        root: root,
        additionalStyles: _additionalStyles,
      ),
    );
  }

  static String? _extractFootnoteFromRoot(
    dom.DocumentFragment root,
    String cleanId,
  ) {
    final target = _findFootnoteTarget(root, cleanId);
    if (target == null) return null;

    var source = target;
    const inlineTags = {'a', 'span', 'sup', 'sub'};
    const tightBlockTags = {'p', 'li', 'dd', 'dt', 'tr', 'aside', 'blockquote'};
    const containerBlockTags = {'div', 'article', 'section'};
    const singleNoteClasses = {
      'footnote',
      '_idfootnote',
      'endnote',
      '_idendnote',
      'rearnote',
      'note',
    };

    final targetTag = target.localName?.toLowerCase();
    if (targetTag != null && inlineTags.contains(targetTag)) {
      dom.Element? current = target.parent is dom.Element
          ? target.parent as dom.Element
          : null;
      while (current != null) {
        final currentTag = current.localName?.toLowerCase();
        if (currentTag != null && tightBlockTags.contains(currentTag)) {
          final parent = current.parent;
          if (currentTag == 'p' &&
              parent is dom.Element &&
              containerBlockTags.contains(parent.localName?.toLowerCase()) &&
              parent.classes.any(
                (cls) => singleNoteClasses.contains(cls.toLowerCase()),
              )) {
            source = parent;
          } else {
            source = current;
          }
          break;
        }
        if (currentTag != null && containerBlockTags.contains(currentTag)) {
          if (target.text.trim().isEmpty && target.nextElementSibling != null) {
            source = target.nextElementSibling!;
          } else {
            source = current;
          }
          break;
        }
        current = current.parent is dom.Element
            ? current.parent as dom.Element
            : null;
      }
      if (identical(source, target) &&
          target.text.trim().isEmpty &&
          target.nextElementSibling != null) {
        source = target.nextElementSibling!;
      }
    }

    final cloned = source.clone(true);
    _stripFootnoteAttributes(cloned);

    if (cloned.text.trim().isEmpty) return null;

    final buffer = StringBuffer(cloned.outerHtml);
    final sourceTag = source.localName?.toLowerCase();
    if (sourceTag == 'dt' &&
        source.nextElementSibling?.localName?.toLowerCase() == 'dd') {
      final clonedDd = source.nextElementSibling!.clone(true);
      _stripFootnoteAttributes(clonedDd);
      if (clonedDd.text.trim().isNotEmpty) {
        buffer.write(clonedDd.outerHtml);
      }
    } else if (sourceTag == 'p' && source.classes.contains('fn')) {
      dom.Element? sibling = source.nextElementSibling;
      while (sibling != null &&
          sibling.localName?.toLowerCase() == 'p' &&
          sibling.classes.contains('fn1')) {
        final clonedSibling = sibling.clone(true);
        _stripFootnoteAttributes(clonedSibling);
        if (clonedSibling.text.trim().isNotEmpty) {
          buffer.write(clonedSibling.outerHtml);
        }
        sibling = sibling.nextElementSibling;
      }
    }

    return '<div class="${HtmlConstants.kavitaWrapperClass} ${HtmlConstants.koverWrapperClass}">$buffer</div>';
  }

  static dom.Element? _findFootnoteTarget(
    dom.DocumentFragment root,
    String cleanId,
  ) {
    for (final element in root.querySelectorAll('[id], [name]')) {
      if (element.id == cleanId || element.attributes['name'] == cleanId) {
        return element;
      }
    }
    return null;
  }

  static void _stripFootnoteAttributes(dom.Element element) {
    _cleanFootnoteElement(element);
    for (final descendant in element.querySelectorAll('*')) {
      if (descendant.localName?.toLowerCase() == 'hr') {
        descendant.remove();
        continue;
      }
      _cleanFootnoteElement(descendant);
    }
  }

  static void _cleanFootnoteElement(dom.Element element) {
    final wasHidden =
        element.attributes.containsKey('hidden') ||
        element.classes.contains('hidden') ||
        element.classes.contains(HtmlConstants.visuallyHiddenClass);
    element.attributes
      ..remove('id')
      ..remove('hidden');
    if (wasHidden) {
      element.attributes.remove(HtmlConstants.nodeIndexAttribute);
    }
    element.classes
      ..remove(HtmlConstants.visuallyHiddenClass)
      ..remove('hidden');
    if (element.classes.isEmpty) {
      element.attributes.remove('class');
    }
  }

  void remeasure() {
    if (_status == .measuring) return;

    _status = .measuring;
    notifyListeners();
  }

  void processMeasurements(
    EpubMeasurements measurements, {
    required Size viewport,
  }) {
    final paginator = _paginator;
    if (paginator == null) return;

    paginator.paginate(measurements.units, viewport.height);
    _contentViewport = viewport;
    _status = .ready;

    final count = paginator.subpageCount;
    onSubpagesCountChanged?.call(count);

    final pendingAnchor = _pendingAnchorId;
    final pendingSubpage = _pendingSubpage;
    _pendingSubpage = null;
    final target = (_resumePending || pendingAnchor != null)
        ? _resumeSubpage() ?? pendingSubpage ?? _currentSubpage
        : pendingSubpage ?? _currentSubpage;
    _resumePending = false;
    _currentSubpage = count == 0 ? 0 : target.clamp(0, count - 1);

    onSubpageChanged?.call(
      _currentSubpage,
      scrollIdForSubpage(_currentSubpage),
    );
    notifyListeners();
  }

  void viewportChanged(Size viewport) {
    if (_contentViewport == viewport) return;

    _contentViewport = viewport;
    if (_status == .measuring) return;

    _status = .measuring;
    notifyListeners();
  }

  String getSubpage(int index) {
    if (_paginator == null) throw Exception('Paginator is not initialized');
    return _paginator!.getSubpage(index);
  }

  String? scrollIdForSubpage(int index) {
    return _paginator?.scrollIdForSubpage(index);
  }

  int? _resumeSubpage() {
    final paginator = _paginator;
    if (paginator == null) return null;

    final pendingAnchor = _pendingAnchorId;
    if (pendingAnchor != null) {
      _pendingAnchorId = null;
      final subpage = paginator.subpageForAnchor(pendingAnchor);
      if (subpage != null) return subpage;
    }

    final xpath = _initialXpath;
    if (xpath == null) return null;

    final element = _findByScrollId(paginator.root, xpath);
    if (element != null) {
      dom.Element? current = element;
      while (current != null) {
        final index = int.tryParse(
          current.attributes[HtmlConstants.nodeIndexAttribute] ?? '',
        );
        if (index != null) {
          final subpage = paginator.subpageForNodeIndex(index);
          if (subpage != null) return subpage;
        }

        final parent = current.parent;
        current = parent is dom.Element ? parent : null;
      }
    }

    return paginator.subpageForScrollId(xpath);
  }

  static dom.Element? _findByScrollId(
    dom.DocumentFragment root,
    String? scrollId,
  ) {
    if (scrollId == null) return null;

    final elements = root.querySelectorAll(
      '[${HtmlConstants.scrollIdAttribute}]',
    );
    for (final element in elements) {
      if (element.attributes[HtmlConstants.scrollIdAttribute] == scrollId) {
        return element;
      }
    }

    return null;
  }
}
