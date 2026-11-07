import 'dart:async';

import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:kover/mapping/enums/read_direction.dart';
import 'package:kover/pages/reader/epub_reader/epub_reader_provider.dart';
import 'package:kover/pages/reader/epub_reader/epub_theme_override.dart';
import 'package:kover/pages/reader/epub_reader/epub_toc_drawer.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/epub_footnote_bottom_sheet.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_controller_status.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/paginated_epub_page_settings.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page/preprocessing/link_normalization_operation.dart';
import 'package:kover/pages/reader/epub_reader/paginated_epub_page_provider.dart';
import 'package:kover/pages/reader/overlay/reader_overlay.dart';
import 'package:kover/riverpod/managers/font_manager.dart';
import 'package:kover/riverpod/providers/book.dart';
import 'package:kover/riverpod/providers/reader/epub_reader.dart';
import 'package:kover/riverpod/providers/settings/epub_reader_settings.dart';
import 'package:kover/utils/layout_constants.dart';
import 'package:kover/widgets/util/async_value.dart';
import 'package:material_ui/material_ui.dart';

class EpubReader extends HookConsumerWidget {
  final int seriesId;
  final int chapterId;
  final int? readingListId;

  const EpubReader({
    super.key,
    required this.seriesId,
    required this.chapterId,
    required this.readingListId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasSelection = useState(false);
    final nav = epubNavigationProvider(
      seriesId: seriesId,
      chapterId: chapterId,
      readingListId: readingListId,
    );

    final model = ref.watch(
      epubReaderProvider(seriesId: seriesId),
    );
    final ignoreSafeAreas = ref.watch(
      epubReaderSettingsProvider(
        seriesId: seriesId,
      ).select((state) => state.value?.ignoreSafeAreas ?? true),
    );

    return Async(
      asyncValue: model,
      data: (data) => ReaderOverlay(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
        disableGestures: hasSelection.value,
        onNextPage: () {
          ref.read(nav.notifier).nextPage();
        },
        onPreviousPage: () {
          ref.read(nav.notifier).previousPage();
        },
        onJumpToPage: (page) {
          ref.read(nav.notifier).jumpToPage(page);
        },
        endDrawer: EpubTocDrawer(
          seriesId: seriesId,
          chapterId: chapterId,
          readingListId: readingListId,
        ),
        child: EpubThemeOverride(
          seriesId: seriesId,
          child: Async(
            asyncValue: ref.watch(nav),
            data: (navState) => HookConsumer(
              builder: (context, ref, child) {
                final controller = usePageController(
                  initialPage: navState.page,
                );

                ref.listen(nav, (
                  previous,
                  next,
                ) async {
                  next.whenData((next) async {
                    final previousPage = previous?.value?.page;
                    final nextPage = next.page;

                    if (nextPage == previousPage) return;

                    hasSelection.value = false;

                    if (controller.hasClients &&
                        controller.page?.round() != nextPage) {
                      final isSequential =
                          previousPage != null &&
                          (nextPage - previousPage).abs() == 1;

                      isSequential && !data.reduceAnimations
                          ? controller.animateToPage(
                              nextPage,
                              duration: LayoutConstants.pageSlideDuration,
                              curve: Curves.easeInOut,
                            )
                          : controller.jumpToPage(nextPage);
                    }
                  });
                });

                final respectSafeAreas =
                    data.mode != .vertical || !ignoreSafeAreas;

                return Directionality(
                  textDirection: data.commonSettings.readDirection
                      .toTextDirection(),
                  child: SafeArea(
                    left: respectSafeAreas,
                    top: respectSafeAreas,
                    right: respectSafeAreas,
                    bottom: respectSafeAreas,
                    child: PageView.builder(
                      clipBehavior: respectSafeAreas ? .hardEdge : .none,
                      controller: controller,
                      itemCount: navState.totalPages,
                      allowImplicitScrolling: true,
                      scrollDirection: switch (data.mode) {
                        .horizontal => .horizontal,
                        .vertical => .vertical,
                        .spreads => .horizontal,
                      },
                      physics: const NeverScrollableScrollPhysics(),
                      onPageChanged: (newPage) {
                        ref.read(nav.notifier).jumpToPage(newPage, force: true);
                      },
                      itemBuilder: (context, index) {
                        return _Page(
                          seriesId: seriesId,
                          chapterId: chapterId,
                          readingListId: readingListId,
                          page: index,
                          reverse:
                              data.commonSettings.readDirection ==
                                  .rightToLeft &&
                              data.mode != .vertical,
                          outerController: controller,
                          onSelectionChanged: (selected) {
                            if (selected != hasSelection.value) {
                              hasSelection.value = selected;
                            }
                          },
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _Page extends HookConsumerWidget {
  final int seriesId;
  final int chapterId;
  final int? readingListId;
  final int page;
  final bool reverse;
  final PageController outerController;
  final void Function(bool)? onSelectionChanged;

  const new({
    required this.seriesId,
    required this.chapterId,
    required this.readingListId,
    required this.page,
    this.reverse = false,
    this.onSelectionChanged,
    required this.outerController,
  });

  bool handleScrollNotification(ScrollNotification notification) {
    if (!outerController.hasClients) return false;

    if (notification is OverscrollNotification) {
      outerController.jumpTo(
        (outerController.offset + notification.overscroll).clamp(
          0.0,
          outerController.position.maxScrollExtent,
        ),
      );
    }

    if (notification is ScrollEndNotification) {
      final rawVelocity = notification.dragDetails?.primaryVelocity ?? 0.0;

      // When reversed, physical velocity direction maps
      // to the opposite logical scroll direction.
      final dragVelocity = reverse ? -rawVelocity : rawVelocity;

      final position = outerController.position;
      final metrics = notification.metrics;

      final atBoundary =
          (dragVelocity > 0 && metrics.pixels <= metrics.minScrollExtent) ||
          (dragVelocity < 0 && metrics.pixels >= metrics.maxScrollExtent);

      if (position is ScrollPositionWithSingleContext && atBoundary) {
        position.goBallistic(-dragVelocity);
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = epubNavigationProvider(
      seriesId: seriesId,
      chapterId: chapterId,
      readingListId: readingListId,
    );
    final model = ref.watch(
      paginatedEpubPageProvider(
        seriesId: seriesId,
        chapterId: chapterId,
        readingListId: readingListId,
        page: page,
      ),
    );
    final controller = useMemoized(
      () => PaginatedEpubPageController(
        onSubpageChanged: (subpage, scrollId) {
          onSelectionChanged?.call(false);
          ref.read(nav.notifier).clearPendingAnchor();
          ref
              .read(nav.notifier)
              .jumpToSubpage(subpage, scrollId: scrollId, page: page);
        },
        onSubpagesCountChanged: (count) {
          ref.read(nav.notifier).updateSubpageCount(page, count);
        },
      ),
    );
    useEffect(() => controller.dispose, [controller]);

    final navState = ref.read(nav).value;
    if (navState != null && navState.page == page) {
      if (navState.pendingAnchorId != null) {
        if (controller.status == .ready) {
          final anchor = navState.pendingAnchorId!;
          ref.read(nav.notifier).clearPendingAnchor();
          controller.jumpToAnchor(anchor);
        } else {
          controller.setPendingAnchor(navState.pendingAnchorId);
        }
      } else if (controller.status == .measuring) {
        controller.setPendingSubpage(navState.subpage);
      }
    }

    ref.listen(
      nav,
      (previous, next) {
        next.whenData((next) {
          if (next.page != page) {
            controller.setPendingSubpage(null);
            controller.setPendingAnchor(null);
            return;
          }

          if (next.pendingAnchorId != null) {
            final anchor = next.pendingAnchorId!;
            if (controller.status == .ready) {
              ref.read(nav.notifier).clearPendingAnchor();
              controller.jumpToAnchor(anchor);
            } else {
              controller.setPendingAnchor(anchor);
            }
            return;
          }

          if (controller.status == .ready) {
            ref
                .read(nav.notifier)
                .updateSubpageCount(page, controller.subpageCount);
            if (controller.currentSubpage != next.subpage) {
              controller.jumpToSubpage(next.subpage);
            }
          } else {
            controller.setPendingSubpage(next.subpage);
          }
        });
      },
    );

    return Async(
      asyncValue: model,
      data: (data) => NotificationListener<ScrollNotification>(
        onNotification: data.settings.canScroll
            ? handleScrollNotification
            : null,
        child: PaginatedEpubPage(
          controller: controller,
          html: data.html,
          settings: data.settings,
          rootStyles: data.rootStyles,
          highlightStyles: data.highlightStyles,
          resumeScrollId: data.resumeScrollId,
          onSelectionChanged: onSelectionChanged,
          onTapUrl: (url) {
            final target = EpubLinkTarget.parse(url);
            if (target == null) return true;
            switch (target) {
              case EpubFootnoteLinkTarget(
                ref: final noteRef,
                page: final targetPage,
              ):
                unawaited(
                  _openFootnoteOrJump(
                    context,
                    ref,
                    controller: controller,
                    settings: data.settings,
                    noteRef: noteRef,
                    targetPage: targetPage,
                  ),
                );
                return true;
              case EpubInternalLinkTarget(
                page: final targetPage,
                :final anchorId,
              ):
                if (targetPage == 0 &&
                    page != 0 &&
                    anchorId != null &&
                    controller.jumpToAnchor(anchorId)) {
                  return true;
                }
                ref
                    .read(nav.notifier)
                    .jumpToLink(page: targetPage, anchorId: anchorId);
                return true;
              case EpubExternalLinkTarget():
                return false;
            }
          },
        ),
      ),
    );
  }

  Future<void> _openFootnoteOrJump(
    BuildContext context,
    WidgetRef ref, {
    required PaginatedEpubPageController controller,
    required PaginatedEpubPageSettings settings,
    required String noteRef,
    required int? targetPage,
  }) async {
    final nav = epubNavigationProvider(
      seriesId: seriesId,
      chapterId: chapterId,
      readingListId: readingListId,
    );
    final navNotifier = ref.read(nav.notifier);

    String? footnoteHtml;
    var footnoteCssEngine = controller.cssEngine;

    if (targetPage == null || targetPage == page || targetPage == 0) {
      footnoteHtml = controller.extractFootnoteHtml(noteRef);
    }

    if (footnoteHtml == null && targetPage != null && targetPage != page) {
      try {
        final fontManager = ref.read(fontManagerProvider.notifier);
        final remotePage = await ref.read(
          epubPageProvider(chapterId: chapterId, page: targetPage).future,
        );
        await fontManager.ensureLoaded(remotePage.fonts);
        if (!context.mounted) return;
        final extracted = controller.extractRemoteFootnote(
          remotePage.root,
          noteRef,
        );
        if (extracted != null) {
          footnoteHtml = extracted.html;
          footnoteCssEngine = extracted.cssEngine;
        }
      } on Exception {
        if (!context.mounted) return;
      }
    }

    footnoteHtml ??= controller.extractFootnoteHtml(noteRef);

    if (footnoteHtml != null) {
      if (!context.mounted) return;
      await showEpubFootnoteBottomSheet(
        context,
        html: footnoteHtml,
        settings: settings,
        cssEngine: footnoteCssEngine,
        onTapUrl: (sheetUrl) {
          final sheetTarget = EpubLinkTarget.parse(sheetUrl);
          if (sheetTarget == null) return true;
          switch (sheetTarget) {
            case EpubFootnoteLinkTarget(
              ref: final innerRef,
              page: final innerPage,
            ):
              Navigator.of(context).pop();
              unawaited(
                _openFootnoteOrJump(
                  context,
                  ref,
                  controller: controller,
                  settings: settings,
                  noteRef: innerRef,
                  targetPage: innerPage ?? targetPage,
                ),
              );
              return true;
            case EpubInternalLinkTarget(
              page: final innerPage,
              anchorId: final innerAnchorId,
            ):
              Navigator.of(context).pop();
              if (innerPage == null || innerPage == page) {
                if (innerAnchorId == null) return true;
                final targetSubpage = controller.subpageForAnchor(
                  innerAnchorId,
                );
                if (targetSubpage == null ||
                    targetSubpage == controller.currentSubpage) {
                  return true;
                }
              }
              unawaited(
                navNotifier.jumpToLink(
                  page: innerPage,
                  anchorId: innerAnchorId,
                ),
              );
              return true;
            case EpubExternalLinkTarget():
              return false;
          }
        },
      );
      return;
    }

    await navNotifier.jumpToLink(page: targetPage, anchorId: noteRef);
  }
}
