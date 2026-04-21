import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'canvas_reader_engine.dart';
import 'novel_reader_constants.dart';
import 'novel_reader_storage.dart';

class NovelReaderBookshelfPage extends StatefulWidget {
  const NovelReaderBookshelfPage({super.key});

  @override
  State<NovelReaderBookshelfPage> createState() =>
      _NovelReaderBookshelfPageState();
}

class _NovelReaderBookshelfPageState extends State<NovelReaderBookshelfPage> {
  final NovelReaderStorage _storage = NovelReaderStorage();

  List<NovelBookEntry> _books = const <NovelBookEntry>[];
  int _currentIndex = 0;
  bool _loadingShelf = true;
  bool _isDownloading = false;
  bool _isImporting = false;
  double? _progress;
  String? _error;

  NovelBookEntry? get _currentBook =>
      _books.isEmpty ? null : _books[_currentIndex.clamp(0, _books.length - 1)];

  NovelBookEntry? get _previousBook =>
      _currentIndex > 0 ? _books[_currentIndex - 1] : null;

  NovelBookEntry? get _nextBook =>
      _currentIndex + 1 < _books.length ? _books[_currentIndex + 1] : null;

  @override
  void initState() {
    super.initState();
    _refreshState();
  }

  Future<void> _refreshState() async {
    try {
      final books = await _storage.getLibrary();
      final selectedId = await _storage.getSelectedBookId();
      var currentIndex = 0;
      if (selectedId != null) {
        final index = books.indexWhere((book) => book.id == selectedId);
        if (index >= 0) {
          currentIndex = index;
        }
      }
      if (!mounted) return;
      setState(() {
        _books = books;
        _currentIndex = currentIndex;
        _loadingShelf = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingShelf = false;
        _error = '$error';
      });
    }
  }

  Future<void> _selectBook(int index) async {
    if (_books.isEmpty) return;
    final safeIndex = index.clamp(0, _books.length - 1);
    final book = _books[safeIndex];
    await _storage.setSelectedBookId(book.id);
    if (!mounted) return;
    setState(() {
      _currentIndex = safeIndex;
      _error = null;
    });
  }

