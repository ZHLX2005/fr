import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'novel_paginator.dart';
import 'novel_reader_constants.dart';
import 'novel_reader_storage.dart';
import 'page_curl_view.dart';

class NovelReaderBookshelfPage extends StatefulWidget {
  const NovelReaderBookshelfPage({super.key});

  @override
  State<NovelReaderBookshelfPage> createState() =>
      _NovelReaderBookshelfPageState();
}

class _NovelReaderBookshelfPageState extends State<NovelReaderBookshelfPage> {
  final NovelReaderStorage _storage = NovelReaderStorage();

  bool _isDownloaded = false;
  bool _isDownloading = false;
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    try {
      final isDownloaded = await _storage.isDownloaded();
      if (!mounted) return;
      setState(() {
        _isDownloaded = isDownloaded;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    }
  }

  Future<void> _downloadBook({bool redownload = false}) async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _progress = null;
      _error = null;
    });

    try {
      if (redownload) {
        await _storage.deleteBookFile();
      }
      await _storage.downloadBook(
        onProgress: (value) {
          if (!mounted) return;
          setState(() {
            _progress = value;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _isDownloaded = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _clearProgress() async {
    await _storage.clearProgress();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Reading progress cleared.')));
  }

  Future<void> _openReader() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const NovelReaderPage()));
    await _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    final progressText = _progress == null
        ? 'Preparing download'
        : 'Downloading ${(math.max(0, _progress!) * 100).toStringAsFixed(0)}%';

    return Scaffold(
      backgroundColor: const Color(0xFFF4EDE3),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(NovelReaderConstants.title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFFDFB982),
                        Color(0xFFB96F42),
                        Color(0xFF6E3D27),
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 28,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.auto_stories_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const Spacer(),
                        const Text(
                          NovelReaderConstants.bookTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 30,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.4,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _isDownloaded
                              ? 'Downloaded to Documents and ready offline.'
                              : 'One fixed TXT novel for pagination and curl demo.',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontSize: 15,
                            height: 1.45,
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 16),
                          Text(
                            _error!,
                            style: const TextStyle(
                              color: Color(0xFFFFE0D6),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _isDownloading
                    ? null
                    : _isDownloaded
                    ? _openReader
                    : _downloadBook,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF714B35),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: Text(
                  _isDownloading
                      ? progressText
                      : _isDownloaded
                      ? 'Read / Continue'
                      : 'Download',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isDownloading
                          ? null
                          : () => _downloadBook(redownload: true),
                      child: const Text('Redownload'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isDownloading ? null : _clearProgress,
                      child: const Text('Clear progress'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key});

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  static const EdgeInsets _pagePadding = EdgeInsets.fromLTRB(24, 28, 24, 28);
  static const double _fontSize = 18;
  static const double _lineHeight = 1.72;

  final NovelReaderStorage _storage = NovelReaderStorage();
  final NovelPaginator _paginator = const NovelPaginator();

  String? _bookText;
  PaginationLayout? _layout;
  NovelPage? _currentPage;
  NovelPage? _nextPage;
  NovelPage? _previousPage;
  int _currentPageIndex = 0;
  int? _savedPageOffset;
  bool _loadingBook = true;
  bool _paginating = false;
  String? _error;
  Size? _requestedPageSize;
  int _paginationRequestId = 0;

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  Future<void> _loadBook() async {
    setState(() {
      _loadingBook = true;
      _error = null;
    });
    try {
      final text = await _storage.readLocalText();
      final lastPageIndex = await _storage.getLastPageIndex();
      final lastPageOffset = await _storage.getLastPageOffset();
      if (!mounted) return;
      setState(() {
        _bookText = text;
        _currentPageIndex = lastPageIndex;
        _savedPageOffset = lastPageOffset;
        _loadingBook = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingBook = false;
        _error = '$error';
      });
    }
  }

  Future<void> _ensurePagination(Size size) async {
    final text = _bookText;
    if (text == null) return;

    final layout = PaginationLayout(
      size: size,
      padding: _pagePadding,
      fontSize: _fontSize,
      lineHeight: _fontSize * _lineHeight,
    );
    if (_layout?.isCloseTo(layout) ?? false) return;

    final previousPage = _currentPage;
    final anchorOffset = previousPage?.start ?? _savedPageOffset ?? 0;

    setState(() {
      _paginating = true;
    });

    final requestId = ++_paginationRequestId;
    await Future<void>.delayed(Duration.zero);
    final currentPage = await _paginator.pageAtOffset(
      text: text,
      layout: layout,
      textStyle: _pageTextStyle,
      startOffset: anchorOffset,
    );
    final previousWindowPage = await _paginator.previousPage(
      text: text,
      layout: layout,
      textStyle: _pageTextStyle,
      currentPage: currentPage,
    );
    final nextWindowPage = await _paginator.nextPage(
      text: text,
      layout: layout,
      textStyle: _pageTextStyle,
      currentPage: currentPage,
    );

    if (!mounted || requestId != _paginationRequestId) return;

    setState(() {
      _layout = layout;
      _currentPage = currentPage;
      _previousPage = previousWindowPage;
      _nextPage = nextWindowPage;
      _paginating = false;
    });
  }

  void _schedulePaginationForSize(Size size) {
    if (_paginating) return;
    final currentRequest = _requestedPageSize;
    if (currentRequest != null &&
        (currentRequest.width - size.width).abs() < 0.5 &&
        (currentRequest.height - size.height).abs() < 0.5) {
      return;
    }
    _requestedPageSize = size;
    Future<void>(() async {
      if (!mounted) return;
      final request = _requestedPageSize;
      if (request == null) return;
      await _ensurePagination(request);
    });
  }

  TextStyle get _pageTextStyle => const TextStyle(
    fontSize: _fontSize,
    height: _lineHeight,
    color: Color(0xFF2E231B),
    letterSpacing: 0.15,
  );

  Future<void> _handlePageTurn(PageTurnRequest request) async {
    if (!request.completed) return;
    final text = _bookText;
    final layout = _layout;
    final currentPage = _currentPage;
    if (text == null || layout == null || currentPage == null) return;

    if (request.direction == PageTurnDirection.next) {
      final target = _nextPage;
      if (target == null) return;
      setState(() {
        _previousPage = currentPage;
        _currentPage = target;
        _nextPage = null;
        _currentPageIndex += 1;
      });
      await Future<void>.delayed(Duration.zero);
      final following = await _paginator.nextPage(
        text: text,
        layout: layout,
        textStyle: _pageTextStyle,
        currentPage: target,
      );
      if (!mounted || _currentPage?.start != target.start) return;
      setState(() {
        _nextPage = following;
      });
      await _storage.setLastPageIndex(_currentPageIndex);
      await _storage.setLastPageOffset(target.start);
      return;
    }

    final target = _previousPage;
    if (target == null) return;
    setState(() {
      _nextPage = currentPage;
      _currentPage = target;
      _previousPage = null;
      _currentPageIndex = math.max(0, _currentPageIndex - 1);
    });
    await Future<void>.delayed(Duration.zero);
    final leading = await _paginator.previousPage(
      text: text,
      layout: layout,
      textStyle: _pageTextStyle,
      currentPage: target,
    );
    if (!mounted || _currentPage?.start != target.start) return;
    setState(() {
      _previousPage = leading;
    });
    await _storage.setLastPageIndex(_currentPageIndex);
    await _storage.setLastPageOffset(target.start);
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingBook) {
      return const Scaffold(
        backgroundColor: Color(0xFFEEE6D8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: const Color(0xFFEEE6D8),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(NovelReaderConstants.bookTitle),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton(onPressed: _loadBook, child: const Text('Retry')),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEBE2D4),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          NovelReaderConstants.bookTitle,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text(
                '${_currentPageIndex + 1} / --',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF634B38),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final pageSize = Size(
              constraints.maxWidth - 28,
              constraints.maxHeight - 24,
            );
            _schedulePaginationForSize(pageSize);

            final currentPage = _currentPage;
            if (_paginating || currentPage == null) {
              return const Center(child: CircularProgressIndicator());
            }

            return Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFFF8F1E6), Color(0xFFE4D5C0)],
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 24,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: PageCurlView(
                      canTurnNext: _nextPage != null,
                      canTurnPrevious: _previousPage != null,
                      currentPage: _ReaderPaper(
                        page: currentPage,
                        style: _pageTextStyle,
                        padding: _pagePadding,
                      ),
                      targetPage: _ReaderPaper(
                        page: _nextPage ?? _previousPage ?? currentPage,
                        style: _pageTextStyle,
                        padding: _pagePadding,
                      ),
                      onTurnFinished: _handlePageTurn,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ReaderPaper extends StatelessWidget {
  const _ReaderPaper({
    required this.page,
    required this.style,
    required this.padding,
  });

  final NovelPage page;
  final TextStyle style;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF9F1E4),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD9C4AE)),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: 0.28),
                    Colors.transparent,
                    Colors.brown.withValues(alpha: 0.03),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: padding,
            child: Text(page.text.trimLeft(), style: style),
          ),
        ],
      ),
    );
  }
}
