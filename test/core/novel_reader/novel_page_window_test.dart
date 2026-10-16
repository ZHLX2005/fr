import 'package:flutter_test/flutter_test.dart';

import 'package:xiaodouzi_fr/core/novel_reader/novel_page_window.dart';

void main() {
  group('buildNovelToc', () {
    test('extracts chinese chapter headings', () {
      const text = '''
前言

第一章 开端
正文一段。

第二章 发展
更多正文。
''';
      final toc = buildNovelToc(text);
      expect(toc.length, greaterThanOrEqualTo(2));
      expect(toc.first.title, contains('第一章'));
      expect(toc[1].title, contains('第二章'));
    });

    test('falls back to sparse progress jumps', () {
      final text = 'hello world without chapters ' * 20;
      final toc = buildNovelToc(text, sparseSteps: 5);
      expect(toc, hasLength(6));
      expect(toc.first.title, 'Beginning');
      expect(toc.last.title, 'Ending');
      expect(toc[1].progressLabel, '20%');
    });
  });

  group('NovelIncrementalPaginator', () {
    test('paginates and hydrates from offset', () {
      final layout = const NovelPageLayoutMetrics(
        height: 400,
        width: 300,
        fontSize: 18,
        lineHeight: 31,
        paragraphSpacing: 8,
      );
      final text = List.generate(40, (i) => 'Paragraph $i with some words.').join('\n');
      final session = NovelIncrementalPaginator(text: text, layout: layout);
      final pages = <NovelCanvasPageConfig>[];
      while (true) {
        final page = session.nextPage(includeContents: false);
        if (page == null) break;
        pages.add(page);
      }
      expect(pages, isNotEmpty);
      expect(pages.every((p) => !p.hasContents), isTrue);

      final hydrated = hydratePageAtOffset(
        text: text,
        layout: layout,
        pageIndex: pages.first.pageIndex,
        startOffset: pages.first.startOffset,
      );
      expect(hydrated.hasContents, isTrue);
      expect(hydrated.startOffset, pages.first.startOffset);
    });
  });

  test('stripPageContentsOutsideWindow keeps near pages', () {
    final pages = List.generate(
      10,
      (i) => NovelCanvasPageConfig(
        pageIndex: i,
        startOffset: i * 10,
        endOffset: i * 10 + 9,
        paragraphContents: <String>['p$i'],
      ),
    );
    stripPageContentsOutsideWindow(
      pages: pages,
      currentIndex: 5,
      radius: 1,
    );
    expect(pages[4].hasContents, isTrue);
    expect(pages[5].hasContents, isTrue);
    expect(pages[6].hasContents, isTrue);
    expect(pages[0].hasContents, isFalse);
    expect(pages[9].hasContents, isFalse);
  });
}
