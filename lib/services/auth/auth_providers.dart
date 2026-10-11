import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:get_it/get_it.dart';

import '../../api/providers/api_providers.dart';
import '../../api/user/user_auth_service.dart';
import 'auth_webview_page.dart';
import 'unified_auth_service.dart';

/// 统一登录服务的 DI 装配。
///
/// 单独一个文件而不是塞进 api_providers：这个服务横跨两层
/// （认证中心端点 + 业务后端账号认领），放进 api 的 provider 文件里
/// 会让"api 层只装端点"这条边界变模糊。
final unifiedAuthProvider = Provider<UnifiedAuthService>((ref) {
  return UnifiedAuthService(
    tokenManager: ref.watch(tokenManagerProvider),
    oidc: ref.watch(authHubOidcEndpointProvider),
    // 复用 GetIt 里的业务后端账号服务单例（聊天登录卡片用的是同一个）。
    // 统一登录成功后要靠它的 /user/info 让业务后端认领本地账号、
    // 把 userId 取回来（象棋身份挂在它上面）。
    // 这里必须走 GetIt 而不是自己 new：另起一个实例就等于另起一套
    // http.Client 与 token 读写路径，两处缓存会各说各话。
    userApi: () => GetIt.instance<UserAuthService>(),

  );
});

/// 发起统一登录：推授权页，回调地址返回后完成换票。
///
/// 抽成顶层函数是因为除了 Lab 面板，聊天里的登录消息卡片将来也要走同一条路。
/// 两处各写一遍 WebView 导航的话，"取消"与"失败"的语义迟早会分叉。
Future<AuthSession?> runUnifiedSignIn(
  BuildContext context,
  WidgetRef ref,
) async {
  final svc = ref.read(unifiedAuthProvider);
  final request = await svc.beginSignIn();
  // 拉发现文档期间页面可能已被销毁（用户退出了 Lab）。
  // 不检查就 Navigator.of(context) 是真实的崩溃来源，不是风格问题。
  if (!context.mounted) return null;
  final host = Uri.parse(request.authorizeUrl).host;

  final callback = await Navigator.of(context).push<String>(
    MaterialPageRoute(
      builder: (_) => AuthWebViewPage(
        authorizeUrl: request.authorizeUrl,
        redirectUri: request.redirectUri,
        identityHost: host,
      ),
    ),
  );
  if (callback == null) return null; // 用户取消

  return svc.completeSignIn(callbackUrl: callback, request: request);
}
