// API 客户端包装
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../api/api_config.dart';
import '../api/goframe/download/apk_endpoint.dart';

// API 响应包装类
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  ApiResponse({required this.code, required this.message, this.data});

  static ApiResponse<T?> fromJson<T>(
    Map<String, dynamic> json,
    T? Function(dynamic) fromJsonT,
  ) {
    return ApiResponse(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? '',
      data: json['data'] != null ? fromJsonT(json['data']) : null,
    );
  }
}

// 下载控制器，用于支持取消/暂停/中断下载
// - cancel: 终止并丢弃已下载的临时文件
// - pause:  终止但保留临时文件，下次可基于 HTTP Range 续传
class DownloadController {
  bool _isCancelled = false;
  bool _isPaused = false;

  bool get isCancelled => _isCancelled;
  bool get isPaused => _isPaused;
  bool get shouldStop => _isCancelled || _isPaused;

  void cancel() {
    _isCancelled = true;
  }

  void pause() {
    _isPaused = true;
  }

  void reset() {
    _isCancelled = false;
    _isPaused = false;
  }
}

// 创建配置好basePath的API客户端
class ApiService {
  static const String baseUrl = 'http://47.110.80.47:8988';

  // 获取APK元数据（用于检查更新）— 委托 lib/api 规范层（ApkDownloadEndpoint）
  static Future<({int? size, String? uploadTime})?> getApkMetadata() async {
    final meta = await ApkDownloadEndpoint(ApiConfig.production()).metadata();
    if (meta == null) return null;
    return (size: meta.size, uploadTime: meta.uploadTime?.toIso8601String());
  }

  // 下载APK（通过key）
  static Future<http.Response?> downloadApk() async {
    try {
      final uri = Uri.parse('$baseUrl/api/v1/file/fr_latest_apk');
      return await http.get(uri);
    } catch (e) {
      return null;
    }
  }

  // 下载APK到本地（真正的流式下载，边收边写）
  // 返回下载后的文件路径，失败返回null
  // 注意：仅在 Android/iOS 平台可用，Web 平台返回 null
  static Future<String?> downloadApkToLocal({
    void Function(int received, int total)? onProgress,
    DownloadController? controller,
  }) async {
    // Web 平台不支持文件操作，返回 null 让调用方回退到浏览器下载
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    const fileKey = 'fr_latest_apk';
    final url = '$baseUrl/api/v1/file/$fileKey';

    try {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/download_$fileKey.tmp');
      final outputFile = File('${dir.path}/$fileKey.apk');

      // 断点续传：检查已下载部分
      int existingLength = 0;
      if (await tempFile.exists()) {
        existingLength = await tempFile.length();
      }

      final client = http.Client();

      try {
        // 使用 StreamedResponse 实现真正的流式下载
        final request = http.Request('GET', Uri.parse(url));
        if (existingLength > 0) {
          request.headers['Range'] = 'bytes=$existingLength-';
        }

        final streamedResponse = await client.send(request);

        if (streamedResponse.statusCode != 200 &&
            streamedResponse.statusCode != 206) {
          return null;
        }

        // 从 Content-Length 或 Content-Range 获取总大小
        int totalSize = existingLength;
        final contentLength = streamedResponse.headers['content-length'];
        if (contentLength != null && contentLength.isNotEmpty) {
          totalSize = existingLength + int.parse(contentLength);
        } else {
          final contentRange = streamedResponse.headers['content-range'];
          if (contentRange != null) {
            final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
            if (match != null) {
              totalSize = int.parse(match.group(1)!);
            }
          }
        }

        // 边收边写磁盘，实时回调进度
        final raf = await tempFile.open(
          mode: existingLength > 0 ? FileMode.append : FileMode.write,
        );
        int received = existingLength;

        await for (final chunk in streamedResponse.stream) {
          // 取消：丢弃临时文件
          if (controller != null && controller.isCancelled) {
            await raf.close();
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
            return null;
          }
          // 暂停：保留临时文件，下次基于 Range 续传
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

        // 重命名为正式文件（使用 copy 而不是 rename，更可靠）
        if (await tempFile.exists()) {
          try {
            // 先删除已存在的输出文件
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
            // 复制临时文件内容到目标文件
            final bytes = await tempFile.readAsBytes();
            await outputFile.writeAsBytes(bytes);
            // 删除临时文件
            await tempFile.delete();
          } catch (e) {
            // 如果复制失败，尝试直接返回临时文件路径
            return tempFile.path;
          }
        }

        // 验证输出文件存在
        if (!await outputFile.exists()) {
          return null;
        }

        return outputFile.path;
      } finally {
        client.close();
      }
    } catch (e) {
      return null;
    }
  }

  // 获取APK下载文件路径（如果已下载）
  // 注意：仅在 Android/iOS 平台可用
  static Future<String?> getDownloadedApkPath() async {
    // Web 平台不支持文件操作
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/fr_latest_apk.apk');
      if (await file.exists()) {
        return file.path;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 获取下载临时文件（用于检测是否存在可续传的暂停下载）
  // 返回 null 表示没有未完成的下载；返回路径和已下载字节数
  static Future<({String path, int size})?> getApkTempFileInfo() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/download_fr_latest_apk.tmp');
      if (await tempFile.exists()) {
        return (path: tempFile.path, size: await tempFile.length());
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  // 删除下载临时文件（取消已暂停的下载）
  static Future<void> clearApkTempFile() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/download_fr_latest_apk.tmp');
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}
  }
}
