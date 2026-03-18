// API 客户端包装
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show MultipartFile;
import '../generated/api.dart' as gen;

// 创建配置好basePath的API客户端
class ApiService {
  static const String baseUrl = 'http://139.9.42.203:8988';

  static final gen.ApiClient _client = gen.ApiClient(
    basePath: baseUrl,
  );

  static gen.KVApi get kvApi => gen.KVApi(_client);
  static gen.FileApi get fileApi => gen.FileApi(_client);

  // KV 操作
  static Future<gen.DevCtrHelloApiKvV1KvGetRes?> getKv(String key) async {
    try {
      return await kvApi.apiV1KvKeyGet(key: key);
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
      final result = await kvApi.apiV1KvPost(req);
      return result != null;
    } catch (e) {
      return false;
    }
  }

  static Future<bool> deleteKv(String key) async {
    try {
      final result = await kvApi.apiV1KvKeyDelete(key: key);
      return result != null;
    } catch (e) {
      return false;
    }
  }

  static Future<List<gen.DevCtrHelloApiKvV1KvItem>?> listKv({int limit = 50, int offset = 0}) async {
    try {
      final result = await kvApi.apiV1KvGet(limit: limit, offset: offset);
      return result?.items?.toList();
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
      return await fileApi.apiV1UploadPost(req);
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
      final result = await fileApi.apiV1FileIdDelete(id: id);
      return result != null;
    } catch (e) {
      return false;
    }
  }

  // 文件元数据
  static Future<gen.DevCtrHelloApiFileV1FileMetadataRes?> getFileMetadata(String id) async {
    try {
      return await fileApi.apiV1FileIdMetadataGet(id: id);
    } catch (e) {
      return null;
    }
  }
}
