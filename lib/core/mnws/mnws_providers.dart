import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth/auth_providers.dart';
import 'mnws_endpoint.dart';
import 'mnws_grant_store.dart';
import 'mnws_service.dart';

/// mn-ws 的 DI 装配。
///
/// 与 services/remotetype 同款：单独一个文件，因为它的编排**形状**和统一登录
/// 一样（登录态 → 静默铸码 → 换本服务凭据），但它是另一个后端的业务，
/// 混进 auth 层会让 auth 层变成「谁接入都要来改一下」的地方。
///
/// 依赖方向单向：core/mnws → services/auth + core/mnws/*；
/// 反过来 import 会成环。
final mnWsGrantStoreProvider = Provider<MnWsGrantStore>((ref) {
  return MnWsGrantStore();
});

final mnWsEndpointProvider = Provider<MnWsEndpoint>((ref) {
  return MnWsEndpoint(
    // 凭据从注入的读取器里取，签名里没有 token 形参 ——
    // 那样「传错凭据」能通过类型检查，要到运行时才炸。
    grantReader: () => ref.read(mnWsGrantStoreProvider).read(),
  );
});

final mnWsServiceProvider = Provider<MnWsService>((ref) {
  return MnWsService(
    endpoint: ref.watch(mnWsEndpointProvider),
    idp: ref.watch(authHubSessionClientProvider),
    store: ref.watch(mnWsGrantStoreProvider),
  );
});
