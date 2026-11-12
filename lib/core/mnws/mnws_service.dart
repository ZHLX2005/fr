import '../../api/authhub/authhub_exception.dart';
import '../../api/authhub/authhub_pkce.dart';
import '../../api/authhub/authhub_session_client.dart';
import '../mnws/mnws_config.dart';
import '../mnws/mnws_endpoint.dart';
import '../mnws/mnws_grant_store.dart';
import '../mnws/mnws_models.dart';

/// mn-ws 的编排：统一登录态 → 静默换来 mn-ws 设备令牌 → 拉目录 → 发请求。
///
/// ── 与 mn-rt 的 RemoteTypeService 同一套模式 ───────────────────────────────
/// 用户在 App 里登录一次统一登录平台，之后每个接入的服务都在背后静默拿凭据：
///   ① 问目标服务「你连的是哪个认证中心、用哪个 client、回调地址是什么」
///   ② 用已有的登录态在认证中心为那个 client 铸一枚授权码（PKCE 由本 App 生成并保管）
///   ③ 换出目标服务自己认的凭据
/// 没有一步需要用户操作，也没有一处需要人复制粘贴。
///
/// ── 与 mn-rt 唯一的一处结构差异 ───────────────────────────────────────────
/// 第 ③ 步的位置不同：
///   · mn-rt 的服务端收**授权码**，换码在服务端做 → fr 只把 code 递过去
///   · mn-ws 的服务端收**认证中心的 access_token**，换码在客户端做
///     （服务端拿它去问认证中心「这是谁」，再签一枚自己的设备令牌）
/// 所以 mn-ws 这条链路上，App 自己会短暂持有一次 access_token ——
/// 它 10 分钟就过期、换到设备令牌即丢弃，**不落盘**。
///
/// ── 为什么这里要单飞（single-flight）──────────────────────────────────────
/// 授权码一次性：并发跑两次 ensureGrant 会有两次铸码，其中一次必然在 ③ 失败，
/// 表现是「偶发登录失败」。用一个共享的 Future 把并发的调用并成一次。

/// 一次就绪状态：能不能用统一登录，以及为什么不能。
class MnWsReadiness {
  const MnWsReadiness({
    required this.available,
    this.reason = '',
    this.detail,
  });

  /// true = 可以用统一登录。
  /// false = 服务不可达 / 没开统一登录，UI 要能说清楚为什么。
  final bool available;
  final String reason;
  final MnWsErrorKind? detail;

  const MnWsReadiness.ok()
      : available = true,
        reason = '',
        detail = null;

  factory MnWsReadiness.off(String why, [MnWsErrorKind? kind]) =>
      MnWsReadiness(available: false, reason: why, detail: kind);
}

class MnWsService {
  MnWsService({
    required MnWsEndpoint endpoint,
    required AuthHubSessionClient idp,
    required MnWsGrantStore store,
  })  : _endpoint = endpoint,
        _idp = idp,
        _store = store;

  final MnWsEndpoint _endpoint;
  final AuthHubSessionClient _idp;
  final MnWsGrantStore _store;

  MnWsAuthConfig? _cfgCache;

  /// 正在进行的 ensureGrant。null = 没有。
  Future<MnWsGrant?>? _inFlight;

  /// server 半是否可用（结果缓存；失败不缓存，下次还会重试）。
  Future<MnWsReadiness> readiness() async {
    if (_cfgCache != null) return const MnWsReadiness.ok();
    try {
      final cfg = await _endpoint.authConfig();
      if (!cfg.enabled) {
        return MnWsReadiness.off('mn-ws 服务端未开启统一登录');
      }
      if (cfg.loginClientId.isEmpty) {
        return MnWsReadiness.off(
          'mn-ws 服务端未发布登录用的 client_id',
          MnWsErrorKind.malformed,
        );
      }
      _cfgCache = cfg;
      return const MnWsReadiness.ok();
    } on MnWsException catch (e) {
      return MnWsReadiness.off(e.message, e.kind);
    }
  }

