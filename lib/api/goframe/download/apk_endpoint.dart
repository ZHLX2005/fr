import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../api_config.dart';
import 'download_controller.dart';

/// APK 流式下载 — 边收边写、断点续传。
/// 走 http.Client 直连（需 stream 控制），不走拦截器链。
class ApkDownloadEndpoint {
  final ApiConfig _config;

  ApkDownloadEndpoint(this._config);

  static const _fileKey = 'fr_latest_apk';

  String get _base => _config.baseUrl;

  Future<http.Response?> downloadRaw() async {
    try {
      return await http
          .get(Uri.parse('$_base/files/by-key/$_fileKey'))
          .timeout(_config.timeout);
    } catch (_) {
      return null;
    }
  }

  Future<String?> downloadToLocal({
    void Function(int received, int total)? onProgress,
    DownloadController? controller,
  }) async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    final url = '$_base/files/by-key/$_fileKey';
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/download_$_fileKey.tmp');
      final outputFile = File('${dir.path}/$_fileKey.apk');

      int existingLength = 0;
      if (await tempFile.exists()) existingLength = await tempFile.length();

      final client = http.Client();
      try {
        final request = http.Request('GET', Uri.parse(url));
        if (existingLength > 0) request.headers['Range'] = 'bytes=$existingLength-';
        final sr = await client.send(request);
        if (sr.statusCode != 200 && sr.statusCode != 206) return null;

        int totalSize = existingLength;
        final cl = sr.headers['content-length'];
        if (cl != null && cl.isNotEmpty) {
          totalSize = existingLength + int.parse(cl);
        } else {
          final cr = sr.headers['content-range'];
          if (cr != null) {
            final m = RegExp(r'/(\d+)$').firstMatch(cr);
            if (m != null) totalSize = int.parse(m.group(1)!);
          }
        }

        final raf = await tempFile.open(
          mode: existingLength > 0 ? FileMode.append : FileMode.write,
        );
        int received = existingLength;

        await for (final chunk in sr.stream) {
          if (controller != null && controller.isCancelled) {
            await raf.close();
            if (await tempFile.exists()) await tempFile.delete();
            return null;
          }
          if (controller != null && controller.isPaused) {
            await raf.close();
            return null;
          }
          await raf.writeFrom(chunk);
          received += chunk.length;
          if (onProgress != null &&
              totalSize > 0 &&
              (controller == null || !controller.shouldStop)) {
            onProgress(received, totalSize);
          }
        }
        await raf.close();

        if (await tempFile.exists()) {
          if (await outputFile.exists()) await outputFile.delete();
          final bytes = await tempFile.readAsBytes();
          await outputFile.writeAsBytes(bytes);
          await tempFile.delete();
        }
        return await outputFile.exists() ? outputFile.path : null;
      } finally {
        client.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<String?> getDownloadedPath() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/$_fileKey.apk');
      return await f.exists() ? f.path : null;
    } catch (_) {
      return null;
    }
  }

  Future<({String path, int size})?> getTempFileInfo() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/download_$_fileKey.tmp');
      return await f.exists() ? (path: f.path, size: await f.length()) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> clearTempFile() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final f = File('${dir.path}/download_$_fileKey.tmp');
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  /// 拉取 fr_latest_apk 的元数据（大小 / 上传时间），供"检查更新"展示。
  /// by-key 出图无 HEAD/metadata 端点，改用 `Range: bytes=0-0` 拿 206 响应头：
  ///   - `Content-Range: bytes 0-0/{total}` → 文件总大小
  ///   - `Last-Modified: <RFC1123 GMT>`     → 上传时间
  /// 只传 1 字节，不下载本体。与本文件其它方法一致：走 http.Client 直连。
  Future<ApkMetadataResult?> metadata() async {
    final client = http.Client();
    try {
      final req = http.Request(
        'GET',
        Uri.parse('$_base/files/by-key/$_fileKey'),
      );
      req.headers['Range'] = 'bytes=0-0';
      final resp = await client.send(req).timeout(_config.timeout);
      if (resp.statusCode != 206) {
        await resp.stream.drain();
        return null;
      }
      // 总大小：Content-Range: bytes 0-0/{total}
      int? size;
      final cr = resp.headers['content-range'];
      if (cr != null) {
        final m = RegExp(r'/(\d+)$').firstMatch(cr);
        size = m != null ? int.tryParse(m.group(1)!) : null;
      }
      // 上传时间：Last-Modified（RFC1123 GMT，HttpDate.parse 返回 UTC，
      // 与旧 upload_time 的 UTC ISO 串一致，上层直接转本地时区展示）
      DateTime? uploadTime;
      final lm = resp.headers['last-modified'];
      if (lm != null) uploadTime = HttpDate.parse(lm);
      await resp.stream.drain();
      return ApkMetadataResult(size: size, uploadTime: uploadTime);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}

/// APK 元数据（仅"检查更新"需要的两个字段）。
class ApkMetadataResult {
  final int? size;
  final DateTime? uploadTime;

  const ApkMetadataResult({this.size, this.uploadTime});
}
