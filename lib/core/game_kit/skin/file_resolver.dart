// lib/core/game_kit/skin/file_resolver.dart
//
// Generic file_id → URL resolver (extracted from lib/core/chess/skins/file_resolver.dart).
// 100% generic — chess re-exports this.

import 'package:flutter/foundation.dart' show immutable;

/// file_id → URL 解析器（UI 端唯一的访问入口，跨部署/跨 CDN 替换）
abstract class FileResolver {
  /// 把 [fileId] 转成可访问 URL（GET 公开或带签名，看实现）
  String url(String fileId);
}

/// 默认实现：拼 `${baseUrl}/files/${fileId}`
///
/// baseUrl 应该从 `ApiConfig.baseUrl` 来，不要 hardcode host。
@immutable
class PublicFileResolver implements FileResolver {
  final String baseUrl;

  const PublicFileResolver({required this.baseUrl});

  @override
  String url(String fileId) {
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/files/$fileId';
  }
}
