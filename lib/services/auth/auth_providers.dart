import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/authhub/authhub_session_client.dart';
import '../../api/goframe/oidc/oidc_endpoint.dart';
import '../../api/providers/api_providers.dart';
import 'unified_auth_service.dart';

/// 统一登录相关服务的 DI 装配。
///
/// 单独一个文件而不是塞进 api_providers：这里组装的东西横跨两个后端
/// （认证中心的登录态 + 业务后端的授权码换 token），放进 api 层的 provider
/// 文件会让"api 层只装端点"这条边界变模糊。
final authHubSessionClientProvider = Provider<AuthHubSessionClient>((ref) {
  final client = AuthHubSessionClient(
    store: ref.watch(idpSessionStoreProvider),
  );
  ref.onDispose(client.close);
  return client;
});

final oidcEndpointProvider = Provider<OidcEndpoint>((ref) {
  return OidcEndpoint(ref.watch(apiClientProvider));
});

final unifiedAuthProvider = Provider<UnifiedAuthService>((ref) {
  final svc = UnifiedAuthService(
    idp: ref.watch(authHubSessionClientProvider),
    sessionStore: ref.watch(idpSessionStoreProvider),
    oidc: ref.watch(oidcEndpointProvider),
    tokens: ref.watch(tokenManagerProvider),
  );

  // 把"用登录态重铸业务 token"挂到 TokenManager 上：业务接口收到 401 时
  // 由它静默换一枚，用户无感。
  //
  // 用注入而不是让 token/ 直接依赖本服务：token 层是基础设施，
  // 规范禁止它碰具体后端的 HTTP 细节；而且反向依赖会成环。
  ref.watch(tokenManagerProvider).attachReauth(svc.reauthBackendToken);

  return svc;
});
