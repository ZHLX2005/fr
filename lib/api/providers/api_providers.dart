import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../api_config.dart';
import '../api_client.dart';
import '../token/token_storage.dart';
import '../token/token_manager.dart';
import '../authhub/authhub_config.dart';
import '../authhub/authhub_exception.dart';
import '../authhub/authhub_oidc_endpoint.dart';
import '../authhub/authhub_qr_endpoint.dart';
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

final tokenManagerProvider = Provider<TokenManager>((ref) {
  final storage = ref.watch(tokenStorageProvider);
  final tm = TokenManager(
    storage: storage,
    // 认证中心的 access_token 只有 10 分钟，必须提前刷；不留提前量就会
    // 撞上"发出请求时还剩 3 秒、往返路上过期"这种随机失败。
    refreshSkew: AuthHubConfig.refreshSkew,
  );

  // 续期回调里用 ref.read 而不是 ref.watch：tokenManager 需要 authhub 端点
  // 去刷票，而那次刷票又要写回 tokenManager —— 构造期解析会成环。
  // read 在真正要刷的那一刻才解析，环就断了。
  tm.attachRefresher((refreshToken) async {
    final oidc = ref.read(authHubOidcEndpointProvider);
    try {
      final set = await oidc.refresh(refreshToken);
      await tm.setTokens(
        accessToken: set.accessToken,
        refreshToken: set.refreshToken,
        expiresAt: set.expiresAt,
        kind: AuthTokenKind.idp,
      );
      return true;
    } on AuthHubException catch (e) {
      // 只有认证中心明确说"这票不行了"才清凭据；网络抖动、5xx 一律保留，
      // 让下一次请求再试。清错的代价是用户被迫重新登录，
      // 不清的代价只是一次请求失败 —— 两者不对称。
      if (e.isFatalAuthError) {
        await tm.clear();
      }
      return false;
    }
  });

  return tm;
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

// ── AuthHub（统一认证中心：OIDC 登录 + 扫码批准）────────────────────
//
// 两个端点各自持有 http.Client（规范 Rule 3），所以生命周期由 Provider 管：
// ref.onDispose 里关掉，避免 Lab 反复进出时泄漏连接。

final authHubOidcEndpointProvider = Provider<AuthHubOidcEndpoint>((ref) {
  final endpoint = AuthHubOidcEndpoint();
  ref.onDispose(endpoint.close);
  return endpoint;
});

final authHubQrEndpointProvider = Provider<AuthHubQrEndpoint>((ref) {
  final endpoint = AuthHubQrEndpoint();
  ref.onDispose(endpoint.close);
  return endpoint;
});
