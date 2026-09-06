import 'dart:math' as math;

import 'package:flutter/painting.dart';

class NovelCanvasPageConfig {
  NovelCanvasPageConfig({
    required this.pageIndex,
    required this.startOffset,
    required this.endOffset,
    required this.paragraphContents,
  });

  final int pageIndex;
  final int startOffset;
  final int endOffset;
  final List<String> paragraphContents;

  bool get hasContents => paragraphContents.isNotEmpty;
}

/// Compact catalog jump target (chapter or sparse progress).
class NovelTocEntry {
  const NovelTocEntry({
    required this.title,
    required this.startOffset,
    this.progressLabel,
  });

  final String title;
  final int startOffset;
  final String? progressLabel;
}

/// Layout metrics used by canvas pagination.
class NovelPageLayoutMetrics {
  const NovelPageLayoutMetrics({
    required this.height,
    required this.width,
    required this.fontSize,
    required this.lineHeight,
    required this.paragraphSpacing,
  });

  final double height;
  final double width;
  final int fontSize;
  final int lineHeight;
  final int paragraphSpacing;
}

class _ParagraphChunk {
  _ParagraphChunk({
    required this.text,
    required this.startOffset,
  });

  String text;
  int startOffset;
}

/// Incremental paginator used by the canvas reader.
class NovelIncrementalPaginator {
  NovelIncrementalPaginator({
    required String text,
    required NovelPageLayoutMetrics layout,
    int pageIndex = 0,
    int startOffset = 0,
  })  : height = layout.height,
        width = layout.width,
        fontSize = layout.fontSize,
        lineHeight = layout.lineHeight,
        paragraphSpacing = layout.paragraphSpacing,
        _painter = TextPainter(textDirection: TextDirection.ltr),
        _pageIndex = pageIndex {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    var cursor = 0;
    for (final paragraph in normalized.split('\n')) {
      _chunks.add(_ParagraphChunk(text: paragraph, startOffset: cursor));
      cursor += paragraph.length + 1;
    }
    _consumeUntil(startOffset.clamp(0, math.max(0, normalized.length)));
  }

  final double height;
  final double width;
  final int fontSize;
  final int lineHeight;
  final int paragraphSpacing;
  final TextPainter _painter;
  final List<_ParagraphChunk> _chunks = <_ParagraphChunk>[];
  int _pageIndex;

  bool get isComplete => _chunks.isEmpty;

  void _consumeUntil(int startOffset) {
    if (startOffset <= 0 || _chunks.isEmpty) return;
    while (_chunks.isNotEmpty) {
      final chunk = _chunks.first;
      final chunkEnd = chunk.startOffset + chunk.text.length;
      if (chunkEnd < startOffset) {
        _chunks.removeAt(0);
        continue;
      }
      if (chunk.startOffset < startOffset) {
        final cut = startOffset - chunk.startOffset;
        if (cut >= chunk.text.length) {
          _chunks.removeAt(0);
        } else {
          chunk.text = chunk.text.substring(cut);
          chunk.startOffset = startOffset;
        }
      }
      break;
    }
  }

  NovelCanvasPageConfig? nextPage({bool includeContents = true}) {
    if (_chunks.isEmpty) return null;

    final pageParagraphs = <String>[];
    int? pageStartOffset;
    var pageEndOffset = 0;
    var currentHeight = 0.0;

    while (currentHeight < height && _chunks.isNotEmpty) {
      if (currentHeight + lineHeight >= height) {
        break;
      }

      final currentChunk = _chunks.first;
      pageStartOffset ??= currentChunk.startOffset;

      if (currentChunk.text.isEmpty) {
        if (includeContents) pageParagraphs.add('');
        pageEndOffset = currentChunk.startOffset;
        _chunks.removeAt(0);
        currentHeight += lineHeight + paragraphSpacing;
        continue;
      }

      _painter.text = TextSpan(
        text: currentChunk.text,
        style: TextStyle(
          fontSize: fontSize.toDouble(),
          height: lineHeight / fontSize,
        ),
      );
      _painter.layout(maxWidth: width);

      var endOffset = _painter
          .getPositionForOffset(
            Offset(width, height - currentHeight - lineHeight),
          )
          .offset;
      if (endOffset <= 0) {
        endOffset = math.min(currentChunk.text.length, 1);
      }

      var pageText = currentChunk.text;
      final lineMetrics = _painter.computeLineMetrics();
      if (endOffset < currentChunk.text.length) {
        pageText = currentChunk.text.substring(0, endOffset);
        currentChunk.text = currentChunk.text.substring(endOffset);
        pageEndOffset = currentChunk.startOffset + endOffset;
        currentChunk.startOffset = pageEndOffset;
        currentHeight = height;
      } else {
        _chunks.removeAt(0);
        pageEndOffset = currentChunk.startOffset + pageText.length;
        currentHeight += lineHeight * lineMetrics.length;
        currentHeight += paragraphSpacing;
      }

      if (includeContents) pageParagraphs.add(pageText);
    }

    if (pageStartOffset == null) return null;
    if (includeContents && pageParagraphs.isEmpty) return null;

    final page = NovelCanvasPageConfig(
      pageIndex: _pageIndex,
      startOffset: pageStartOffset,
      endOffset: pageEndOffset,
      paragraphContents: includeContents ? pageParagraphs : const <String>[],
    );
    _pageIndex += 1;
    return page;
  }
}

