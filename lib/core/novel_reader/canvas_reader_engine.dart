import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'novel_page_window.dart';

export 'novel_page_window.dart'
    show NovelCanvasPageConfig, NovelTocEntry, buildNovelToc;

class NovelCanvasPageData {
  NovelCanvasPageData({
    required this.pageIndex,
    this.picture,
    this.image,
  });

  final int pageIndex;
  final ui.Picture? picture;
  final ui.Image? image;

  NovelCanvasPageData copyWith({
    ui.Picture? picture,
    ui.Image? image,
  }) {
    return NovelCanvasPageData(
      pageIndex: pageIndex,
      picture: picture ?? this.picture,
      image: image ?? this.image,
    );
  }

  void dispose() {
    image?.dispose();
    picture?.dispose();
  }
}

typedef NovelCanvasProgressChanged = Future<void> Function(
  int pageIndex,
  int pageStartOffset,
);

class NovelCanvasReaderController extends ChangeNotifier {
  NovelCanvasReaderController({
    required this.title,
    this.onProgressChanged,
  });

  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(24, 28, 24, 28);
  static const int _defaultFontSize = 18;
  static const int _defaultLineHeight = 31;
  static const int _paragraphSpacing = 8;
  static const int _titleHeight = 28;
  static const int _titleFontSize = 20;
  static const int _bottomTipHeight = 22;
  static const int _bottomTipFontSize = 14;

  /// Pages within this radius of current are rasterized and kept in cache.
  static const int _rasterWindowRadius = 3;

  /// Prefer immediate raster for current ± this radius (page-curl neighbors).
  static const int _rasterPriorityRadius = 1;

  /// Keep paragraph bodies only near the reading position.
  static const int _contentWindowRadius = 12;

  /// Mark UI ready once current + this many following pages exist.
  static const int _readyAheadPages = 2;

  final String title;
  final NovelCanvasProgressChanged? onProgressChanged;

  late final Paint bgPaint;
  ColorScheme? _colorScheme;

  final ListQueue<int> _microParseQueue = ListQueue<int>();
  final ListQueue<int> _parseQueue = ListQueue<int>();
  final Map<int, NovelCanvasPageData> _pageDataMap = <int, NovelCanvasPageData>{};

  final TextPainter _titlePainter = TextPainter(textDirection: TextDirection.ltr);
  final TextPainter _contentPainter = TextPainter(textDirection: TextDirection.ltr);
  final TextPainter _footerPainter = TextPainter(textDirection: TextDirection.ltr);

  String? _bookText;
  List<NovelCanvasPageConfig> _pageConfigs = <NovelCanvasPageConfig>[];
  List<NovelTocEntry> _tocEntries = const <NovelTocEntry>[];
  Size _pageSize = Size.zero;
  int _currentPageIndex = 0;
  int _fontSize = _defaultFontSize;
  int _lineHeight = _defaultLineHeight;
  NovelReaderTheme _theme = NovelReaderTheme.paper;
  int? _savedPageIndex;
  int? _savedPageOffset;
  bool _loopRunning = false;
  bool _disposed = false;
  bool _initialised = false;
  bool _repaginating = false;
  bool _paginationComplete = false;
  int _paginationGeneration = 0;

  int get currentPageIndex => _currentPageIndex;
  int get currentDisplayPage => _pageConfigs.isEmpty ? 0 : _currentPageIndex + 1;

  /// Exact total when background scan finished; otherwise discovered count.
  int get totalDisplayPages => _pageConfigs.length;

  bool get isPaginationComplete => _paginationComplete;

  /// 0..1 reading progress by character offset (stable across reflow).
  double get progressRatio {
    final text = _bookText;
    final config = _safePageConfig(_currentPageIndex);
    if (text == null || text.isEmpty || config == null) return 0;
    return (config.startOffset / text.length).clamp(0.0, 1.0);
  }

  String get progressLabel {
    final percent = (progressRatio * 100).clamp(0, 100).round();
    if (_paginationComplete && _pageConfigs.isNotEmpty) {
      return '$currentDisplayPage / $totalDisplayPages · $percent%';
    }
    if (_pageConfigs.isEmpty) return '$percent%';
    return '$currentDisplayPage · $percent%';
  }

  bool get isReady => _initialised;
  bool get isRepaginating => _repaginating;
  List<NovelCanvasPageConfig> get pageConfigs => List.unmodifiable(_pageConfigs);
  List<NovelTocEntry> get tocEntries => List.unmodifiable(_tocEntries);
  int get fontSize => _fontSize;
  int get lineHeight => _lineHeight;
  NovelReaderTheme get theme => _theme;
  List<NovelReaderTheme> get themes => NovelReaderTheme.values;

  NovelCanvasPageData? get currentPageData => _pageDataMap[_currentPageIndex];
  NovelCanvasPageData? get prePageData =>
      _currentPageIndex > 0 ? _pageDataMap[_currentPageIndex - 1] : null;
  NovelCanvasPageData? get nextPageData =>
      _currentPageIndex + 1 < _pageConfigs.length
          ? _pageDataMap[_currentPageIndex + 1]
          : null;

  bool isCanGoNext() =>
      _currentPageIndex + 1 < _pageConfigs.length &&
      nextPageData?.picture != null;

  bool isCanGoPre() =>
      _currentPageIndex > 0 && prePageData?.picture != null;

  void setColorScheme(ColorScheme scheme) {
    _colorScheme = scheme;
  }

  void initialize({
    required String text,
    required int initialPageIndex,
    required int? initialPageOffset,
  }) {
    bgPaint = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.fill
      ..color = _theme.pageColor;
    _bookText = text;
    _tocEntries = buildNovelToc(text);
    _savedPageIndex = initialPageIndex;
    _savedPageOffset = initialPageOffset;
    _initialised = true;
    _startParseLooper();
    notifyListeners();
  }

  void setPageSize(Size size) {
    if (!_initialised) return;
    if ((_pageSize.width - size.width).abs() < 0.5 &&
        (_pageSize.height - size.height).abs() < 0.5) {
      return;
    }
    _pageSize = size;
    _repaginate();
  }

  Future<void> nextPage() async {
    if (!isCanGoNext()) return;
    _currentPageIndex += 1;
    _queuePagesAroundCurrent();
    notifyListeners();
    await _persistProgress();
  }

  Future<void> prePage() async {
    if (!isCanGoPre()) return;
    _currentPageIndex -= 1;
    _queuePagesAroundCurrent();
    notifyListeners();
    await _persistProgress();
  }

