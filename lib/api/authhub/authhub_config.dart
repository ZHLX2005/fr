/// 认证中心（go-ah auth-hub）的连接参数。
///
/// 按 `api-module-auth` 规范 Rule 1/Rule 3：子目录 = 后端名，且**不共享** baseUrl
/// 与拦截器链 —— 认证中心的响应形状、错误语义、token 生命周期都与 goframe
/// 业务后端不同，硬套同一条链会让 AuthInterceptor 把业务后端的 token
/// 注进认证中心的请求里（或反过来），那类 bug 表现为"登录莫名其妙失败"。
///
/// URL 只能出现在这个文件里（规范检测项 5）。
library;

/// 认证中心连接配置。
class AuthHubConfig {
  AuthHubConfig._();

  /// 认证中心对外地址（nginx 入口，**不是**后端容器端口）。
  ///
  /// 必须是浏览器/手机可达的地址：授权与登出端点由用户设备直接访问，
  /// 写成容器内地址会让授权页打不开。与 auth-hub 的 IDP_ISSUER 逐字一致，
  /// 否则 id_token 的 iss 校验直接失败。
  static const String issuer = 'http://47.110.80.47:8082';

  /// 本 App 在认证中心注册的 client_id（见 auth-hub 的 consts.ClientFRApp 种子）。
  static const String clientId = 'fr-app';

  /// 申请的 scope。
  ///
  /// `email` 不能省：业务后端（dev_ctr_hello）认领本地账号时以邮箱为主键，
  /// 少了 email 就只能靠 sub 绑定，第一次统一登录会新建一个空账号，
  /// 而这个人在业务系统里本来是有数据的 —— 那正是接入统一登录要避免的事故。
  static const List<String> scopes = ['openid', 'profile', 'email'];

  /// 授权回调地址。
  ///
  /// 端口通配是认证中心白名单唯一允许移动端使用的形态
  /// （自定义 scheme 被 ValidRedirectURIs 拒，Universal Link 要 HTTPS + AASA）。
  /// 实际上本 App **不真的监听这个端口**：授权在 App 内嵌 WebView 里完成，
  /// 302 到该地址前就被 NavigationDelegate 拦下并从中取走 code，
  /// 所以端口只需要"每次不一样且能过白名单"，不需要有服务在听。
  static const String redirectPath = '/callback';

  /// 回环主机。用 127.0.0.1 而不是 localhost：后者在部分 ROM 上会先解析 IPv6 ::1。
  static const String redirectHost = '127.0.0.1';

  // ── 认证中心端点路径（auth-hub 用的是非标准名，不是 /authorize）──────────

  static const String discoveryPath = '/.well-known/openid-configuration';
  static const String userinfoPath = '/oauth2/userinfo';
  static const String logoutPath = '/oauth2/logout';

  /// 令牌吊销端点（RFC 7009）。
  ///
  /// 发现文档不 advertise 它，所以只能按 issuer 拼 —— 但**不要**从
  /// tokenEndpoint 反推（削掉 /token 再加 /revoke）：那种字符串戏法
  /// 在端点命名变更时会静默拼出 404，而 404 会被调用方的容错吞掉。
  static const String revokePath = '/oauth2/revoke';

  /// 原生表单登录要用到的三个端点路径。
  ///
  /// 授权端点是 `/oauth2/auth` 而不是标准的 `/authorize` —— 认证中心用的
  /// 是自己的命名，这里必须逐字对齐，写错只会得到一个 404。
  static const String authPath = '/oauth2/auth';
  static const String tokenPath = '/oauth2/token';
  static const String loginPath = '/api/login';
  static const String consentPath = '/api/consent';

  /// 查"当前登录态对应谁"。未登录时返回 code=0 且 data=null（正常态，不是错误）。
  static const String mePath = '/api/me';

  /// 认证中心的全局会话 Cookie 名（与后端 consts.SessionCookieName 一致）。
  ///
  /// 跨语言重复一份是事实，不是设计偏好：后端把它当不透明的 Set-Cookie 发出，
  /// 客户端必须知道名字才能在自己的 Cookie 容器里认出它。
  /// 改后端这个名字时**必须同步改这里** —— 否则原生登录会在
  /// "登录成功但未获得会话凭据"那一步失败（有断言兜着，不会静默）。
  static const String sessionCookieName = 'idp_session';

  /// 扫码登录端点前缀。
  static const String qrBasePath = '/api/qr/sessions';

  /// 手机确认页路径（扫码得到的就是这个 URL，App 要能从里面解析出 ticket）。
  static const String qrScanPath = '/scan';

  /// 二维码内容里 ticket 的查询参数名。
  static const String qrTicketParam = 't';

  // ── 超时 ───────────────────────────────────────────────────────────────

  /// 认证中心是**登录链路上的依赖**，超时必须短。
  ///
  /// 与 goframe 业务后端那个 240 秒（为大文件传输调的）完全不是一个量级：
  /// 拿 240 秒等一个 OAuth 端点，用户只会觉得 App 卡死。
  static const Duration httpTimeout = Duration(seconds: 10);

  /// 授权页等待用户完成登录的上限。超时后允许用户重来。
  static const Duration authorizeTimeout = Duration(minutes: 3);

  /// access_token 提前多久就视为该刷新。
  ///
  /// 认证中心的 access_token 只有 10 分钟。留 60 秒余量是为了避免
  /// "请求发出时还剩 3 秒、往返路上过期"这种在边界上随机失败的竞态。
  static const Duration refreshSkew = Duration(seconds: 60);

  /// 拼出一次授权会话使用的回调地址。
  static String redirectUriFor(int port) =>
      'http://$redirectHost:$port$redirectPath';

  /// 从扫码得到的 URL 中解析 ticket；解析失败返回 null。
  ///
  /// 兼容两种输入：完整 URL（`http://host/scan?t=xxx`）与裸 ticket。
  /// 真机上相机解出来的是前者，而 Lab 里手工粘贴时人往往只给后半截。
  static String? parseTicketFromScan(String scanned) {
    final s = scanned.trim();
    if (s.isEmpty) return null;
    if (s.startsWith('qrt_')) return s;
    final uri = Uri.tryParse(s);
    if (uri == null) return null;
    final t = uri.queryParameters[qrTicketParam];
    if (t != null && t.isNotEmpty) return t;
    return null;
  }
}
