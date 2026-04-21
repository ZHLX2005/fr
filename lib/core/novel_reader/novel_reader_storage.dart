import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'novel_reader_constants.dart';

class DownloadResult {
  const DownloadResult({required this.text, required this.file});

  final String text;
  final File file;
}

enum NovelBookSource { builtIn, imported }

class NovelBookEntry {
  const NovelBookEntry({
    required this.id,
    required this.title,
    required this.fileName,
    required this.source,
    this.remoteUrl,
    this.importedAt,
  });

  final String id;
  final String title;
  final String fileName;
  final NovelBookSource source;
  final String? remoteUrl;
  final int? importedAt;

  bool get isBuiltIn => source == NovelBookSource.builtIn;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'fileName': fileName,
      'source': source.name,
      'remoteUrl': remoteUrl,
      'importedAt': importedAt,
    };
  }

  factory NovelBookEntry.fromJson(Map<String, dynamic> json) {
    final sourceName = json['source'] as String? ?? NovelBookSource.imported.name;
    final source = NovelBookSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => NovelBookSource.imported,
    );
    return NovelBookEntry(
      id: json['id'] as String,
      title: json['title'] as String,
      fileName: json['fileName'] as String,
      source: source,
      remoteUrl: json['remoteUrl'] as String?,
      importedAt: json['importedAt'] as int?,
    );
  }
}

class NovelReaderStorage {
  static const Uuid _uuid = Uuid();

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

  Future<List<NovelBookEntry>> getLibrary() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(NovelReaderConstants.libraryKey);
    final books = <NovelBookEntry>[];

    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as List<dynamic>;
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            books.add(NovelBookEntry.fromJson(item));
          } else if (item is Map) {
            books.add(
              NovelBookEntry.fromJson(Map<String, dynamic>.from(item)),
            );
          }
        }
      } catch (_) {
        // Ignore invalid persisted payload and rebuild from defaults.
      }
    }

    final builtIn = _builtInEntry;
    books.removeWhere((book) => book.id == builtIn.id);
    final normalized = <NovelBookEntry>[builtIn, ...books];
    await _saveLibrary(normalized);
    return normalized;
  }

  Future<void> _saveLibrary(List<NovelBookEntry> books) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = jsonEncode(books.map((book) => book.toJson()).toList());
    await prefs.setString(NovelReaderConstants.libraryKey, raw);
  }

  NovelBookEntry get _builtInEntry => const NovelBookEntry(
    id: NovelReaderConstants.builtInBookId,
    title: NovelReaderConstants.bookTitle,
    fileName: NovelReaderConstants.builtInFileName,
    source: NovelBookSource.builtIn,
    remoteUrl: NovelReaderConstants.remoteUrl,
  );

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

    final selectedId = prefs.getString(NovelReaderConstants.selectedBookKey);
    if (selectedId == book.id) {
      await prefs.setString(
        NovelReaderConstants.selectedBookKey,
        NovelReaderConstants.builtInBookId,
      );
    }
  }

  Future<void> deleteBookFile(NovelBookEntry book) async {
    final file = await getBookFile(book);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> getLastPageIndex(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressKey(bookId)) ?? 0;
  }

  Future<int?> getLastPageOffset(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressOffsetKey(bookId));
  }

  Future<void> setLastPageIndex(String bookId, int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressKey(bookId), index);
  }

  Future<void> setLastPageOffset(String bookId, int offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressOffsetKey(bookId), offset);
  }

  Future<void> clearProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(NovelReaderConstants.progressKey(bookId));
    await prefs.remove(NovelReaderConstants.progressOffsetKey(bookId));
  }

  Future<String?> getSelectedBookId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(NovelReaderConstants.selectedBookKey);
  }

  Future<void> setSelectedBookId(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NovelReaderConstants.selectedBookKey, bookId);
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

  Future<void> setFontSize(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.fontSizeKey, value);
  }

  Future<void> setLineHeight(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.lineHeightKey, value);
  }

  Future<void> setTheme(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(NovelReaderConstants.themeKey, value);
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
