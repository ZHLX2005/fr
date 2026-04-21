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
                '${controller.currentDisplayPage} / ${controller.totalDisplayPages}',
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
                child: NovelCanvasReaderView(controller: controller),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