  Future<void> _persistProgress() async {
    final config = _safePageConfig(_currentPageIndex);
    if (config == null || onProgressChanged == null) return;
    await onProgressChanged!.call(_currentPageIndex, config.startOffset);
  }

  Future<void> goToPage(int pageIndex) async {
    if (pageIndex < 0) return;
    if (!_paginationComplete && pageIndex >= _pageConfigs.length) {
      await _waitUntilPageDiscovered(pageIndex);
    }
    if (pageIndex >= _pageConfigs.length) return;
    if (pageIndex == _currentPageIndex) return;
    _currentPageIndex = pageIndex;
    _queuePagesAroundCurrent();
    notifyListeners();
    await _persistProgress();
  }

  Future<void> goToProgress(double ratio) async {
    final text = _bookText;
    if (text == null || text.isEmpty) return;
    final offset =
        (text.length * ratio.clamp(0.0, 1.0)).floor().clamp(0, text.length - 1);
    await goToOffset(offset);
  }

  Future<void> goToOffset(int offset) async {
    final text = _bookText;
    if (text == null || text.isEmpty) return;
    final target = offset.clamp(0, text.length - 1);

    final existing = _findPageIndexForOffset(target);
    if (existing != null) {
      await goToPage(existing);
      return;
    }

    if (!_paginationComplete) {
      final generation = _paginationGeneration;
      while (!_disposed &&
          generation == _paginationGeneration &&
          !_paginationComplete) {
        final found = _findPageIndexForOffset(target);
        if (found != null) {
          await goToPage(found);
          return;
        }
        if (_pageConfigs.isNotEmpty &&
            _pageConfigs.last.endOffset >= target) {
          final nearest = _findNearestPageIndex(target);
          if (nearest != null) await goToPage(nearest);
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    }

    final afterScan = _findPageIndexForOffset(target) ??
        _findNearestPageIndex(target);
    if (afterScan != null) {
      await goToPage(afterScan);
      return;
    }

    _savedPageOffset = target;
    _savedPageIndex = null;
    await _repaginate();
  }

  Future<void> setFontSize(int value) async {
    final clamped = value.clamp(14, 30);
    if (clamped == _fontSize) return;
    final anchor = _safePageConfig(_currentPageIndex)?.startOffset;
    _fontSize = clamped;
    if (_lineHeight < _fontSize + 8) {
      _lineHeight = _fontSize + 8;
    }
    if (anchor != null) {
      _savedPageOffset = anchor;
      _savedPageIndex = null;
    }
    await _repaginate();
  }

  Future<void> setLineHeight(int value) async {
    final clamped = value.clamp(_fontSize + 6, 46);
    if (clamped == _lineHeight) return;
    final anchor = _safePageConfig(_currentPageIndex)?.startOffset;
    _lineHeight = clamped;
    if (anchor != null) {
      _savedPageOffset = anchor;
      _savedPageIndex = null;
    }
    await _repaginate();
  }

  void setTheme(NovelReaderTheme value) {
    if (value == _theme) return;
    _theme = value;
    bgPaint.color = value.pageColor;
    _clearPageCache();
    _queuePagesAroundCurrent();
    notifyListeners();
  }

  NovelPageLayoutMetrics? _currentLayout() {
    if (_pageSize == Size.zero) return null;
    final contentHeight = _pageSize.height -
        _contentPadding.vertical -
        _bottomTipHeight -
        _titleHeight;
    final contentWidth = _pageSize.width - _contentPadding.horizontal;
    if (contentHeight <= 0 || contentWidth <= 0) return null;
    return NovelPageLayoutMetrics(
      height: contentHeight,
      width: contentWidth,
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      paragraphSpacing: _paragraphSpacing,
    );
  }

  Future<void> _repaginate() async {
    final text = _bookText;
    final layout = _currentLayout();
    if (text == null || layout == null) return;

    final generation = ++_paginationGeneration;
    _repaginating = true;
    _paginationComplete = false;
    _clearPageCache();
    _pageConfigs = <NovelCanvasPageConfig>[];
    _microParseQueue.clear();
    _parseQueue.clear();
    notifyListeners();

    final session = NovelIncrementalPaginator(text: text, layout: layout);

    var initialPageResolved = false;
    var readyNotified = false;

    while (!_disposed && generation == _paginationGeneration) {
      // Skeleton-only during bulk scan; hydrate near the reading window on demand.
      final nextPage = session.nextPage(includeContents: false);
      if (nextPage == null) break;
      _pageConfigs.add(nextPage);

      if (!initialPageResolved && _shouldUseAsInitialPage(nextPage)) {
        _currentPageIndex = nextPage.pageIndex;
        _savedPageIndex = null;
        _savedPageOffset = null;
        initialPageResolved = true;
      }

      if (_pageConfigs.length == 1 && !initialPageResolved) {
        _currentPageIndex = 0;
      }

      if (!initialPageResolved && _savedPageIndex != null) {
        if (_savedPageIndex! >= 0 && _savedPageIndex! < _pageConfigs.length) {
          _currentPageIndex = _savedPageIndex!;
          _savedPageIndex = null;
          _savedPageOffset = null;
          initialPageResolved = true;
        }
      }

      if (initialPageResolved && !readyNotified) {
        final ahead = nextPage.pageIndex - _currentPageIndex;
        if (ahead >= _readyAheadPages || session.isComplete) {
          _hydrateContentWindow();
          _queuePagesAroundCurrent();
          _repaginating = false;
          readyNotified = true;
          notifyListeners();
          unawaited(_persistProgress());
        }
      } else if (readyNotified &&
          nextPage.pageIndex <= _currentPageIndex + _rasterWindowRadius) {
        _hydrateContentWindow();
        _queuePagesAroundCurrent();
        notifyListeners();
      }

      await Future<void>.delayed(Duration.zero);
    }

    if (_disposed || generation != _paginationGeneration) {
      return;
    }

    _paginationComplete = true;
    if (_pageConfigs.isEmpty) {
      _currentPageIndex = 0;
    } else {
      _currentPageIndex = math.min(_currentPageIndex, _pageConfigs.length - 1);
      _hydrateContentWindow();
      _queuePagesAroundCurrent();
    }
    _repaginating = false;
    notifyListeners();
    unawaited(_persistProgress());
  }

  Future<void> _waitUntilPageDiscovered(int pageIndex) async {
    final generation = _paginationGeneration;
    while (!_disposed &&
        generation == _paginationGeneration &&
        !_paginationComplete &&
        pageIndex >= _pageConfigs.length) {
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
  }

  bool _shouldUseAsInitialPage(NovelCanvasPageConfig config) {
    if (_savedPageOffset != null) {
      return _savedPageOffset! >= config.startOffset &&
          _savedPageOffset! <= config.endOffset;
    }
    if (_savedPageIndex != null) {
      return config.pageIndex == _savedPageIndex;
    }
    return config.pageIndex == 0;
  }

  int? _findPageIndexForOffset(int offset) {
    for (var i = 0; i < _pageConfigs.length; i += 1) {
      final page = _pageConfigs[i];
      final end = i + 1 < _pageConfigs.length
          ? _pageConfigs[i + 1].startOffset
          : page.endOffset;
      if (offset >= page.startOffset && offset < end) return i;
      if (offset >= page.startOffset && offset <= page.endOffset) return i;
    }
    return null;
  }

  int? _findNearestPageIndex(int offset) {
    if (_pageConfigs.isEmpty) return null;
    var best = 0;
    var bestDist = (offset - _pageConfigs[0].startOffset).abs();
    for (var i = 1; i < _pageConfigs.length; i += 1) {
      final dist = (offset - _pageConfigs[i].startOffset).abs();
      if (dist < bestDist) {
        best = i;
        bestDist = dist;
      }
    }
    return best;
  }

  void _hydrateContentWindow() {
    final text = _bookText;
    final layout = _currentLayout();
    if (text == null || layout == null || _pageConfigs.isEmpty) return;

    final start = math.max(0, _currentPageIndex - _contentWindowRadius);
    final end =
        math.min(_pageConfigs.length - 1, _currentPageIndex + _contentWindowRadius);
    for (var i = start; i <= end; i += 1) {
      final page = _pageConfigs[i];
      if (page.hasContents) continue;
      _pageConfigs[i] = hydratePageAtOffset(
        text: text,
        layout: layout,
        pageIndex: page.pageIndex,
        startOffset: page.startOffset,
      );
    }
    stripPageContentsOutsideWindow(
      pages: _pageConfigs,
      currentIndex: _currentPageIndex,
      radius: _contentWindowRadius,
    );
  }

  void _queuePagesAroundCurrent() {
    _microParseQueue.clear();
    _parseQueue.clear();
    if (_pageConfigs.isEmpty) return;

    _hydrateContentWindow();

    final windowStart = math.max(0, _currentPageIndex - _rasterWindowRadius);
    final windowEnd =
        math.min(_pageConfigs.length - 1, _currentPageIndex + _rasterWindowRadius);
    final priorityStart =
        math.max(0, _currentPageIndex - _rasterPriorityRadius);
    final priorityEnd = math.min(
      _pageConfigs.length - 1,
      _currentPageIndex + _rasterPriorityRadius,
    );

    for (var index = priorityStart; index <= priorityEnd; index += 1) {
      _enqueuePage(index, micro: true);
    }
    for (var index = windowStart; index <= windowEnd; index += 1) {
      if (index >= priorityStart && index <= priorityEnd) continue;
      _enqueuePage(index, micro: false);
    }

    _evictPagesOutsideWindow(windowStart, windowEnd);
  }

  void _enqueuePage(int index, {required bool micro}) {
    if (_pageDataMap[index]?.picture != null) return;
    if (_microParseQueue.contains(index) || _parseQueue.contains(index)) return;
    (micro ? _microParseQueue : _parseQueue).add(index);
  }

  bool _isInsideRasterWindow(int index) {
    if (_pageConfigs.isEmpty) return false;
    final windowStart = math.max(0, _currentPageIndex - _rasterWindowRadius);
    final windowEnd =
        math.min(_pageConfigs.length - 1, _currentPageIndex + _rasterWindowRadius);
    return index >= windowStart && index <= windowEnd;
  }

  void _evictPagesOutsideWindow(int windowStart, int windowEnd) {
    final staleKeys = <int>[];
    for (final key in _pageDataMap.keys) {
      if (key < windowStart || key > windowEnd) {
        staleKeys.add(key);
      }
    }
    for (final key in staleKeys) {
      _pageDataMap.remove(key)?.dispose();
    }
  }

  void _clearPageCache() {
    for (final data in _pageDataMap.values) {
      data.dispose();
    }
    _pageDataMap.clear();
  }

  void _startParseLooper() {
    if (_loopRunning) return;
    _loopRunning = true;
    Future<void>(() async {
      while (!_disposed) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (_disposed ||
            _repaginating ||
            _pageSize == Size.zero ||
            _pageConfigs.isEmpty) {
          continue;
        }
        if (_microParseQueue.isNotEmpty) {
          final target = _microParseQueue.removeFirst();
          await _parseAndCachePage(target);
          continue;
        }
        if (_parseQueue.isNotEmpty) {
          final target = _parseQueue.removeFirst();
          await _parseAndCachePage(target);
        }
      }
      _loopRunning = false;
    });
  }

  Future<void> _parseAndCachePage(int index) async {
    if (_disposed || _pageSize == Size.zero) return;
    if (!_isInsideRasterWindow(index)) return;
    if (_pageDataMap[index]?.picture != null) return;
    if (index < 0 || index >= _pageConfigs.length) return;

    _hydrateContentWindow();
    if (!_pageConfigs[index].hasContents) return;

    final picture = _drawPage(index);
    final image = await picture.toImage(
      _pageSize.width.ceil(),
      _pageSize.height.ceil(),
    );
    if (_disposed || !_isInsideRasterWindow(index)) {
      image.dispose();
      picture.dispose();
      return;
    }
    _pageDataMap[index]?.dispose();
    _pageDataMap[index] = NovelCanvasPageData(
      pageIndex: index,
      picture: picture,
      image: image,
    );
    if ((index - _currentPageIndex).abs() <= 1) {
      notifyListeners();
    }
  }

  String _footerText(int index) {
    final text = _bookText;
    final page = _safePageConfig(index);
    final percent = (text == null || text.isEmpty || page == null)
        ? 0
        : ((page.startOffset / text.length) * 100).clamp(0, 100).round();
    if (_paginationComplete) {
      return '${index + 1}/${_pageConfigs.length}';
    }
    return '${index + 1} · $percent%';
  }

  ui.Picture _drawPage(int index) {
    final config = _pageConfigs[index];
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final bounds = Offset.zero & _pageSize;
    final rrect = BorderRadius.circular(18).toRRect(bounds);

    canvas.drawRRect(rrect, bgPaint);
    canvas.drawRRect(
      rrect,
      Paint()
        ..color = _colorScheme!.tertiary
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    canvas.save();
    canvas.clipRRect(rrect);
    canvas.drawRect(
      bounds,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(255, 255, 255, 0.28),
            Color.fromRGBO(255, 255, 255, 0.0),
            Color.fromRGBO(165, 42, 42, 0.03),
          ],
        ).createShader(bounds),
    );
    canvas.restore();

    final titleOffset = Offset(
      _contentPadding.left,
      _contentPadding.top,
    );
    _titlePainter.text = TextSpan(
      text: title,
      style: TextStyle(
        color: _theme.titleColor,
        fontWeight: FontWeight.w700,
        fontSize: _titleFontSize.toDouble(),
        height: _titleHeight / _titleFontSize,
      ),
    );
    _titlePainter.layout(maxWidth: _pageSize.width - _contentPadding.horizontal);
    _titlePainter.paint(canvas, titleOffset);

    var offset = Offset(
      _contentPadding.left,
      _contentPadding.top + _titleHeight.toDouble(),
    );

    for (final paragraph in config.paragraphContents) {
      _contentPainter.text = TextSpan(
        text: paragraph,
        style: TextStyle(
          color: _theme.textColor,
          fontSize: _fontSize.toDouble(),
          height: _lineHeight / _fontSize,
          letterSpacing: 0.15,
        ),
      );
      _contentPainter.layout(
        maxWidth: _pageSize.width - _contentPadding.horizontal,
      );
      _contentPainter.paint(canvas, offset);
      offset = Offset(
        _contentPadding.left,
        offset.dy +
            (_contentPainter.computeLineMetrics().length * _lineHeight) +
            _paragraphSpacing.toDouble(),
      );
    }

    _footerPainter.text = TextSpan(
      text: _footerText(index),
      style: TextStyle(
        color: _theme.titleColor,
        fontSize: _bottomTipFontSize.toDouble(),
        height: _bottomTipHeight / _bottomTipFontSize,
      ),
    );
    _footerPainter.layout(
      maxWidth: _pageSize.width - _contentPadding.horizontal,
    );
    _footerPainter.paint(
      canvas,
      Offset(
        _contentPadding.left,
        _pageSize.height - _contentPadding.bottom - _bottomTipHeight,
      ),
    );

    return recorder.endRecording();
  }

  NovelCanvasPageConfig? _safePageConfig(int index) {
    if (index < 0 || index >= _pageConfigs.length) return null;
    return _pageConfigs[index];
  }

  @override
  void dispose() {
    _disposed = true;
    _microParseQueue.clear();
    _parseQueue.clear();
    _clearPageCache();
    super.dispose();
  }
}

enum NovelReaderTheme {
  paper(
    'Paper',
    Color(0xFFF9F1E4),
    Color(0xFF2E231B),
    Color(0xFF634B38),
  ),
  mist(
    'Mist',
    Color(0xFFF2F4EF),
    Color(0xFF243028),
    Color(0xFF4C5A52),
  ),
  night(
    'Night',
    Color(0xFF23211E),
    Color(0xFFE7DDCF),
    Color(0xFFC9BBA8),
  );

