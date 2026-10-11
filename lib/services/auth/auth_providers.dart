import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:get_it/get_it.dart';

import '../../api/providers/api_providers.dart';
import '../../api/authhub/authhub_native_login.dart';
import '../../api/user/user_auth_service.dart';
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
    native: AuthHubNativeLoginFlow(),
    // 复用 GetIt 里的业务后端账号服务单例（聊天登录卡片用的是同一个）。
    // 统一登录成功后要靠它的 /user/info 让业务后端认领本地账号、
    // 把 userId 取回来（象棋身份挂在它上面）。
    // 这里必须走 GetIt 而不是自己 new：另起一个实例就等于另起一套
    // http.Client 与 token 读写路径，两处缓存会各说各话。
    userApi: () => GetIt.instance<UserAuthService>(),

  );
});
