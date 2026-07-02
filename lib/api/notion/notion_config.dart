/// Notion API 配置常量。
class NotionConfig {
  /// Notion API base URL。
  static const String baseUrl = 'https://api.notion.com';

  /// Notion-Version header 值。锁定到 2022-06-28，覆盖 file_upload
  /// 单步/多步上传 + blocks/children PATCH 三套语义。
  static const String version = '2022-06-28';

  /// 单文件上传上限。Notion 当前限制 5MB / 单 integration。
  static const int maxFileSize = 5 * 1024 * 1024;

  /// 用户的「me」数据库 ID — 默认填在 SharedPreferences 之前的 fallback。
  static const String defaultDatabaseId =
      '38b550be-064e-801c-b944-f437c9a65f8a';

  NotionConfig._();
}