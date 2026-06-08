import '../../api_client.dart';
import '../../api_response.dart';

/// 文件端点 — 上传 / 元数据 / 删除。
class FileEndpoint {
  final ApiClient _client;

  FileEndpoint(this._client);

  Future<ApiResponse<FileUploadResult>> upload({
    required String fileName,
    required List<int> bytes,
    String? ttl,
  }) =>
      _client.request<FileUploadResult>(
        method: 'POST',
        path: '/api/v1/upload',
        body: {'file_name': fileName, 'file_bytes': bytes, ?ttl: ttl},
        fromJson: (json) => FileUploadResult.fromJson(json),
      );

  Future<ApiResponse<FileUploadResult>> uploadByKey({
    required String key,
    required String fileName,
    required List<int> bytes,
    String? ttl,
  }) =>
      _client.request<FileUploadResult>(
        method: 'POST',
        path: '/api/v1/upload/$key',
        body: {'file_name': fileName, 'file_bytes': bytes, ?ttl: ttl},
        fromJson: (json) => FileUploadResult.fromJson(json),
      );

  Future<ApiResponse<FileMetadataResult>> metadata(String id) =>
      _client.request<FileMetadataResult>(
        method: 'GET',
        path: '/api/v1/file/$id/metadata',
        fromJson: (json) => FileMetadataResult.fromJson(json),
      );

  Future<ApiResponse<void>> delete(String id) => _client.request<void>(
        method: 'DELETE',
        path: '/api/v1/file/$id',
      );
}

class FileUploadResult {
  final String id;
  final String name;
  final int? size;
  final String? contentType;
  final String? downloadUrl;

  const FileUploadResult({
    required this.id,
    required this.name,
    this.size,
    this.contentType,
    this.downloadUrl,
  });

  factory FileUploadResult.fromJson(Map<String, dynamic> json) =>
      FileUploadResult(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        size: json['size'] as int?,
        contentType: json['content_type'] as String?,
        downloadUrl: json['download_url'] as String?,
      );
}

class FileMetadataResult {
  final String id;
  final String name;
  final int? size;
  final String? contentType;
  final DateTime? uploadTime;
  final DateTime? expiresAt;

  const FileMetadataResult({
    required this.id,
    required this.name,
    this.size,
    this.contentType,
    this.uploadTime,
    this.expiresAt,
  });

  factory FileMetadataResult.fromJson(Map<String, dynamic> json) =>
      FileMetadataResult(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        size: json['size'] as int?,
        contentType: json['content_type'] as String?,
        uploadTime: json['upload_time'] != null
            ? DateTime.tryParse(json['upload_time'] as String)
            : null,
        expiresAt: json['expires_at'] != null
            ? DateTime.tryParse(json['expires_at'] as String)
            : null,
      );
}