  const NovelReaderTheme(
    this.label,
    this.pageColor,
    this.textColor,
    this.titleColor,
  );

  final String label;
  final Color pageColor;
  final Color textColor;
  final Color titleColor;
}

class NovelCanvasReaderView extends StatefulWidget {
  const NovelCanvasReaderView({
    super.key,
    required this.controller,
    required this.onToggleChrome,
  });

  final NovelCanvasReaderController controller;
  final VoidCallback onToggleChrome;

  @override
  State<NovelCanvasReaderView> createState() => _NovelCanvasReaderViewState();
}

class _NovelCanvasReaderViewState extends State<NovelCanvasReaderView>
    with TickerProviderStateMixin {
  late final GlobalKey _canvasKey = GlobalKey();
  late final CanvasPageManager _pageManager;
  late final NovelCanvasPagePainter _painter;
  late final AnimationControllerWithListenerNumber _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationControllerWithListenerNumber(vsync: this);
    _pageManager = CanvasPageManager()
      ..setCurrentAnimation(CanvasPageManager.typeAnimationSimulationTurn)
      ..setCurrentCanvasContainerContext(_canvasKey)
      ..setAnimationController(_animationController)
      ..setController(widget.controller);
    _painter = NovelCanvasPagePainter(pageManager: _pageManager);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scheme = Theme.of(context).colorScheme;
    _pageManager.setScheme(scheme);
    widget.controller.setColorScheme(scheme);
  }