NovelCanvasPageConfig skeletonPage(NovelCanvasPageConfig page) {
  if (page.paragraphContents.isEmpty) return page;
  return NovelCanvasPageConfig(
    pageIndex: page.pageIndex,
    startOffset: page.startOffset,
    endOffset: page.endOffset,
    paragraphContents: const <String>[],
  );
}

/// Keep full paragraph bodies only near [currentIndex].
void stripPageContentsOutsideWindow({
  required List<NovelCanvasPageConfig> pages,
  required int currentIndex,
  required int radius,
}) {
  if (pages.isEmpty) return;
  final start = math.max(0, currentIndex - radius);
  final end = math.min(pages.length - 1, currentIndex + radius);
  for (var i = 0; i < pages.length; i += 1) {
    if (i >= start && i <= end) continue;
    final page = pages[i];
    if (page.paragraphContents.isEmpty) continue;
    pages[i] = skeletonPage(page);
  }
}

/// Re-paginate a single page body from [startOffset].
NovelCanvasPageConfig hydratePageAtOffset({
  required String text,
  required NovelPageLayoutMetrics layout,
  required int pageIndex,
  required int startOffset,
}) {
  final session = NovelIncrementalPaginator(
    text: text,
    layout: layout,
    pageIndex: pageIndex,
    startOffset: startOffset,
  );
  final page = session.nextPage(includeContents: true);
  if (page == null) {
    return NovelCanvasPageConfig(
      pageIndex: pageIndex,
      startOffset: startOffset,
      endOffset: startOffset,
      paragraphContents: const <String>[],
    );
  }
  return page;
}

final RegExp _chapterLinePattern = RegExp(
  r'^[\s\u3000]*('
  r'第[\d一二三四五六七八九十百千万两零〇]+[章节回部卷][^\n]{0,40}'
  r'|Chapter\s+\d+[^\n]{0,40}'
  r'|CHAPTER\s+\d+[^\n]{0,40}'
  r')\s*$',
  multiLine: true,
);

/// Prefer real chapter headings; fall back to sparse percent jumps.
List<NovelTocEntry> buildNovelToc(String text, {int sparseSteps = 10}) {
  final chapters = <NovelTocEntry>[];
  for (final match in _chapterLinePattern.allMatches(text)) {
    final title = match.group(0)?.trim();
    if (title == null || title.isEmpty) continue;
    chapters.add(NovelTocEntry(title: title, startOffset: match.start));
    if (chapters.length >= 400) break;
  }
  if (chapters.length >= 2) return chapters;

  final length = text.length;
  if (length <= 0) return const [];
  final steps = math.max(2, sparseSteps);
  final sparse = <NovelTocEntry>[];
  for (var i = 0; i <= steps; i += 1) {
    final ratio = i / steps;
    final offset = i == steps ? math.max(0, length - 1) : (length * ratio).floor();
    final percent = (ratio * 100).round();
    sparse.add(
      NovelTocEntry(
        title: i == 0 ? 'Beginning' : (i == steps ? 'Ending' : '$percent%'),
        startOffset: offset,
        progressLabel: '$percent%',
      ),
    );
  }
  return sparse;
}
