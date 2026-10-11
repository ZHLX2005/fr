import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../api/providers/api_providers.dart';
import '../auth/auth_providers.dart';
import 'remotetype_service.dart';

/// 远程输入桥服务的 DI 装配。
///
/// 单独一个文件而不是塞进 auth_providers：它的编排**形状**和统一登录一样
/// （登录态 → 静默铸码 → 换本服务凭据），但它是另一个后端的业务，
/// 混在一起会让 auth 层变成"谁接入都要来改一下"的地方。
///
/// 依赖方向是单向的 services/remotetype → services/auth + api/*；
/// 反过来 import 会成环（auth_providers 已经依赖 api_providers）。
final remoteTypeServiceProvider = Provider<RemoteTypeService>((ref) {
  return RemoteTypeService(
    endpoint: ref.watch(remoteTypeEndpointProvider),
    idp: ref.watch(authHubSessionClientProvider),
    store: ref.watch(remoteTypeGrantStoreProvider),
  );
});
