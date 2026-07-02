/// Notion API — Database / Page / File Upload 端点。
///
/// 第三方后端，按 `lib/api/github/` 同模式：自持 [http.Client]、Bearer
/// token、不走 [ApiClient] 拦截器链（Notion 错误语义和 GoFrame 不同）。
///
/// 使用方式：
/// ```dart
/// final db = NotionDatabaseEndpoint(token: 'ntn_xxx');
/// final page = await db.queryLatestPage('<database-id>');
/// ```
library;

export 'notion_config.dart';
export 'notion_exception.dart';
export 'database_endpoint.dart';
export 'page_endpoint.dart';
export 'file_endpoint.dart';