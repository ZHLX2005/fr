import 'dart:math' as math;

import 'package:flutter/material.dart';

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
        : 'Downloading ${(_progress! * 100).toStringAsFixed(0)}%';

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
      final text = await _storage.readLocalText();
      final lastPageIndex = await _storage.getLastPageIndex();
      final lastPageOffset = await _storage.getLastPageOffset();
      final savedFontSize = await _storage.getFontSize();
      final savedLineHeight = await _storage.getLineHeight();
      final savedTheme = await _storage.getTheme();

      final controller = NovelCanvasReaderController(
        title: NovelReaderConstants.bookTitle,
        onProgressChanged: (pageIndex, pageStartOffset) async {
          await _storage.setLastPageIndex(pageIndex);
          await _storage.setLastPageOffset(pageStartOffset);
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
                        title: NovelReaderConstants.bookTitle,
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