  @override
  void didUpdateWidget(covariant NovelCanvasReaderView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _pageManager.setController(widget.controller);
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        widget.controller.setPageSize(size);
        _pageManager.setPageSize(size);

        return AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) {
            if (widget.controller.isRepaginating ||
                widget.controller.currentPageData?.picture == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onToggleChrome,
              onPanDown: (details) {
                _painter.setCurrentTouchEvent(
                  CanvasTouchEvent(
                    CanvasTouchEvent.actionDown,
                    details.localPosition,
                  ),
                );
                _markNeedsPaint();
              },
              onPanUpdate: (details) {
                _painter.setCurrentTouchEvent(
                  CanvasTouchEvent(
                    CanvasTouchEvent.actionMove,
                    details.localPosition,
                  ),
                );
                _markNeedsPaint();
              },
              onPanEnd: (details) {
                final event = CanvasTouchEvent<DragEndDetails>(
                  CanvasTouchEvent.actionUp,
                  Offset.zero,
                )..touchDetail = details;
                _painter.setCurrentTouchEvent(event);
                _markNeedsPaint();
              },
              onPanCancel: () {
                _painter.setCurrentTouchEvent(
                  CanvasTouchEvent(
                    CanvasTouchEvent.actionCancel,
                    Offset.zero,
                  ),
                );
                _markNeedsPaint();
              },
              child: SizedBox.expand(
                child: CustomPaint(
                  key: _canvasKey,
                  isComplex: true,
                  painter: _painter,
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _markNeedsPaint() {
    final renderObject = _canvasKey.currentContext?.findRenderObject();
    if (renderObject is RenderObject) {
      renderObject.markNeedsPaint();
    }
  }
}

class NovelCanvasPagePainter extends CustomPainter {
  NovelCanvasPagePainter({required this.pageManager});

  final CanvasPageManager pageManager;
  CanvasTouchEvent? currentTouchData;

  void setCurrentTouchEvent(CanvasTouchEvent event) {
    currentTouchData = event;
    pageManager.setCurrentTouchEvent(event);
  }

  @override
  void paint(Canvas canvas, Size size) {
    pageManager.setPageSize(size);
    pageManager.onPageDraw(canvas);
  }

  @override
  bool shouldRepaint(covariant NovelCanvasPagePainter oldDelegate) {
    return pageManager.shouldRepaint(oldDelegate, this);
  }
}

class CanvasPageManager {
  static const typeAnimationSimulationTurn = 1;

  BaseCanvasAnimationPage? currentAnimationPage;
  CanvasTouchEvent? currentTouchData;
  int currentAnimationType = 0;
  CanvasPageManagerState currentState = CanvasPageManagerState.idle;
  GlobalKey? canvasKey;
  AnimationController? animationController;
  Animation<Offset>? _boundAnimation;
  ColorScheme? _scheme;

  void setCurrentTouchEvent(CanvasTouchEvent event) {
    if (currentState == CanvasPageManagerState.animating) {
      if (currentAnimationPage?.isShouldAnimatingInterrupt() ?? false) {
        if (event.action == CanvasTouchEvent.actionDown) {
          interruptCancelAnimation();
        }
      } else {
        return;
      }
    }

    if (event.action == CanvasTouchEvent.actionUp ||
        event.action == CanvasTouchEvent.actionCancel) {
      if (currentAnimationPage == null) return;
      if (currentAnimationPage!.isCancelArea()) {
        startCancelAnimation();
      } else if (currentAnimationPage!.isConfirmArea()) {
        startConfirmAnimation();
      }
      return;
    }

    currentTouchData = event;
    currentAnimationPage?.onTouchEvent(event);
  }

  void setPageSize(Size size) {
    currentAnimationPage?.setSize(size);
  }

  void setController(NovelCanvasReaderController controller) {
    currentAnimationPage?.setController(controller);
  }

  void onPageDraw(Canvas canvas) {
    currentAnimationPage?.onDraw(canvas);
  }

  void setScheme(ColorScheme scheme) {
    _scheme = scheme;
  }

  void setCurrentAnimation(int animationType) {
    currentAnimationType = animationType;
    if (animationType == typeAnimationSimulationTurn) {
      final anim = SimulationTurnCanvasAnimation();
      if (_scheme != null) anim.scheme = _scheme!;
      currentAnimationPage = anim;
    }
  }

  void setCurrentCanvasContainerContext(GlobalKey canvasKey) {
    this.canvasKey = canvasKey;
  }

  void startConfirmAnimation() {
    final animation = currentAnimationPage?.getConfirmAnimation(
      animationController!,
      canvasKey!,
    );
    if (animation == null) return;
    _setAnimation(animation);
    animationController!.forward();
  }

  void startCancelAnimation() {
    final animation = currentAnimationPage?.getCancelAnimation(
      animationController!,
      canvasKey!,
    );
    if (animation == null) return;
    _setAnimation(animation);
    animationController!.forward();
  }

  void _setAnimation(Animation<Offset> animation) {
    if (animationController!.isCompleted) {
      animationController!.reset();
    }
    if (!identical(_boundAnimation, animation)) {
      _boundAnimation = animation;
      animation
        ..addListener(() {
          currentState = CanvasPageManagerState.animating;
          final renderObject = canvasKey?.currentContext?.findRenderObject();
          if (renderObject is RenderObject) {
            renderObject.markNeedsPaint();
          }
          currentAnimationPage?.onTouchEvent(
            CanvasTouchEvent(
              CanvasTouchEvent.actionMove,
              animation.value,
            ),
          );
        })
        ..addStatusListener((status) {
          switch (status) {
            case AnimationStatus.completed:
              currentState = CanvasPageManagerState.idle;
              currentAnimationPage?.onTouchEvent(
                CanvasTouchEvent(CanvasTouchEvent.actionUp, Offset.zero),
              );
              currentTouchData =
                  CanvasTouchEvent(CanvasTouchEvent.actionUp, Offset.zero);
              animationController?.stop();
              break;
            case AnimationStatus.dismissed:
              break;
            case AnimationStatus.forward:
            case AnimationStatus.reverse:
              currentState = CanvasPageManagerState.animating;
              break;
          }
        });
    }
  }

  void interruptCancelAnimation() {
    if (animationController != null && !animationController!.isCompleted) {
      animationController!.stop();
      currentState = CanvasPageManagerState.idle;
      currentAnimationPage?.onTouchEvent(
        CanvasTouchEvent(CanvasTouchEvent.actionUp, Offset.zero),
      );
      currentTouchData = CanvasTouchEvent(CanvasTouchEvent.actionUp, Offset.zero);
    }
  }

  bool shouldRepaint(CustomPainter oldDelegate, NovelCanvasPagePainter currentDelegate) {
    if (currentState == CanvasPageManagerState.animating) {
      return true;
    }
    if (currentTouchData?.action == CanvasTouchEvent.actionDown) {
      return true;
    }
    if (oldDelegate is! NovelCanvasPagePainter) return true;
    return oldDelegate.currentTouchData != currentDelegate.currentTouchData;
  }

  void setAnimationController(AnimationController controller) {
    controller.duration = const Duration(milliseconds: 300);
    animationController = controller;
  }
}

enum CanvasPageManagerState { animating, idle }

class CanvasTouchEvent<T> {
  CanvasTouchEvent(this.action, this.touchPos);

  static const actionDown = 0;
  static const actionMove = 1;
  static const actionUp = 2;
  static const actionCancel = 3;

  final int action;
  final Offset touchPos;
  T? touchDetail;

  @override
  bool operator ==(Object other) {
    return other is CanvasTouchEvent &&
        other.action == action &&
        other.touchPos == touchPos;
  }

  @override
  int get hashCode => Object.hash(action, touchPos);
}

abstract class BaseCanvasAnimationPage {
  Offset mTouch = Offset.zero;
  Size currentSize = Size.zero;
  NovelCanvasReaderController? readerController;

  void setSize(Size size) {
    currentSize = size;
  }

  void setController(NovelCanvasReaderController controller) {
    readerController = controller;
  }

  void onDraw(Canvas canvas);
  void onTouchEvent(CanvasTouchEvent event);

  bool isShouldAnimatingInterrupt() => false;
  bool isCancelArea();
  bool isConfirmArea();
  Animation<Offset>? getCancelAnimation(
    AnimationController controller,
    GlobalKey canvasKey,
  );
  Animation<Offset>? getConfirmAnimation(
    AnimationController controller,
    GlobalKey canvasKey,
  );
}

class SimulationTurnCanvasAnimation extends BaseCanvasAnimationPage {
  ColorScheme scheme = const ColorScheme.light();
  bool isStartAnimation = false;
  final Path mTopPagePath = Path();
  final Path mBottomPagePath = Path();
  Path mTopBackAreaPagePath = Path();

  double mCornerX = 1;
  double mCornerY = 1;
  bool mIsRTandLB = false;

  Offset mBezierStart1 = Offset.zero;
  Offset mBezierControl1 = Offset.zero;
  Offset mBezierVertex1 = Offset.zero;
  Offset mBezierEnd1 = Offset.zero;
  Offset mBezierStart2 = Offset.zero;
  Offset mBezierControl2 = Offset.zero;
  Offset mBezierVertex2 = Offset.zero;
  Offset mBezierEnd2 = Offset.zero;

  double mMiddleX = 0;
  double mMiddleY = 0;
  double mTouchToCornerDis = 0;
  double mMaxLength = 0;

  bool isTurnToNext = false;
  bool isConfirmAnimation = false;

  Tween<Offset>? currentAnimationTween;
  Animation<Offset>? currentAnimation;
  AnimationStatusListener? statusListener;

  void calBezierPoint() {
    mMiddleX = (mTouch.dx + mCornerX) / 2;
    mMiddleY = (mTouch.dy + mCornerY) / 2;
    mMaxLength = math.sqrt(
      math.pow(currentSize.width, 2) + math.pow(currentSize.height, 2),
    );

    mBezierControl1 = Offset(
      mMiddleX -
          (mCornerY - mMiddleY) * (mCornerY - mMiddleY) / (mCornerX - mMiddleX),
      mCornerY,
    );

    final f4 = mCornerY - mMiddleY;
    if (f4 == 0) {
      mBezierControl2 = Offset(
        mCornerX,
        mMiddleY - (mCornerX - mMiddleX) * (mCornerX - mMiddleX) / 0.1,
      );
    } else {
      mBezierControl2 = Offset(
        mCornerX,
        mMiddleY - (mCornerX - mMiddleX) * (mCornerX - mMiddleX) / f4,
      );
    }

    mBezierStart1 = Offset(
      mBezierControl1.dx - (mCornerX - mBezierControl1.dx) / 2,
      mCornerY,
    );

    if (mTouch.dx > 0 &&
        mTouch.dx < currentSize.width &&
        (mBezierStart1.dx < 0 || mBezierStart1.dx > currentSize.width)) {
      if (mBezierStart1.dx < 0) {
        mBezierStart1 =
            Offset(currentSize.width - mBezierStart1.dx, mBezierStart1.dy);
      }

      final f1 = (mCornerX - mTouch.dx).abs();
      final f2 = currentSize.width * f1 / mBezierStart1.dx;
      mTouch = Offset((mCornerX - f2).abs(), mTouch.dy);
      final f3 = (mCornerX - mTouch.dx).abs() * (mCornerY - mTouch.dy).abs() / f1;
      mTouch = Offset((mCornerX - f2).abs(), (mCornerY - f3).abs());

      mMiddleX = (mTouch.dx + mCornerX) / 2;
      mMiddleY = (mTouch.dy + mCornerY) / 2;
      mBezierControl1 = Offset(
        mMiddleX -
            (mCornerY - mMiddleY) * (mCornerY - mMiddleY) / (mCornerX - mMiddleX),
        mCornerY,
      );
      final f5 = mCornerY - mMiddleY;
      if (f5 == 0) {
        mBezierControl2 = Offset(
          mCornerX,
          mMiddleY - (mCornerX - mMiddleX) * (mCornerX - mMiddleX) / 0.1,
        );
      } else {
        mBezierControl2 = Offset(
          mCornerX,
          mMiddleY - (mCornerX - mMiddleX) * (mCornerX - mMiddleX) / f5,
        );
      }
      mBezierStart1 = Offset(
        mBezierControl1.dx - (mCornerX - mBezierControl1.dx) / 2,
        mBezierStart1.dy,
      );
    }

    mBezierStart2 = Offset(
      mCornerX,
      mBezierControl2.dy - (mCornerY - mBezierControl2.dy) / 2,
    );

    mTouchToCornerDis = math.sqrt(
      math.pow(mTouch.dx - mCornerX, 2) + math.pow(mTouch.dy - mCornerY, 2),
    );
    mBezierEnd1 = getCross(mTouch, mBezierControl1, mBezierStart1, mBezierStart2);
    mBezierEnd2 = getCross(mTouch, mBezierControl2, mBezierStart1, mBezierStart2);
    mBezierVertex1 = Offset(
      (mBezierStart1.dx + 2 * mBezierControl1.dx + mBezierEnd1.dx) / 4,
      (2 * mBezierControl1.dy + mBezierStart1.dy + mBezierEnd1.dy) / 4,
    );
    mBezierVertex2 = Offset(
      (mBezierStart2.dx + 2 * mBezierControl2.dx + mBezierEnd2.dx) / 4,
      (2 * mBezierControl2.dy + mBezierStart2.dy + mBezierEnd2.dy) / 4,
    );
  }

  Offset getCross(Offset p1, Offset p2, Offset p3, Offset p4) {
    final k1 = (p2.dy - p1.dy) / (p2.dx - p1.dx);
    final b1 = ((p1.dx * p2.dy) - (p2.dx * p1.dy)) / (p1.dx - p2.dx);
    final k2 = (p4.dy - p3.dy) / (p4.dx - p3.dx);
    final b2 = ((p3.dx * p4.dy) - (p4.dx * p3.dy)) / (p3.dx - p4.dx);
    return Offset((b2 - b1) / (k1 - k2), k1 * ((b2 - b1) / (k1 - k2)) + b1);
  }

  void calcCornerXY(double x, double y) {
    mCornerX = x <= currentSize.width / 2 ? 0 : currentSize.width;
    mCornerY = y <= currentSize.height / 2 ? 0 : currentSize.height;
    mIsRTandLB = (mCornerX == 0 && mCornerY == currentSize.height) ||
        (mCornerX == currentSize.width && mCornerY == 0);
  }

  @override
  void onTouchEvent(CanvasTouchEvent event) {
    mTouch = event.touchPos;

    switch (event.action) {
      case CanvasTouchEvent.actionDown:
        calcCornerXY(mTouch.dx, mTouch.dy);
        break;
      case CanvasTouchEvent.actionMove:
        isTurnToNext = mTouch.dx - mCornerX < 0;
        if ((!isTurnToNext && (readerController?.isCanGoPre() ?? false)) ||
            (isTurnToNext && (readerController?.isCanGoNext() ?? false))) {
          isStartAnimation = true;
        }
        break;
      case CanvasTouchEvent.actionUp:
      case CanvasTouchEvent.actionCancel:
        if ((!isTurnToNext && (readerController?.isCanGoPre() ?? false)) ||
            (isTurnToNext && (readerController?.isCanGoNext() ?? false))) {
          isStartAnimation = true;
        }
        break;
      default:
        break;
    }

    calBezierPoint();
  }

  @override
  void onDraw(Canvas canvas) {
    if (isStartAnimation && mTouch != Offset.zero) {
      drawTopPageCanvas(canvas);
      drawBottomPageCanvas(canvas);
      drawTopPageBackArea(canvas);
    } else {
      final targetPicture = readerController?.currentPageData?.picture;
      if (targetPicture != null) {
        canvas.drawPicture(targetPicture);
      }
    }
    isStartAnimation = false;
  }

  void drawTopPageCanvas(Canvas canvas) {
    mTopPagePath.reset();
    mTopPagePath.moveTo(mCornerX == 0 ? currentSize.width : 0, mCornerY);
    mTopPagePath.lineTo(mBezierStart1.dx, mBezierStart1.dy);
    mTopPagePath.quadraticBezierTo(
      mBezierControl1.dx,
      mBezierControl1.dy,
      mBezierEnd1.dx,
      mBezierEnd1.dy,
    );
    mTopPagePath.lineTo(mTouch.dx, mTouch.dy);
    mTopPagePath.lineTo(mBezierEnd2.dx, mBezierEnd2.dy);
    mTopPagePath.quadraticBezierTo(
      mBezierControl2.dx,
      mBezierControl2.dy,
      mBezierStart2.dx,
      mBezierStart2.dy,
    );
    mTopPagePath.lineTo(mCornerX, mCornerY == 0 ? currentSize.height : 0);
    mTopPagePath.lineTo(
      mCornerX == 0 ? currentSize.width : 0,
      mCornerY == 0 ? currentSize.height : 0,
    );
    mTopPagePath.close();

    final clipBounds = Path()
      ..addRect(Offset.zero & currentSize);
    final safePath = Path.combine(PathOperation.intersect, clipBounds, mTopPagePath);

    canvas.save();
    canvas.clipPath(safePath, doAntiAlias: false);
    final picture = readerController?.currentPageData?.picture;
    if (picture != null) {
      canvas.drawPicture(picture);
    }
    drawTopPageShadow(canvas);
    canvas.restore();
  }

  void drawTopPageShadow(Canvas canvas) {
    final dx = mCornerX == 0 ? 5 : -5;
    final dy = mCornerY == 0 ? 5 : -5;
    final shadowPath = Path.combine(
      PathOperation.intersect,
      Path()..addRect(Offset.zero & currentSize),
      Path()
        ..moveTo(mTouch.dx + dx, mTouch.dy + dy)
        ..lineTo(mBezierControl2.dx + dx, mBezierControl2.dy + dy)
        ..lineTo(mBezierControl1.dx + dx, mBezierControl1.dy + dy)
        ..close(),
    );
    canvas.drawShadow(shadowPath, scheme.onSurface, 5, true);
  }

  void drawBottomPageCanvas(Canvas canvas) {
    mBottomPagePath.reset();
    mBottomPagePath.moveTo(mCornerX, mCornerY);
    mBottomPagePath.lineTo(mBezierStart1.dx, mBezierStart1.dy);
    mBottomPagePath.quadraticBezierTo(
      mBezierControl1.dx,
      mBezierControl1.dy,
      mBezierEnd1.dx,
      mBezierEnd1.dy,
    );
    mBottomPagePath.lineTo(mBezierEnd2.dx, mBezierEnd2.dy);
    mBottomPagePath.quadraticBezierTo(
      mBezierControl2.dx,
      mBezierControl2.dy,
      mBezierStart2.dx,
      mBezierStart2.dy,
    );
    mBottomPagePath.close();

    final extraRegion = Path()
      ..moveTo(mTouch.dx, mTouch.dy)
      ..lineTo(mBezierVertex1.dx, mBezierVertex1.dy)
      ..lineTo(mBezierVertex2.dx, mBezierVertex2.dy)
      ..close();
    final diffPath = Path.combine(PathOperation.difference, mBottomPagePath, extraRegion);
    final safePath = Path.combine(
      PathOperation.intersect,
      Path()..addRect(Offset.zero & currentSize),
      diffPath,
    );

    canvas.save();
    canvas.clipPath(safePath, doAntiAlias: false);
    final picture = isTurnToNext
        ? readerController?.nextPageData?.picture
        : readerController?.prePageData?.picture;
    if (picture != null) {
      canvas.drawPicture(picture);
    }
    drawBottomPageShadow(canvas);
    canvas.restore();
  }

  void drawBottomPageShadow(Canvas canvas) {
    double left;
    double right;
    Gradient shadowGradient;
    if (mIsRTandLB) {
      left = 0;
      right = mTouchToCornerDis / 4;
      shadowGradient = LinearGradient(
        colors: [Color(0xAA000000), scheme.surface.withValues(alpha: 0.0)],
      );
    } else {
      left = -mTouchToCornerDis / 4;
      right = 0;
      shadowGradient = LinearGradient(
        colors: [scheme.surface.withValues(alpha: 0.0), Color(0xAA000000)],
      );
    }

    canvas.save();
    canvas.translate(mBezierStart1.dx, mBezierStart1.dy);
    canvas.rotate(
      math.atan2(mBezierControl1.dx - mCornerX, mBezierControl2.dy - mCornerY),
    );
    canvas.drawRect(
      Rect.fromLTRB(left, 0, right, mMaxLength),
      Paint()
        ..isAntiAlias = false
        ..style = PaintingStyle.fill
        ..shader = shadowGradient.createShader(
          Rect.fromLTRB(left, 0, right, mMaxLength),
        ),
    );
    canvas.restore();
  }

  void drawTopPageBackArea(Canvas canvas) {
    final tempBackAreaPath = Path()
      ..moveTo(mBezierVertex1.dx, mBezierVertex1.dy)
      ..lineTo(mBezierVertex2.dx, mBezierVertex2.dy)
      ..lineTo(mTouch.dx, mTouch.dy)
      ..close();

    mTopBackAreaPagePath = Path.combine(
      PathOperation.intersect,
      tempBackAreaPath,
      mBottomPagePath,
    );
    mTopBackAreaPagePath = Path.combine(
      PathOperation.intersect,
      Path()..addRect(Offset.zero & currentSize),
      mTopBackAreaPagePath,
    );

    canvas.save();
    canvas.clipPath(mTopBackAreaPagePath);
    canvas.drawPaint(Paint()..color = readerController?.bgPaint.color ?? scheme.surface);
    canvas.save();
    canvas.translate(mBezierControl1.dx, mBezierControl1.dy);

    final dis = math.sqrt(
      math.pow(mCornerX - mBezierControl1.dx, 2) +
          math.pow(mBezierControl2.dy - mCornerY, 2),
    );
    final sinAngle = (mCornerX - mBezierControl1.dx) / dis;
    final cosAngle = (mBezierControl2.dy - mCornerY) / dis;
    final matrix = Matrix4.identity()
      ..setEntry(0, 0, -(1 - 2 * sinAngle * sinAngle))
      ..setEntry(1, 0, 2 * sinAngle * cosAngle)
      ..setEntry(0, 1, 2 * sinAngle * cosAngle)
      ..setEntry(1, 1, 1 - 2 * sinAngle * sinAngle)
      ..translateByDouble(-mBezierControl1.dx, -mBezierControl1.dy, 0, 1);
    canvas.transform(matrix.storage);

    final image = readerController?.currentPageData?.image;
    if (image != null) {
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        Offset.zero & currentSize,
        Paint()..isAntiAlias = true,
      );
    } else {
      final picture = readerController?.currentPageData?.picture;
      if (picture != null) {
        canvas.drawPicture(picture);
      }
    }
    canvas.drawPaint(
      Paint()
        ..color = Color(
          (readerController?.bgPaint.color.toARGB32() ?? 0xFFF9F1E4) &
              0xAAFFFFFF,
        ),
    );
    canvas.restore();
    drawTopPageBackAreaShadow(canvas);
    canvas.restore();
  }

  void drawTopPageBackAreaShadow(Canvas canvas) {
    final center = (mBezierStart1.dx + mBezierControl1.dx) / 2;
    final topDistance = (center - mBezierControl1.dx).abs();
    final middle = (mBezierStart2.dy + mBezierControl2.dy) / 2;
    final sideDistance = (middle - mBezierControl2.dy).abs();
    final width = math.min(topDistance, sideDistance);

    final left = mIsRTandLB ? (mBezierStart1.dx - 1) : (mBezierStart1.dx - width - 1);
    final right = mIsRTandLB ? (mBezierStart1.dx + width + 1) : (mBezierStart1.dx + 1);
    final shaderWidth = mIsRTandLB ? right - left : left - right;

    canvas.save();
    canvas.translate(mBezierStart1.dx, mBezierStart1.dy);
    canvas.rotate(
      math.atan2(mBezierControl1.dx - mCornerX, mBezierControl2.dy - mCornerY),
    );
    canvas.drawRect(
      Rect.fromLTRB(0, 0, shaderWidth, mMaxLength),
      Paint()
        ..isAntiAlias = true
        ..style = PaintingStyle.fill
        ..shader = LinearGradient(
          colors: [scheme.surface.withValues(alpha: 0.0), Color(0xAA000000)],
        ).createShader(Rect.fromLTRB(0, 0, shaderWidth, mMaxLength)),
    );
    canvas.restore();
  }

  @override
  Animation<Offset>? getCancelAnimation(
    AnimationController controller,
    GlobalKey canvasKey,
  ) {
    if ((!isTurnToNext && !(readerController?.isCanGoPre() ?? false)) ||
        (isTurnToNext && !(readerController?.isCanGoNext() ?? false))) {
      return null;
    }
    isConfirmAnimation = false;
    currentAnimationTween ??= Tween(begin: Offset.zero, end: Offset.zero);
    currentAnimation = currentAnimationTween!.animate(controller);
    currentAnimationTween!
      ..begin = mTouch
      ..end = Offset(mCornerX, mCornerY);
    return currentAnimation;
  }

  @override
  Animation<Offset>? getConfirmAnimation(
    AnimationController controller,
    GlobalKey canvasKey,
  ) {
    if ((!isTurnToNext && !(readerController?.isCanGoPre() ?? false)) ||
        (isTurnToNext && !(readerController?.isCanGoNext() ?? false))) {
      return null;
    }
    isConfirmAnimation = true;
    currentAnimationTween ??= Tween(begin: Offset.zero, end: Offset.zero);
    currentAnimation = currentAnimationTween!.animate(controller);

    statusListener ??= (status) {
      if (status == AnimationStatus.completed && isConfirmAnimation) {
        if (isTurnToNext) {
          unawaited(readerController?.nextPage());
        } else {
          unawaited(readerController?.prePage());
        }
        final renderObject = canvasKey.currentContext?.findRenderObject();
        if (renderObject is RenderObject) {
          renderObject.markNeedsPaint();
        }
      }
    };
    if (controller is AnimationControllerWithListenerNumber &&
        !controller.statusListeners.contains(statusListener)) {
      currentAnimation!.addStatusListener(statusListener!);
    }

    currentAnimationTween!
      ..begin = mTouch
      ..end = Offset(
        mCornerX == 0 ? currentSize.width * 3 / 2 : -currentSize.width / 2,
        mCornerY == 0 ? 0 : currentSize.height,
      );
    return currentAnimation;
  }

  @override
  bool isCancelArea() {
    return isTurnToNext
        ? mTouch.dx.abs() > (currentSize.width * 3 / 4)
        : mTouch.dx.abs() < (currentSize.width / 4);
  }

  @override
  bool isConfirmArea() {
    return isTurnToNext
        ? mTouch.dx.abs() < (currentSize.width * 3 / 4)
        : mTouch.dx.abs() > (currentSize.width / 4);
  }
}

class AnimationControllerWithListenerNumber extends AnimationController {
  AnimationControllerWithListenerNumber({
    required super.vsync,
  });

  final ObserverList<AnimationStatusListener> statusListeners =
      ObserverList<AnimationStatusListener>();

  @override
  void addStatusListener(AnimationStatusListener listener) {
    if (!statusListeners.contains(listener)) {
      statusListeners.add(listener);
    }
    super.addStatusListener(listener);
  }

  @override
  void removeStatusListener(AnimationStatusListener listener) {
    statusListeners.remove(listener);
    super.removeStatusListener(listener);
  }
}
