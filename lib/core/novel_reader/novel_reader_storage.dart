import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'novel_reader_catalog.dart';
import 'novel_reader_constants.dart';
import 'novel_reader_models.dart';
import 'novel_reader_sync_hook.dart';

export 'novel_reader_models.dart';

class DownloadResult {
  const DownloadResult({required this.text, required this.file});

  final String text;
  final File file;
}

class NovelReaderStorage {
  NovelReaderStorage({NovelReaderSyncHook? sync}) : _sync = sync;

  static const Uuid _uuid = Uuid();

  NovelReaderSyncHook? _sync;

  /// Optional personal-cloud sync (set after construction to avoid cycles).
  set sync(NovelReaderSyncHook? value) => _sync = value;

  NovelReaderSyncHook? get sync => _sync;

  Future<Directory> _getBooksDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${dir.path}${Platform.pathSeparator}${NovelReaderConstants.localDirectory}',
    );
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return folder;
  }

  Future<File> getBookFile(NovelBookEntry book) async {
    final folder = await _getBooksDirectory();
    return File('${folder.path}${Platform.pathSeparator}${book.fileName}');
  }

  /// Load shelf. When [mergeCatalog] is true, refresh built-ins from public KV.
  Future<List<NovelBookEntry>> getLibrary({bool mergeCatalog = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NovelReaderConstants.libraryKey);
    final local = <NovelBookEntry>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        local.addAll(NovelBookEntry.decodeLibraryJson(raw));
      } catch (_) {
        // Ignore invalid persisted payload and rebuild from defaults.
      }
    }

    final imported =
        local.where((b) => b.source == NovelBookSource.imported).toList();

    List<NovelBookEntry> builtIns;
    if (mergeCatalog) {
      final catalog = await fetchNovelCatalog();
      builtIns = catalog.isNotEmpty ? catalog : <NovelBookEntry>[novelFallbackBuiltIn()];
    } else {
      final existingBuiltIns =
          local.where((b) => b.source == NovelBookSource.builtIn).toList();
      builtIns = existingBuiltIns.isNotEmpty
          ? existingBuiltIns
          : <NovelBookEntry>[novelFallbackBuiltIn()];
    }

    final byId = <String, NovelBookEntry>{
      for (final b in builtIns) b.id: b,
      for (final b in imported) b.id: b,
    };
    // Preserve built-in order from catalog, then imports.
    final normalized = <NovelBookEntry>[
      ...builtIns,
      ...imported.where((b) => !builtIns.any((c) => c.id == b.id)),
    ];
    // Drop accidental dupes while keeping order.
    final seen = <String>{};
    final deduped = <NovelBookEntry>[];
    for (final b in normalized) {
      if (seen.add(b.id)) deduped.add(byId[b.id] ?? b);
    }

    await _saveLibrary(deduped, sync: false);
    return deduped;
  }

  /// Replace local library JSON without catalog merge (used by sync pull).
  Future<void> replaceLibrary(List<NovelBookEntry> books) async {
    await _saveLibrary(books, sync: false);
  }

  Future<void> _saveLibrary(
    List<NovelBookEntry> books, {
    bool sync = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(books.map((book) => book.toJson()).toList());
    await prefs.setString(NovelReaderConstants.libraryKey, raw);
    if (sync) {
      _sync?.onLocalChanged(NovelSyncTopic.library);
    }
  }

  Future<bool> isDownloaded(NovelBookEntry book) async {
    final file = await getBookFile(book);
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 0;
  }

  Future<String> readLocalText(NovelBookEntry book) async {
    final file = await getBookFile(book);
    if (!await file.exists()) {
      throw NovelReaderException('${book.title} has not been downloaded yet.');
    }
    final text = await file.readAsString();
    final normalized = _normalize(text);
    if (normalized.trim().isEmpty) {
      throw NovelReaderException('${book.title} is empty or invalid.');
    }
    return normalized;
  }

  Future<DownloadResult> downloadBook(
    NovelBookEntry book, {
    void Function(double progress)? onProgress,
  }) async {
    final remoteUrl = book.remoteUrl;
    if (remoteUrl == null || remoteUrl.isEmpty) {
      throw NovelReaderException('${book.title} does not support redownload.');
    }

    final file = await getBookFile(book);
    final tempFile = File('${file.path}.part');
    http.StreamedResponse? response;
    IOSink? sink;

    try {
      final request = http.Request('GET', Uri.parse(remoteUrl));
      response = await request.send();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw NovelReaderException(
          'Download failed with status ${response.statusCode}.',
        );
      }

      sink = tempFile.openWrite();
      final bytes = <int>[];
      final total = response.contentLength;
      var received = 0;

      await for (final chunk in response.stream) {
        bytes.addAll(chunk);
        sink.add(chunk);
        received += chunk.length;
        if (total != null && total > 0) {
          onProgress?.call(received / total);
        }
      }

      await sink.flush();
      await sink.close();
      sink = null;

      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);

      final text = _normalize(String.fromCharCodes(bytes));
      if (text.trim().isEmpty) {
        throw NovelReaderException('Downloaded book is empty.');
      }
      onProgress?.call(1);
      return DownloadResult(text: text, file: file);
    } on SocketException {
      throw const NovelReaderException('Network unavailable. Please retry.');
    } on TimeoutException {
      throw const NovelReaderException('Download timed out. Please retry.');
    } finally {
      await sink?.close();
      if (await tempFile.exists()) {
        final hasTarget = await file.exists();
        if (!hasTarget) {
          await tempFile.delete();
        }
      }
    }
  }

  Future<NovelBookEntry> importBookFromPath(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw const NovelReaderException('Selected TXT file is unavailable.');
    }

    final rawText = await sourceFile.readAsString();
    final normalized = _normalize(rawText);
    if (normalized.trim().isEmpty) {
      throw const NovelReaderException('Selected TXT file is empty.');
    }

    final sourceName = sourceFile.uri.pathSegments.isEmpty
        ? 'Imported Book'
        : sourceFile.uri.pathSegments.last;
    final title = _guessTitle(sourceName);
    final id = _uuid.v4();
    final safeName = _safeFileName(title);
    final fileName = '${safeName}_$id.txt';
    final targetFile = await getBookFile(
      NovelBookEntry(
        id: id,
        title: title,
        fileName: fileName,
        source: NovelBookSource.imported,
      ),
    );

    await targetFile.writeAsString(normalized, flush: true);

    final entry = NovelBookEntry(
      id: id,
      title: title,
      fileName: fileName,
      source: NovelBookSource.imported,
      importedAt: DateTime.now().millisecondsSinceEpoch,
    );

    final books = await getLibrary();
    await _saveLibrary(<NovelBookEntry>[...books, entry]);
    await setSelectedBookId(entry.id);
    return entry;
  }

  Future<void> removeBook(NovelBookEntry book) async {
    if (book.isBuiltIn) {
      throw const NovelReaderException('Built-in book cannot be removed.');
    }
    final books = await getLibrary();
    books.removeWhere((entry) => entry.id == book.id);
    await _saveLibrary(books);

    final file = await getBookFile(book);
    if (await file.exists()) {
      await file.delete();
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(NovelReaderConstants.progressKey(book.id));
    await prefs.remove(NovelReaderConstants.progressOffsetKey(book.id));
    await prefs.remove(_progressTsKey(book.id));

    final selectedId = prefs.getString(NovelReaderConstants.selectedBookKey);
    if (selectedId == book.id) {
      await setSelectedBookId(
        books.isNotEmpty
            ? books.first.id
            : NovelReaderConstants.builtInBookId,
      );
    }
  }

  Future<void> deleteBookFile(NovelBookEntry book) async {
    final file = await getBookFile(book);
    if (await file.exists()) {
      await file.delete();
    }
  }

  String _progressTsKey(String bookId) =>
      '${NovelReaderConstants.progressKeyPrefix}.ts.$bookId';

  Future<int?> getProgressTimestamp(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_progressTsKey(bookId));
  }

  Future<int> getLastPageIndex(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressKey(bookId)) ?? 0;
  }

  Future<int?> getLastPageOffset(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressOffsetKey(bookId));
  }

  Future<void> setLastPageIndex(
    String bookId,
    int index, {
    bool sync = true,
    int? timestampMs,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressKey(bookId), index);
    await prefs.setInt(
      _progressTsKey(bookId),
      timestampMs ?? DateTime.now().millisecondsSinceEpoch,
    );
    if (sync) {
      _sync?.onLocalChanged(NovelSyncTopic.progress, bookId: bookId);
    }
  }

  Future<void> setLastPageOffset(
    String bookId,
    int offset, {
    bool sync = true,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressOffsetKey(bookId), offset);
    if (sync) {
      _sync?.onLocalChanged(NovelSyncTopic.progress, bookId: bookId);
    }
  }

  Future<void> clearProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(NovelReaderConstants.progressKey(bookId));
    await prefs.remove(NovelReaderConstants.progressOffsetKey(bookId));
    await prefs.remove(_progressTsKey(bookId));
    _sync?.onLocalChanged(NovelSyncTopic.progress, bookId: bookId);
  }

  Future<String?> getSelectedBookId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NovelReaderConstants.selectedBookKey);
  }

  Future<void> setSelectedBookId(String bookId, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NovelReaderConstants.selectedBookKey, bookId);
    if (sync) {
      _sync?.onLocalChanged(NovelSyncTopic.selected);
    }
  }

  Future<int?> getFontSize() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.fontSizeKey);
  }

  Future<int?> getLineHeight() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.lineHeightKey);
  }

  Future<String?> getTheme() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NovelReaderConstants.themeKey);
  }

  Future<void> setFontSize(int value, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.fontSizeKey, value);
    if (sync) _sync?.onLocalChanged(NovelSyncTopic.prefs);
  }

  Future<void> setLineHeight(int value, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.lineHeightKey, value);
    if (sync) _sync?.onLocalChanged(NovelSyncTopic.prefs);
  }

  Future<void> setTheme(String value, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NovelReaderConstants.themeKey, value);
    if (sync) _sync?.onLocalChanged(NovelSyncTopic.prefs);
  }

  Future<bool?> getVolumeKeyTurnEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(NovelReaderConstants.volumeKeyTurnKey);
  }

  Future<void> setVolumeKeyTurnEnabled(bool value, {bool sync = true}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(NovelReaderConstants.volumeKeyTurnKey, value);
    if (sync) _sync?.onLocalChanged(NovelSyncTopic.prefs);
  }

  String _normalize(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }

  String _guessTitle(String sourceName) {
    final normalized = sourceName.trim();
    if (normalized.isEmpty) return 'Imported Book';
    final lastDot = normalized.lastIndexOf('.');
    if (lastDot <= 0) return normalized;
    return normalized.substring(0, lastDot);
  }

  String _safeFileName(String input) {
    final normalized = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return normalized.isEmpty ? 'book' : normalized;
  }
}

class NovelReaderException implements Exception {
  const NovelReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}
