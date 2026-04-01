// API 客户端包装
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile;
import 'package:path_provider/path_provider.dart';
import '../generated/api.dart' as gen;

// API 响应包装类
class ApiResponse<T> {
  final int code;
  final String message;
  final T? data;

  ApiResponse({required this.code, required this.message, this.data});

  static ApiResponse<T?> fromJson<T>(Map<String, dynamic> json, T? Function(dynamic) fromJsonT) {
    return ApiResponse(
      code: json['code'] as int? ?? -1,
      message: json['message'] as String? ?? '',
      data: json['data'] != null ? fromJsonT(json['data']) : null,
    );
  }
}

// 创建配置好basePath的API客户端
class ApiService {
  static const String baseUrl = 'http://47.110.80.47:8988';

  static final gen.ApiClient _client = gen.ApiClient(
    basePath: baseUrl,
  );

  static gen.KVApi get kvApi => gen.KVApi(_client);
  static gen.FileApi get fileApi => gen.FileApi(_client);

  // KV 操作
  static Future<gen.DevCtrHelloApiKvV1KvGetRes?> getKv(String key) async {
    try {
      final response = await kvApi.apiV1KvKeyGetWithHttpInfo(key: key);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return gen.DevCtrHelloApiKvV1KvGetRes.fromJson(json['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  static Future<bool> setKv(String key, String value, {int? ttl}) async {
    try {
      final req = gen.DevCtrHelloApiKvV1KvSetReq(
        key: key,
        value: value,
        ttl: ttl,
      );
      final response = await kvApi.apiV1KvPostWithHttpInfo(req);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['code'] == 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteKv(String key) async {
    try {
      final response = await kvApi.apiV1KvKeyDeleteWithHttpInfo(key: key);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['code'] == 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  static Future<List<gen.DevCtrHelloApiKvV1KvItem>?> listKv({int limit = 50, int offset = 0}) async {
    try {
      final response = await kvApi.apiV1KvGetWithHttpInfo(limit: limit, offset: offset);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null && json['data']['items'] != null) {
          return gen.DevCtrHelloApiKvV1KvItem.listFromJson(json['data']['items'])
              .toList();
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 文件上传
  static Future<gen.DevCtrHelloApiFileV1FileUploadRes?> uploadFile(
    File file, {
    String? ttl,
  }) async {
    try {
      final fileName = file.path.split('/').last;
      final bytes = await file.readAsBytes();

      final multipartFile = MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      );

      final req = gen.DevCtrHelloApiFileV1FileUploadReq(
        file: multipartFile,
        ttl: ttl ?? '1h',
      );
      final response = await fileApi.apiV1UploadPostWithHttpInfo(req);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return gen.DevCtrHelloApiFileV1FileUploadRes.fromJson(json['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 文件下载
  static Future<http.Response?> downloadFile(String id) async {
    try {
      return await fileApi.apiV1DownloadIdGetWithHttpInfo(id: id);
    } catch (e) {
      return null;
    }
  }

  // 文件删除
  static Future<bool> deleteFile(String id) async {
    try {
      final response = await fileApi.apiV1FileIdDeleteWithHttpInfo(id: id);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return json['code'] == 0;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // 通过Key上传文件
  static Future<gen.DevCtrHelloApiFileV1FileUploadRes?> uploadFileByKey(
    File file,
    String key, {
    String? ttl,
  }) async {
    try {
      final fileName = file.path.split('/').last;
      final bytes = await file.readAsBytes();

      final multipartFile = MultipartFile.fromBytes(
        'file',
        bytes,
        filename: fileName,
      );

      // 使用 key 作为路径参数上传
      final uri = Uri.parse('$baseUrl/api/v1/upload/$key');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(multipartFile);
      if (ttl != null) {
        request.fields['ttl'] = ttl;
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return gen.DevCtrHelloApiFileV1FileUploadRes.fromJson(json['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // 获取APK元数据（用于检查更新）- 使用key作为id
  static Future<gen.DevCtrHelloApiFileV1FileMetadataRes?> getApkMetadata() async {
    try {
      final response = await fileApi.apiV1FileIdMetadataGetWithHttpInfo(id: 'fr_latest_apk');
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return gen.DevCtrHelloApiFileV1FileMetadataRes.fromJson(json['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
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

  // 下载APK到本地（支持断点续传）
  // 返回下载后的文件路径，失败返回null
  // 注意：仅在 Android/iOS 平台可用，Web 平台返回 null
  static Future<String?> downloadApkToLocal({
    void Function(int received, int total)? onProgress,
  }) async {
    // Web 平台不支持文件操作，返回 null 让调用方回退到浏览器下载
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    const fileKey = 'fr_latest_apk';
    final url = '$baseUrl/api/v1/file/$fileKey';

    try {
      // 获取应用文档目录
      final dir = await getApplicationDocumentsDirectory();
      final tempFile = File('${dir.path}/download_$fileKey.tmp');
      final outputFile = File('${dir.path}/$fileKey.apk');

      // 检查已下载的部分
      int existingLength = 0;
      if (await tempFile.exists()) {
        existingLength = await tempFile.length();
      }

      final client = http.Client();

      try {
        // 发送 Range 请求（如果支持断点续传）
        Map<String, String> headers = {};
        if (existingLength > 0) {
          headers['Range'] = 'bytes=$existingLength-';
        }

        final response = await client.get(Uri.parse(url), headers: headers);

        if (response.statusCode == 200 || response.statusCode == 206) {
          // 获取总大小
          int totalSize = existingLength;
          final contentLength = response.headers['content-length'];
          if (contentLength != null) {
            final receivedLength = int.parse(contentLength);
            totalSize = existingLength + receivedLength;
          } else {
            // 没有 Content-Length，尝试从 Content-Range 解析
            final contentRange = response.headers['content-range'];
            if (contentRange != null) {
              final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
              if (match != null) {
                totalSize = int.parse(match.group(1)!);
              }
            }
          }

          // 写入文件
          final raf = await tempFile.open(mode: existingLength > 0 ? FileMode.append : FileMode.write);
          // 直接写入整个字节数组
          await raf.writeFrom(response.bodyBytes);
          await raf.close();

          if (onProgress != null && totalSize > 0) {
            onProgress(await tempFile.length(), totalSize);
          }

          // 重命名为正式文件
          if (await tempFile.exists()) {
            if (await outputFile.exists()) {
              await outputFile.delete();
            }
            await tempFile.rename(outputFile.path);
          }

          return outputFile.path;
        } else {
          // 服务器不支持断点续传，清空重新下载
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          final newResponse = await client.get(Uri.parse(url));
          if (newResponse.statusCode == 200) {
            await outputFile.writeAsBytes(newResponse.bodyBytes);
            return outputFile.path;
          }
          return null;
        }
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

  // 文件元数据
  static Future<gen.DevCtrHelloApiFileV1FileMetadataRes?> getFileMetadata(String id) async {
    try {
      final response = await fileApi.apiV1FileIdMetadataGetWithHttpInfo(id: id);
      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        if (json['data'] != null) {
          return gen.DevCtrHelloApiFileV1FileMetadataRes.fromJson(json['data']);
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
