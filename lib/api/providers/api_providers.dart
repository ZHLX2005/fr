import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api_config.dart';
import '../api_client.dart';
import '../token/token_storage.dart';
import '../token/token_manager.dart';
import '../goframe/kv/kv_endpoint.dart';
import '../goframe/file/file_endpoint.dart';
import '../goframe/download/download_controller.dart';
import '../goframe/download/apk_endpoint.dart';
import '../goframe/article/article_endpoint.dart';
import '../goframe/ai/ai_endpoint.dart';
import '../goframe/room/room_endpoint.dart';
import '../notion/database_endpoint.dart';
import '../notion/page_endpoint.dart';
import '../notion/file_endpoint.dart';

// ── Token ──────────────────────────────────────────────────────────

final tokenStorageProvider = Provider<TokenStorage>((_) => SharedPrefsTokenStorage());

final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  return TokenManager(storage: storage);
});

// ── Config / Client ────────────────────────────────────────────────

final apiConfigProvider = Provider<ApiConfig>((_) => ApiConfig.production());

final apiClientProvider = Provider<ApiClient>((ref) {
  final config = ref.watch(apiConfigProvider);
  final tm = ref.watch(tokenManagerProvider);
  return ApiClient(config: config, tokenManager: tm);
});

// ── GoFrame Endpoints ──────────────────────────────────────────────

final kvEndpointProvider = Provider<KvEndpoint>((ref) {
  return KvEndpoint(ref.watch(apiClientProvider));
});

final fileEndpointProvider = Provider<FileEndpoint>((ref) {
  return FileEndpoint(ref.watch(apiClientProvider));
});

final articleEndpointProvider = Provider<ArticleEndpoint>((ref) {
  return ArticleEndpoint(ref.watch(apiClientProvider));
});

final aiEndpointProvider = Provider<AiEndpoint>((ref) {
  return AiEndpoint(ref.watch(apiClientProvider));
});

final apkDownloadEndpointProvider = Provider<ApkDownloadEndpoint>((ref) {
  return ApkDownloadEndpoint(ref.watch(apiConfigProvider));
});

final downloadControllerProvider = Provider<DownloadController>((_) => DownloadController());

final roomEndpointProvider = Provider<RoomEndpoint>((_) {
  // 用默认 GoFrame 后端地址
  return RoomEndpoint(baseUrl: 'http://47.110.80.47:8988', pathPrefix: '/relay');
});

// ── Notion ──────────────────────────────────────────────────────────
//
// Notion 端点需要 token + 可选 databaseId。token 存在 StateProvider，
// UI 层（demo）从 SharedPreferences 读出来写入；不在这层做持久化，
// 避免依赖耦合。
final notionTokenProvider = StateProvider<String?>((_) => null);

final notionDatabaseIdProvider = StateProvider<String?>((_) => null);

final notionDatabaseEndpointProvider = Provider<NotionDatabaseEndpoint>((ref) {
  final token = ref.watch(notionTokenProvider);
  if (token == null || token.isEmpty) {
    throw StateError('Notion token 未设置：请在 UI 中写入 notionTokenProvider');
  }
  return NotionDatabaseEndpoint(token: token);
});

final notionPageEndpointProvider = Provider<NotionPageEndpoint>((ref) {
  final token = ref.watch(notionTokenProvider);
  if (token == null || token.isEmpty) {
    throw StateError('Notion token 未设置');
  }
  return NotionPageEndpoint(token: token);
});

final notionFileEndpointProvider = Provider<NotionFileEndpoint>((ref) {
  final token = ref.watch(notionTokenProvider);
  if (token == null || token.isEmpty) {
    throw StateError('Notion token 未设置');
  }
  return NotionFileEndpoint(token: token);
});
