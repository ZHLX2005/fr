// lib/core/chess/skins/file_resolver.dart
//
// 把 server 端 32-hex file_id 转换成可访问 HTTP(s) URL 给 CachedNetworkImage 渲染。
//
// 设计要点：
//   - abstract FileResolver 让不同来源（Cdn、S3、自管）可替换；UI 端只依赖这个抽象
//   - PublicFileResolver 是默认实现：拼 baseUrl + `/files/` + fileId
//     （实测 server 端访问 GET /files/<fileId> 是 public-anonymous，无需 token）
//   - 不在构造时校验 fileId；UI 渲染前 CachedNetworkImage 会异步 404 → 走 chessSkinIsComplete fallback

import 'package:flutter/foundation.dart' show immutable;

/// file_id → URL 解析器（UI 端唯一的访问入口，跨部署/跨 CDN 替换）
abstract class FileResolver {
  /// 把 [fileId] 转成可访问 URL（GET 公开或带签名，看实现）
  String url(String fileId);
}

/// 默认实现：拼 `${baseUrl}/files/${fileId}`
///
/// baseUrl 应该从 `ApiConfig.baseUrl` 来，不要在 chess 模块里 hardcode host。
///   例如：`PublicFileResolver(baseUrl: ApiConfig.production().baseUrl)`
@immutable
class PublicFileResolver implements FileResolver {
  final String baseUrl;

  const PublicFileResolver({required this.baseUrl});

  @override
  String url(String fileId) {
    // 标准化：baseUrl 末尾可能带斜杠，去掉再拼，避免双斜杠
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    return '$base/files/$fileId';
  }
}
