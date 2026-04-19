import 'dart:math' as math;

import 'package:flutter/material.dart';

class NovelPage {
  const NovelPage({required this.start, required this.end, required this.text});

  final int start;
  final int end;
  final String text;
}

class PaginationLayout {
  const PaginationLayout({
    required this.size,
    required this.padding,
    required this.fontSize,
    required this.lineHeight,
  });

  final Size size;
  final EdgeInsets padding;
  final double fontSize;
  final double lineHeight;

  double get contentWidth => math.max(1, size.width - padding.horizontal);
  double get contentHeight => math.max(1, size.height - padding.vertical);

  bool isCloseTo(PaginationLayout other) {
    return (size.width - other.size.width).abs() < 0.5 &&
        (size.height - other.size.height).abs() < 0.5 &&
        (fontSize - other.fontSize).abs() < 0.01 &&
        (lineHeight - other.lineHeight).abs() < 0.01 &&
        padding == other.padding;
  }
}

class NovelPaginator {
  const NovelPaginator();

  Future<NovelPage> pageAtOffset({
    required String text,
    required PaginationLayout layout,
    required TextStyle textStyle,
    required int startOffset,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return const NovelPage(start: 0, end: 0, text: '');
    }

    final start = startOffset.clamp(0, normalized.length - 1);
    final painter = _createPainter(layout);
    final end = _findPageEnd(
      source: normalized,
      start: start,
      painter: painter,
      layout: layout,
      style: textStyle,
    );
    return NovelPage(
      start: start,
      end: end,
      text: normalized.substring(start, end),
    );
  }

  Future<NovelPage?> nextPage({
    required String text,
    required PaginationLayout layout,
    required TextStyle textStyle,
    required NovelPage currentPage,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || currentPage.end >= normalized.length) {
      return null;
    }
    return pageAtOffset(
      text: normalized,
      layout: layout,
      textStyle: textStyle,
      startOffset: currentPage.end,
    );
  }

  Future<NovelPage?> previousPage({
    required String text,
    required PaginationLayout layout,
    required TextStyle textStyle,
    required NovelPage currentPage,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || currentPage.start <= 0) {
      return null;
    }

    final painter = _createPainter(layout);
    final start = _findPreviousPageStart(
      source: normalized,
      end: currentPage.start,
      painter: painter,
      layout: layout,
      style: textStyle,
    );
    return NovelPage(
      start: start,
      end: currentPage.start,
      text: normalized.substring(start, currentPage.start),
    );
  }

  TextPainter _createPainter(PaginationLayout layout) {
    return TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.start,
      maxLines: null,
      strutStyle: StrutStyle(
        fontSize: layout.fontSize,
        height: layout.lineHeight / layout.fontSize,
        forceStrutHeight: true,
      ),
    );
  }

  int _findPageEnd({
    required String source,
    required int start,
    required TextPainter painter,
    required PaginationLayout layout,
    required TextStyle style,
  }) {
    var low = start + 1;
    var high = source.length;
    var best = low;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = _trimPageCandidate(source.substring(start, mid));
      painter.text = TextSpan(text: candidate, style: style);
      painter.layout(maxWidth: layout.contentWidth);
      final fits = painter.height <= layout.contentHeight;
      if (fits) {
        best = math.max(best, start + candidate.length);
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }

    if (best <= start) {
      return math.min(source.length, start + 1);
    }

    final adjusted = _preferNaturalBreak(source, start, best);
    return adjusted > start ? adjusted : best;
  }

  int _findPreviousPageStart({
    required String source,
    required int end,
    required TextPainter painter,
    required PaginationLayout layout,
    required TextStyle style,
  }) {
    var low = 0;
    var high = end - 1;
    var best = high;

    while (low <= high) {
      final mid = (low + high) >> 1;
      final candidate = source.substring(mid, end);
      painter.text = TextSpan(text: candidate, style: style);
      painter.layout(maxWidth: layout.contentWidth);
      final fits = painter.height <= layout.contentHeight;
      if (fits) {
        best = mid;
        high = mid - 1;
      } else {
        low = mid + 1;
      }
    }

    if (best >= end) {
      return math.max(0, end - 1);
    }
    return _preferNaturalStart(source, best, end);
  }

  String _trimPageCandidate(String input) {
    return input.replaceFirst(RegExp(r'^\n+'), '');
  }

  int _preferNaturalBreak(String source, int start, int end) {
    final lookbackFloor = math.max(start, end - 120);
    for (var i = end - 1; i >= lookbackFloor; i--) {
      final char = source[i];
      if (char == '\n') {
        final next = i + 1;
        if (next > start + 24) {
          return next;
        }
      }
      if (_isSentenceBoundary(char) && i + 1 > start + 40) {
        return i + 1;
      }
    }
    return end;
  }

  int _preferNaturalStart(String source, int start, int end) {
    final lookaheadCeil = math.min(end - 1, start + 120);
    for (var i = start; i <= lookaheadCeil; i++) {
      final char = source[i];
      if (char == '\n') {
        final next = i + 1;
        if (end - next > 24) {
          return next;
        }
      }
    }
    return start;
  }

  bool _isSentenceBoundary(String char) {
    return char == '.' ||
        char == '!' ||
        char == '?' ||
        char == ';' ||
        char == ':';
  }
}
