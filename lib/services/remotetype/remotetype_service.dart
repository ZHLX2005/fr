// lib/services/remotetype/remotetype_service.dart
//
// 远程输入桥的编排：统一登录态 → 静默换来 mn-rt 凭据 → 列我名下的电脑。
//
// ── 与 8988 业务后端完全同一套模式 ─────────────────────────────────────────
// 用户在 App 里登录一次统一登录平台，之后每个接入的服务都在背后静默拿凭据：
//   ① 问目标服务"你连的是哪个认证中心、用哪个 client、回调地址是什么"
//   ② 用已有的登录态在认证中心为那个 client 铸一枚授权码（PKCE 由本 App 生成并保管）
//   ③ 把 code + verifier 交给目标服务，换回它自己的凭据
// 没有一步需要用户操作，也没有一处需要人复制粘贴。
//
// ── 为什么这里要单飞（single-flight）──────────────────────────────────────
// 授权码一次性：并发跑两次 ensureGrant 会有两次铸码，其中一次必然在 ③ 失败，
// 表现是"偶发登录失败"。用一个共享的 Future 把并发的调用并成一次。

import '../../api/authhub/authhub_exception.dart';
import '../../api/authhub/authhub_pkce.dart';
import '../../api/authhub/authhub_session_client.dart';
import '../../api/remotetype/remotetype.dart';

/// 一次就绪状态：能不能用统一登录，以及为什么不能。
class RemoteTypeReadiness {
  const RemoteTypeReadiness({
    required this.available,
    this.reason = '',
    this.detail,
  });

  /// true = 可以用统一登录，UI 显示"我的电脑"列表。
  /// false = 退回手工配对 key 的旧流程，并说明原因。
  final bool available;
  final String reason;
  final RemoteTypeErrorKind? detail;

  const RemoteTypeReadiness.ok()
      : available = true,
        reason = '',
        detail = null;

  factory RemoteTypeReadiness.off(String why, [RemoteTypeErrorKind? kind]) =>
      RemoteTypeReadiness(available: false, reason: why, detail: kind);
}

class RemoteTypeService {
  RemoteTypeService({
    required RemoteTypeEndpoint endpoint,
    required AuthHubSessionClient idp,
    required RemoteTypeGrantStore store,
  })  : _endpoint = endpoint,
        _idp = idp,
        _store = store;

  final RemoteTypeEndpoint _endpoint;
  final AuthHubSessionClient _idp;
  final RemoteTypeGrantStore _store;

  RtAuthConfig? _cfgCache;

  /// 正在进行的 ensureGrant。null = 没有。
  Future<RtGrant?>? _inFlight;

  /// 服务端是否支持统一登录（结果缓存；失败不缓存，下次还会重试）。
  Future<RemoteTypeReadiness> readiness() async {
    if (_cfgCache != null) return const RemoteTypeReadiness.ok();
    try {
      final cfg = await _endpoint.authConfig();
      if (!cfg.enabled) {
        // 不是错误：服务端没开启。UI 要能继续用旧的配对 key 流程。
        return RemoteTypeReadiness.off('该服务未开启统一登录，请用配对 key 连接');
      }
      if (cfg.clientId.isEmpty || cfg.redirectUri.isEmpty) {
        return RemoteTypeReadiness.off('服务端统一登录配置不完整',
            RemoteTypeErrorKind.idpUnavailable);
      }
      _cfgCache = cfg;
      return const RemoteTypeReadiness.ok();
    } on RemoteTypeException catch (e) {
      return RemoteTypeReadiness.off(e.message, e.kind);
    }
  }

  /// 拿到一枚可用凭据；没有就静默换一次。
  ///
  /// 返回 null 表示"换不到"（服务端没开启 / 没有统一登录态）。
  /// 刻意不抛：调用方拿到 null 之后退回手工 key，比弹一个红色错误更贴近事实。
  Future<RtGrant?> ensureGrant({bool force = false}) async {
    final pending = _inFlight;
    if (pending != null) return pending;
    final future = _ensureGrantInner(force: force);
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<RtGrant?> _ensureGrantInner({required bool force}) async {
    if (!force) {
      final cached = await _store.read();
      if (cached != null) return cached;
    }

    // 局部变量不叫 readiness：与方法同名会在自己的初始化里引用到未声明的局部量，
    // Dart 直接报"can't be referenced before it is declared"，
    // 但这个写法在别的语言里是能重载调用的，读代码的人容易踩。
    final ready = await readiness();
    if (!ready.available) {
      // 配置不完整/未开启时，把可能存在的旧凭据一并清掉：
      // 留着一枚服务端已经不认的令牌，只会让用户在"点击连接"后拿到一个 401。
      if (force) await _store.clear();
      return null;
    }
    final cfg = _cfgCache!;

    final pkce = AuthPkce.generate();
    late final IssuedCode issued;
    try {
      // 用**统一登录平台的登录态**给 mn-rt 这个 client 铸码。
      // 内部服务自动同意（都是自己的权限域），所以这里不会弹任何东西。
      issued = await _idp.mintCodeForClient(
        client: cfg.clientId,
        redirectUri: cfg.redirectUri,
        scopes: cfg.scopes.isEmpty
            ? const ['openid', 'profile', 'email']
            : cfg.scopes,
        state: pkce.state,
        nonce: pkce.nonce,
        codeChallenge: pkce.codeChallenge,
      );
    } on AuthHubException catch (e) {
      // 登录态没了是要用户动手的信号（重新登录），不能当瞬时失败重试。
      if (e.error == 'unauthenticated' || e.error == 'session_expired') {
        await _store.clear();
        return null;
      }
      rethrow;
    }

    final grant = await _endpoint.exchangeCode(
      code: issued.code,
      codeVerifier: pkce.codeVerifier,
      redirectUri: cfg.redirectUri,
    );
    await _store.save(grant);
    return grant;
  }

  /// 我名下的电脑。凭据失效时会自动重铸一次再试（用户无感）。
  Future<List<RtComputer>> myComputers() async {
    final grant = await ensureGrant();
    if (grant == null) return const [];
    try {
      return await _endpoint.myComputers();
    } on RemoteTypeException catch (e) {
      if (e.kind != RemoteTypeErrorKind.unauthorized) rethrow;
      final fresh = await ensureGrant(force: true);
      if (fresh == null) rethrow;
      return _endpoint.myComputers();
    }
  }

  Future<void> signOut() => _store.clear();

  /// 清掉服务参数缓存（改了服务端配置或换部署地址后强制重探一次）。
  void resetConfigCache() => _cfgCache = null;
}
