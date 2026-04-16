import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

class LineCacheManager {
  static const String _cacheDir = 'line_cache';

  String? _basePath;

  Future<String> get basePath async {
    if (_basePath != null) return _basePath!;
    final dir = await getApplicationDocumentsDirectory();
    _basePath = '${dir.path}/$_cacheDir';
    return _basePath!;
  }

  Future<void> _ensureDir(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
  }

  /// 下载文件（带进度回调），返回本地缓存路径
  Future<String> downloadFile(
    String url,
    String subDir,
    String filename, {
    void Function(double progress)? onProgress,
  }) async {
    final base = await basePath;
    final dirPath = '$base/$subDir';
    await _ensureDir(dirPath);
    final filePath = '$dirPath/$filename';

    final file = File(filePath);
    if (await file.exists()) {
      onProgress?.call(1.0);
      return filePath;
    }

    final request = http.Request('GET', Uri.parse(url));
    final streamedResponse = await http.Client().send(request);
    final contentLength = streamedResponse.contentLength ?? 0;
    final sink = file.openWrite();
    var received = 0;

    await for (final chunk in streamedResponse.stream) {
      sink.add(chunk);
      received += chunk.length;
      if (contentLength > 0) {
        onProgress?.call(received / contentLength);
      }
    }

    await sink.close();
    onProgress?.call(1.0);
    return filePath;
  }

  /// 下载并缓存文件，返回本地缓存路径
  Future<String> cacheFile(String url, String subDir, String filename) async {
    final base = await basePath;
    final dirPath = '$base/$subDir';
    await _ensureDir(dirPath);
    final filePath = '$dirPath/$filename';

    final file = File(filePath);
    if (await file.exists()) {
      return filePath;
    }

    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      await file.writeAsBytes(response.bodyBytes);
      return filePath;
    } else {
      throw Exception('Failed to download $url: ${response.statusCode}');
    }
  }

  /// 获取缓存路径（文件存在则返回，不存在返回 null）
  Future<String?> getCachedPath(String subDir, String filename) async {
    final base = await basePath;
    final filePath = '$base/$subDir/$filename';
    if (await File(filePath).exists()) {
      return filePath;
    }
    return null;
  }

  /// 清除所有缓存
  Future<void> clearAll() async {
    final base = await basePath;
    final dir = Directory(base);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// 获取 songs 表缓存路径
  Future<String> get songsIndexCachePath async {
    final base = await basePath;
    return '$base/songs_index.json';
  }

  /// 缓存 songs 表 JSON
  Future<void> cacheSongsIndex(String json) async {
    final base = await basePath;
    await _ensureDir(base);
    final file = File('$base/songs_index.json');
    await file.writeAsString(json);
  }

  /// 读取 songs 表缓存
  Future<String?> readCachedSongsIndex() async {
    final path = await songsIndexCachePath;
    final file = File(path);
    if (await file.exists()) {
      return file.readAsString();
    }
    return null;
  }
}