  /// 拿到一枚可用凭据；没有就静默换一次。
  ///
  /// 返回 null 表示「换不到」（服务端没开启 / 没有统一登录态）。
  /// 刻意不抛：调用方拿到 null 之后退回提示，比弹一个红色错误更贴近事实。
  Future<MnWsGrant?> ensureGrant({bool force = false}) async {
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

  Future<MnWsGrant?> _ensureGrantInner({required bool force}) async {
    if (!force) {
      final cached = await _store.read();
      if (cached != null) return cached;
    }

    // 局部变量不叫 readiness：与方法同名会在自己的初始化里引用到未声明的局部量，
    // Dart 直接报 "can't be referenced before it is declared"，
    // 但这个写法在别的语言里是能重载调用的，读代码的人容易踩。
    final ready = await readiness();
    if (!ready.available) {
      // 配置不完整/未开启时，把可能存在的旧凭据一并清掉：
      // 留着一枚服务端已经不认的令牌，只会让用户在「点击连接」后拿到一个 401。
      if (force) await _store.clear();
      return null;
    }
    final cfg = _cfgCache!;

    final pkce = AuthPkce.generate();
    late final IssuedCode issued;
    try {
      // 用**统一登录平台的登录态**给 mn-ws-client 这个 client 铸码。
      // 内部服务自动同意（都是自己的权限域），所以这里不会弹任何东西。
      issued = await _idp.mintCodeForClient(
        client: cfg.loginClientId,
        redirectUri: MnWsConfig.redirectUri,
        scopes: cfg.scopes.isEmpty
            ? MnWsConfig.scopes
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

    // ② 换认证中心的 access_token（mn-ws 的服务端收的是它，不是码）
    final accessToken = await _endpoint.exchangeIdpToken(
      code: issued.code,
      codeVerifier: pkce.codeVerifier,
      redirectUri: MnWsConfig.redirectUri,
      clientId: cfg.loginClientId,
      tokenEndpoint: cfg.tokenEndpoint.isNotEmpty
          ? cfg.tokenEndpoint
          : '${cfg.issuer}${MnWsConfig.tokenPath}',
    );

    // ③ 换 mn-ws 自己的设备令牌
    final grant = await _endpoint.verify(
      accessToken: accessToken,
      clientId: MnWsConfig.deviceId,
      deviceName: MnWsConfig.deviceName,
    );
    await _store.save(grant);
    return grant;
  }

  /// 服务端支持哪些端口、应用名是什么。
  Future<List<MnWsApp>> catalog() async {
    final grant = await ensureGrant();
    if (grant == null) return const [];
    try {
      return await _endpoint.catalog();
    } on MnWsException catch (e) {
      if (e.kind != MnWsErrorKind.unauthorized) rethrow;
      final fresh = await ensureGrant(force: true);
      if (fresh == null) rethrow;
      return _endpoint.catalog();
    }
  }

  /// 经桥发一个请求（凭据失效时自动重铸一次再试，用户无感）。
  Future<MnWsResponse> request({
    required String method,
    required String path,
    String? app,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final grant = await ensureGrant();
    if (grant == null) {
      throw const MnWsException(
        MnWsErrorKind.unauthorized,
        '还没有 mn-ws 的凭据，请先登录',
      );
    }
    try {
      return await _endpoint.request(
        method: method,
        path: path,
        app: app,
        headers: headers,
        body: body,
      );
    } on MnWsException catch (e) {
      if (e.kind != MnWsErrorKind.unauthorized) rethrow;
      final fresh = await ensureGrant(force: true);
      if (fresh == null) rethrow;
      return _endpoint.request(
        method: method,
        path: path,
        app: app,
        headers: headers,
        body: body,
      );
    }
  }

  Future<void> signOut() => _store.clear();

  /// 清掉服务参数缓存（改了服务端配置或换部署地址后强制重探一次）。
  void resetConfigCache() => _cfgCache = null;
}
