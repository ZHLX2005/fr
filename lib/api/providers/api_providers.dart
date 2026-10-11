import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api_config.dart';
import '../api_client.dart';
import '../token/token_storage.dart';
import '../token/token_manager.dart';
import '../authhub/authhub_qr_endpoint.dart';
import '../authhub/idp_session_store.dart';
import '../goframe/kv/kv_endpoint.dart';
import '../goframe/group/group_endpoint.dart';
import '../goframe/file/file_endpoint.dart';
import '../goframe/download/download_controller.dart';
import '../goframe/download/apk_endpoint.dart';
import '../goframe/article/article_endpoint.dart';
import '../goframe/ai/ai_endpoint.dart';
import '../goframe/room/room_endpoint.dart';
import '../notion/database_endpoint.dart';
import '../notion/page_endpoint.dart';
import '../notion/file_endpoint.dart';
import '../pi/pi.dart';

// ── Token ─────────────────────────────────────────────────────────

final tokenStorageProvider = Provider<TokenStorage>((_) => SharedPrefsTokenStorage());

/// 统一登录平台的登录态存储。
///
/// 定义在这里而不是 auth_providers：auth_providers 要用本文件的
/// tokenManagerProvider / apiClientProvider，反向 import 会成环。
/// 它本质是存储原语，与 tokenStorageProvider 同层。
final idpSessionStoreProvider = Provider<IdpSessionStore>((_) => IdpSessionStore());

final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  // 刻意不再 attachRefresher：客户端不持有长期凭据，也就没有续期这回事。
  // 过期由 TokenManager.needsReauth 暴露给上层，走一次 WebView 重新授权。
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

final groupEndpointProvider = Provider<GroupEndpoint>((ref) {
  return GroupEndpoint(ref.watch(apiClientProvider));
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
  return RoomEndpoint(baseUrl: 'http://47.110.80.47:8988');
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

// ── pi（nx-as 网关）─────────────────────────────────────────────────

/// pi 运行时配置（服务地址 / device token / 工作目录）。
///
/// ⚠️ 这里是**内存态**；持久化由 `lib/core/ai_chat/pi/` 的
/// SharedPreferences 配置层在启动时灌入（配置完全可在 App 内设置）。
final piConfigProvider = StateProvider<PiConfig>((_) => const PiConfig());

final piAgentEndpointProvider = Provider<PiAgentEndpoint>((ref) {
  return PiAgentEndpoint(config: () => ref.read(piConfigProvider));
});

final piSessionsEndpointProvider = Provider<PiSessionsEndpoint>((ref) {
  return PiSessionsEndpoint(config: () => ref.read(piConfigProvider));
});

final piModelsEndpointProvider = Provider<PiModelsEndpoint>((ref) {
  return PiModelsEndpoint(config: () => ref.read(piConfigProvider));
});

// ── AuthHub（统一认证中心：扫码批准）────────────────────────────────
//
// 自持 http.Client（规范 Rule 3），生命周期由 Provider 管，
// ref.onDispose 里关掉，避免 Lab 反复进出时泄漏连接。

final authHubQrEndpointProvider = Provider<AuthHubQrEndpoint>((ref) {
  final endpoint = AuthHubQrEndpoint(
    sessionStore: ref.watch(idpSessionStoreProvider),
  );
  ref.onDispose(endpoint.close);
  return endpoint;
});