  Future<void> _downloadCurrentBook({bool redownload = false}) async {
    final book = _currentBook;
    if (book == null || _isDownloading) return;
    setState(() {
      _isDownloading = true;
      _progress = null;
      _error = null;
    });

    try {
      if (redownload) {
        await _storage.deleteBookFile(book);
      }
      await _storage.downloadBook(
        book,
        onProgress: (value) {
          if (!mounted) return;
          setState(() {
            _progress = value;
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _progress = 1;
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

  Future<void> _importTxt() async {
    if (_isImporting) return;
    setState(() {
      _isImporting = true;
      _error = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['txt'],
        allowMultiple: false,
        dialogTitle: 'Import TXT Book',
      );
      if (result == null || result.files.isEmpty) {
        return;
      }
      final picked = result.files.single;
      final path = picked.path;
      if (path == null || path.isEmpty) {
        throw const NovelReaderException(
          'Selected TXT file is unavailable. Please try another file.',
        );
      }
      final imported = await _storage.importBookFromPath(path);
      final books = await _storage.getLibrary();
      final index = books.indexWhere((book) => book.id == imported.id);
      if (!mounted) return;
      setState(() {
        _books = books;
        _currentIndex = index < 0 ? books.length - 1 : index;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<void> _clearProgress() async {
    final book = _currentBook;
    if (book == null) return;
    await _storage.clearProgress(book.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${book.title} progress cleared.')),
    );
  }

  Future<void> _removeCurrentBook() async {
    final book = _currentBook;
    if (book == null || book.isBuiltIn) return;
    await _storage.removeBook(book);
    await _refreshState();
  }

  Future<void> _openReader() async {
    final book = _currentBook;
    if (book == null) return;
    await _storage.setSelectedBookId(book.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => NovelReaderPage(book: book)),
    );
    await _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    final book = _currentBook;
    final progressText = _progress == null
        ? 'Preparing download'
        : 'Downloading ${(_progress! * 100).toStringAsFixed(0)}%';

    if (_loadingShelf) {
      return const Scaffold(
        backgroundColor: Color(0xFFF4EDE3),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (book == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF4EDE3),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: const Text(NovelReaderConstants.title),
        ),
        body: Center(
          child: FilledButton(
            onPressed: _importTxt,
            child: const Text('Import TXT'),
          ),
        ),
      );
    }

    return FutureBuilder<bool>(
      future: _storage.isDownloaded(book),
      builder: (context, snapshot) {
        final isDownloaded = snapshot.data ?? book.source == NovelBookSource.imported;
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
                  Text(
                    'Swipe left or right to switch books. At the edge, swipe again or tap the empty slot to import TXT.',
                    style: TextStyle(
                      color: const Color(0xFF6F5846).withValues(alpha: 0.92),
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Expanded(
                    child: _BookshelfSwipeDeck(
                      key: ValueKey('${book.id}_$_currentIndex'),
                      currentBook: book,
                      previousBook: _previousBook,
                      nextBook: _nextBook,
                      isCurrentDownloaded: isDownloaded,
                      onSwipeToPrevious: _previousBook == null
                          ? null
                          : () => _selectBook(_currentIndex - 1),
                      onSwipeToNext: _nextBook == null
                          ? null
                          : () => _selectBook(_currentIndex + 1),
                      onImportFromLeft: _previousBook == null ? _importTxt : null,
                      onImportFromRight: _nextBook == null ? _importTxt : null,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFF8F3B21),
                        fontSize: 13,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isDownloading || _isImporting
                        ? null
                        : isDownloaded
                        ? _openReader
                        : book.isBuiltIn
                        ? _downloadCurrentBook
                        : null,
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
                          : isDownloaded
                          ? 'Read / Continue'
                          : book.isBuiltIn
                          ? 'Download'
                          : 'Unavailable',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 160,
                        child: OutlinedButton(
                          onPressed: _isImporting || _isDownloading ? null : _importTxt,
                          child: Text(_isImporting ? 'Importing...' : 'Import TXT'),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                    child: OutlinedButton(
                          onPressed: _isDownloading || _isImporting
                              ? null
                              : book.isBuiltIn
                              ? () => _downloadCurrentBook(redownload: true)
                              : _removeCurrentBook,
                          child: Text(book.isBuiltIn ? 'Redownload' : 'Remove Book'),
                        ),
                      ),
                      SizedBox(
                        width: 160,
                        child: OutlinedButton(
                          onPressed: _isDownloading || _isImporting ? null : _clearProgress,
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
      },
    );
  }
}

class NovelReaderPage extends StatefulWidget {
  const NovelReaderPage({super.key, required this.book});

  final NovelBookEntry book;

  @override
  State<NovelReaderPage> createState() => _NovelReaderPageState();
}

class _NovelReaderPageState extends State<NovelReaderPage> {
  final NovelReaderStorage _storage = NovelReaderStorage();

  bool _loadingBook = true;
  bool _chromeVisible = false;
  String? _error;
  NovelCanvasReaderController? _readerController;

  @override
  void initState() {
    super.initState();
    _loadBook();
  }

  @override
  void dispose() {
    _readerController?.dispose();
    super.dispose();
  }

  Future<void> _loadBook() async {
    setState(() {
      _loadingBook = true;
      _error = null;
    });
    try {
      final text = await _storage.readLocalText(widget.book);
      final lastPageIndex = await _storage.getLastPageIndex(widget.book.id);
      final lastPageOffset = await _storage.getLastPageOffset(widget.book.id);
      final savedFontSize = await _storage.getFontSize();
      final savedLineHeight = await _storage.getLineHeight();
      final savedTheme = await _storage.getTheme();

      final controller = NovelCanvasReaderController(
        title: widget.book.title,
        onProgressChanged: (pageIndex, pageStartOffset) async {
          await _storage.setLastPageIndex(widget.book.id, pageIndex);
          await _storage.setLastPageOffset(widget.book.id, pageStartOffset);
        },
      );
      controller.initialize(
        text: text,
        initialPageIndex: lastPageIndex,
        initialPageOffset: lastPageOffset,
      );
      if (savedFontSize != null) {
        await controller.setFontSize(savedFontSize);
      }
      if (savedLineHeight != null) {
        await controller.setLineHeight(savedLineHeight);
      }
      final restoredTheme = _themeFromStorage(savedTheme);
      if (restoredTheme != null) {
        controller.setTheme(restoredTheme);
      }
      controller.addListener(_handleControllerUpdate);

      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _readerController?.removeListener(_handleControllerUpdate);
        _readerController?.dispose();
        _readerController = controller;
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

  void _handleControllerUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  void _toggleChrome() {
    setState(() {
      _chromeVisible = !_chromeVisible;
    });
  }

  NovelReaderTheme? _themeFromStorage(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    for (final theme in NovelReaderTheme.values) {
      if (theme.name == raw) {
        return theme;
      }
    }
    return null;
  }

  Future<void> _openCatalog(NovelCanvasReaderController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8F1E6),
      builder: (context) {
        return SafeArea(
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Text(
                      'Pages',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B3728),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: controller.pageConfigs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final config = controller.pageConfigs[index];
                    final selected = index == controller.currentPageIndex;
                    return Material(
                      color: selected
                          ? const Color(0xFFE8D4BE)
                          : const Color(0xFFFFFBF5),
                      borderRadius: BorderRadius.circular(16),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        title: Text(
                          'Page ${index + 1}',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? const Color(0xFF5F402B)
                                : const Color(0xFF4B3728),
                          ),
                        ),
                        subtitle: Text(
                          'Offset ${config.startOffset}-${config.endOffset}',
                          style: const TextStyle(color: Color(0xFF7A5D47)),
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await controller.goToPage(index);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openSettings(NovelCanvasReaderController controller) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8F1E6),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Settings',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B3728),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ReaderSettingSlider(
                      title: 'Font Size',
                      valueLabel: '${controller.fontSize}',
                      value: controller.fontSize.toDouble(),
                      min: 14,
                      max: 30,
                      divisions: 16,
                      onChanged: (value) async {
                        final nextValue = value.round();
                        await controller.setFontSize(nextValue);
                        await _storage.setFontSize(controller.fontSize);
                        await _storage.setLineHeight(controller.lineHeight);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 10),
                    _ReaderSettingSlider(
                      title: 'Line Height',
                      valueLabel: '${controller.lineHeight}',
                      value: controller.lineHeight.toDouble(),
                      min: (controller.fontSize + 6).toDouble(),
                      max: 46,
                      divisions: math.max(1, 46 - (controller.fontSize + 6)),
                      onChanged: (value) async {
                        final nextValue = value.round();
                        await controller.setLineHeight(nextValue);
                        await _storage.setLineHeight(nextValue);
                        setSheetState(() {});
                      },
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Theme',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF4B3728),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: controller.themes.map((theme) {
                        final selected = controller.theme == theme;
                        return ChoiceChip(
                          label: Text(theme.label),
                          selected: selected,
                          selectedColor: const Color(0xFFE8D4BE),
                          backgroundColor: const Color(0xFFFFFBF5),
                          side: BorderSide(
                            color: selected
                                ? const Color(0xFF8A6246)
                                : const Color(0xFFD7C3AE),
                          ),
                          onSelected: (_) async {
                            controller.setTheme(theme);
                            await _storage.setTheme(theme.name);
                            setSheetState(() {});
                          },
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
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
          title: Text(widget.book.title),
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

    final controller = _readerController;
    if (controller == null) {
      return const Scaffold(
        backgroundColor: Color(0xFFEEE6D8),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFEBE2D4),
      body: Stack(
        children: [
          SafeArea(
            child: Padding(
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
                    child: NovelCanvasReaderView(
                      controller: controller,
                      onToggleChrome: _toggleChrome,
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: 0,
                    right: 0,
                    top: _chromeVisible ? 0 : -96,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _chromeVisible ? 1 : 0,
                      child: _ReaderTopBar(
                        title: widget.book.title,
                        pageLabel:
                            '${controller.currentDisplayPage} / ${controller.totalDisplayPages}',
                      ),
                    ),
                  ),
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    left: 16,
                    right: 16,
                    bottom: _chromeVisible ? 16 : -120,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 180),
                      opacity: _chromeVisible ? 1 : 0,
                      child: _ReaderBottomBar(
                        canGoPrevious: controller.isCanGoPre(),
                        canGoNext: controller.isCanGoNext(),
                        currentPage: controller.currentDisplayPage,
                        totalPages: controller.totalDisplayPages,
                        pageLabel:
                            '${controller.currentDisplayPage} / ${controller.totalDisplayPages}',
                        onCatalog: () => _openCatalog(controller),
                        onSettings: () => _openSettings(controller),
                        onSeek: (page) => controller.goToPage(page),
                        onPrevious: controller.isCanGoPre()
                            ? () async => controller.prePage()
                            : null,
                        onNext: controller.isCanGoNext()
                            ? () async => controller.nextPage()
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookshelfSwipeDeck extends StatefulWidget {
  const _BookshelfSwipeDeck({
    super.key,
    required this.currentBook,
    required this.previousBook,
    required this.nextBook,
    required this.isCurrentDownloaded,
    required this.onSwipeToPrevious,
    required this.onSwipeToNext,
    required this.onImportFromLeft,
    required this.onImportFromRight,
  });

  final NovelBookEntry currentBook;
  final NovelBookEntry? previousBook;
  final NovelBookEntry? nextBook;
  final bool isCurrentDownloaded;
  final Future<void> Function()? onSwipeToPrevious;
  final Future<void> Function()? onSwipeToNext;
  final Future<void> Function()? onImportFromLeft;
  final Future<void> Function()? onImportFromRight;

  @override
  State<_BookshelfSwipeDeck> createState() => _BookshelfSwipeDeckState();
}

class _BookshelfSwipeDeckState extends State<_BookshelfSwipeDeck>
    with SingleTickerProviderStateMixin {
  static const double _swipeThreshold = 110;

  late final AnimationController _offsetController;
  double _offsetX = 0;
  bool _animating = false;

  @override
  void initState() {
    super.initState();
    _offsetController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        setState(() {
          _offsetX = _offsetController.value;
        });
      });
  }

  @override
  void dispose() {
    _offsetController.dispose();
    super.dispose();
  }

  Future<void> _handlePanEnd(double velocityX, double width) async {
    final canGoPrevious = widget.onSwipeToPrevious != null;
    final canGoNext = widget.onSwipeToNext != null;
    final shouldGoPrevious =
        _offsetX > _swipeThreshold || (velocityX > 900 && _offsetX > 0);
    final shouldGoNext =
        _offsetX < -_swipeThreshold || (velocityX < -900 && _offsetX < 0);

    if (shouldGoPrevious) {
      await _animateOut(width);
      if (canGoPrevious) {
        await widget.onSwipeToPrevious!.call();
      } else if (widget.onImportFromLeft != null) {
        await widget.onImportFromLeft!.call();
      }
      _resetOffset();
      return;
    }

    if (shouldGoNext) {
      await _animateOut(-width);
      if (canGoNext) {
        await widget.onSwipeToNext!.call();
      } else if (widget.onImportFromRight != null) {
        await widget.onImportFromRight!.call();
      }
      _resetOffset();
      return;
    }

    await _animateSpringBack();
  }

  Future<void> _animateOut(double target) async {
    _animating = true;
    await _offsetController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeIn,
    );
    _animating = false;
  }

  Future<void> _animateSpringBack() async {
    _animating = true;
    final spring = SpringDescription(
      mass: 1,
      stiffness: 320,
      damping: 26,
    );
    await _offsetController.animateWith(
      SpringSimulation(spring, _offsetController.value, 0, 0),
    );
    _animating = false;
  }

  void _resetOffset() {
    _offsetController.value = 0;
    _offsetX = 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final progress = (_offsetX.abs() / width).clamp(0.0, 1.0);
        final movingRight = _offsetX >= 0;
        final leftCard = widget.previousBook;
        final rightCard = widget.nextBook;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: Row(
                children: [
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _SideBookCard(
                        alignment: Alignment.centerLeft,
                        visibleProgress: movingRight ? progress : 0,
                        title: leftCard?.title ?? 'Import TXT',
                        subtitle: leftCard == null
                            ? 'No book on the left'
                            : leftCard.isBuiltIn
                            ? 'Built-in novel'
                            : 'Imported TXT',
                        accent: leftCard == null
                            ? const Color(0xFF2F6A55)
                            : const Color(0xFF83553A),
                        icon: leftCard == null
                            ? Icons.upload_file_rounded
                            : Icons.menu_book_rounded,
                        isPlaceholder: leftCard == null,
                        onTap: leftCard == null ? widget.onImportFromLeft : null,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _SideBookCard(
                        alignment: Alignment.centerRight,
                        visibleProgress: movingRight ? 0 : progress,
                        title: rightCard?.title ?? 'Import TXT',
                        subtitle: rightCard == null
                            ? 'No book on the right'
                            : rightCard.isBuiltIn
                            ? 'Built-in novel'
                            : 'Imported TXT',
                        accent: rightCard == null
                            ? const Color(0xFF2F6A55)
                            : const Color(0xFF83553A),
                        icon: rightCard == null
                            ? Icons.upload_file_rounded
                            : Icons.menu_book_rounded,
                        isPlaceholder: rightCard == null,
                        onTap: rightCard == null ? widget.onImportFromRight : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Center(
              child: GestureDetector(
                onPanUpdate: _animating
                    ? null
                    : (details) {
                        _offsetController.value += details.delta.dx;
                      },
                onPanEnd: _animating
                    ? null
                    : (details) => _handlePanEnd(
                        details.velocity.pixelsPerSecond.dx,
                        width,
                      ),
                onPanCancel: _animating ? null : _animateSpringBack,
                child: Transform.translate(
                  offset: Offset(_offsetX, 0),
                  child: Transform.rotate(
                    angle: (_offsetX / width) * 0.12,
                    child: Transform.scale(
                      scale: 1 - (progress * 0.04),
                      child: _CurrentBookCard(
                        book: widget.currentBook,
                        isDownloaded: widget.isCurrentDownloaded,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _CurrentBookCard extends StatelessWidget {
  const _CurrentBookCard({
    required this.book,
    required this.isDownloaded,
  });

  final NovelBookEntry book;
  final bool isDownloaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
            color: Colors.black.withValues(alpha: 0.14),
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
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    book.isBuiltIn
                        ? Icons.auto_stories_rounded
                        : Icons.description_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    book.isBuiltIn ? 'Built-in' : 'Imported TXT',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              book.title,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              isDownloaded
                  ? 'Ready to read. Swipe sideways to move across your shelf.'
                  : 'This book is on the shelf but still needs downloading.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.86),
                fontSize: 15,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideBookCard extends StatelessWidget {
  const _SideBookCard({
    required this.alignment,
    required this.visibleProgress,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.isPlaceholder,
    required this.onTap,
  });

  final Alignment alignment;
  final double visibleProgress;
  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final bool isPlaceholder;
  final Future<void> Function()? onTap;

  @override
  Widget build(BuildContext context) {
    final opacity = (0.25 + (visibleProgress * 0.75)).clamp(0.25, 1.0);
    final translateX = alignment == Alignment.centerLeft
        ? 20 - (visibleProgress * 20)
        : -20 + (visibleProgress * 20);

    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(translateX, 0),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 170),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap == null ? null : () => onTap!.call(),
              child: Ink(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: isPlaceholder
                      ? const Color(0xFFD7E5DC)
                      : const Color(0xFFE9D7C5),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.30),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: accent, size: 28),
                    const SizedBox(height: 12),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent.withValues(alpha: 0.86),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReaderTopBar extends StatelessWidget {
  const _ReaderTopBar({
    required this.title,
    required this.pageLabel,
  });

  final String title;
  final String pageLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF6EEE1).withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              IconButton(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF4B3728),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                pageLabel,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF7A5D47),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReaderBottomBar extends StatelessWidget {
  const _ReaderBottomBar({
    required this.canGoPrevious,
    required this.canGoNext,
    required this.currentPage,
    required this.totalPages,
    required this.pageLabel,
    required this.onCatalog,
    required this.onSettings,
    required this.onSeek,
    required this.onPrevious,
    required this.onNext,
  });

  final bool canGoPrevious;
  final bool canGoNext;
  final int currentPage;
  final int totalPages;
  final String pageLabel;
  final VoidCallback onCatalog;
  final VoidCallback onSettings;
  final ValueChanged<int> onSeek;
  final Future<void> Function()? onPrevious;
  final Future<void> Function()? onNext;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFBF5EA).withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  onPressed: onCatalog,
                  icon: const Icon(Icons.list_alt_rounded),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    pageLabel,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF6C523F),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  onPressed: onSettings,
                  icon: const Icon(Icons.tune_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF7A5339),
                thumbColor: const Color(0xFF7A5339),
                inactiveTrackColor: const Color(0xFFD8C5B1),
                overlayColor: const Color(0x337A5339),
              ),
              child: Slider(
                value: totalPages <= 1
                    ? 0
                    : (currentPage - 1).clamp(0, totalPages - 1).toDouble(),
                min: 0,
                max: totalPages <= 1 ? 1 : (totalPages - 1).toDouble(),
                divisions: totalPages <= 1 ? 1 : totalPages - 1,
                onChanged: totalPages <= 1
                    ? null
                    : (value) => onSeek(value.round()),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: canGoPrevious ? () => onPrevious?.call() : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Previous'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: canGoNext ? () => onNext?.call() : null,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: const Color(0xFF7A5339),
                    ),
                    child: const Text('Next'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReaderSettingSlider extends StatelessWidget {
  const _ReaderSettingSlider({
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBF5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF4B3728),
                    ),
                  ),
                ),
                Text(
                  valueLabel,
                  style: const TextStyle(
                    color: Color(0xFF7A5D47),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF7A5339),
                thumbColor: const Color(0xFF7A5339),
                inactiveTrackColor: const Color(0xFFD8C5B1),
                overlayColor: const Color(0x337A5339),
              ),
              child: Slider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
