import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'novel_reader_constants.dart';

class DownloadResult {
  const DownloadResult({required this.text, required this.file});

  final String text;
  final File file;
}

class NovelReaderStorage {
  Future<File> getBookFile() async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory(
      '${dir.path}${Platform.pathSeparator}${NovelReaderConstants.localDirectory}',
    );
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    return File(
      '${folder.path}${Platform.pathSeparator}${NovelReaderConstants.localFileName}',
    );
  }

  Future<bool> isDownloaded() async {
    final file = await getBookFile();
    if (!await file.exists()) return false;
    final length = await file.length();
    return length > 0;
  }

  Future<String> readLocalText() async {
    final file = await getBookFile();
    if (!await file.exists()) {
      throw const NovelReaderException('Book has not been downloaded yet.');
    }
    final text = await file.readAsString();
    final normalized = _normalize(text);
    if (normalized.trim().isEmpty) {
      throw const NovelReaderException('Local book file is empty or invalid.');
    }
    return normalized;
  }

  Future<DownloadResult> downloadBook({
    void Function(double progress)? onProgress,
  }) async {
    final file = await getBookFile();
    final tempFile = File('${file.path}.part');
    http.StreamedResponse? response;
    IOSink? sink;

    try {
      final request = http.Request(
        'GET',
        Uri.parse(NovelReaderConstants.remoteUrl),
      );
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
        throw const NovelReaderException('Downloaded book is empty.');
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

  Future<void> deleteBookFile() async {
    final file = await getBookFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<int> getLastPageIndex() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressKey) ?? 0;
  }

  Future<int?> getLastPageOffset() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(NovelReaderConstants.progressOffsetKey);
  }

  Future<void> setLastPageIndex(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressKey, index);
  }

  Future<void> setLastPageOffset(int offset) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(NovelReaderConstants.progressOffsetKey, offset);
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

  Future<void> clearProgress() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(NovelReaderConstants.progressKey);
    await prefs.remove(NovelReaderConstants.progressOffsetKey);
  }

  String _normalize(String text) {
    return text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  }
}

class NovelReaderException implements Exception {
  const NovelReaderException(this.message);

  final String message;

  @override
  String toString() => message;
}
