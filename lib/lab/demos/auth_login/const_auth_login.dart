/// 统一登录 / 扫码批准 Lab 的常量。
///
/// 按项目规范单独建 `const_xxxx.dart` 统一管理，不散在各界面文件里 ——
/// 这些值里有 tab 索引、轮询节奏、展示文案，多处各写一份迟早会不一致。
class AuthLoginConst {
  AuthLoginConst._();

  // ── Tab ──────────────────────────────────────────────────────────────
  static const int tabUnifiedLogin = 0;
  static const int tabQrApprove = 1;
  static const int tabSelfTest = 2;

  static const List<String> tabLabels = [
    '统一登录',
    '扫码批准',
    '本机自测',
  ];

  // ── 扫码轮询 ─────────────────────────────────────────────────────────

  /// 自测模式下 PC 侧的轮询间隔（与后端下发的 interval_ms 同量级）。
  static const Duration pollInterval = Duration(milliseconds: 1500);

  /// 自测等待批准的上限。超过就提示超时 —— 比无限转圈好，
  /// 因为用户无法区分"还在等"和"卡住了"。
  static const Duration selfTestTimeout = Duration(seconds: 100);

  /// 扫码结果去重窗口：相机对同一张码会以每秒几十帧的频率回调，
  /// 不去重会瞬间打出几十个 preview 请求，把认证中心当 DDOS 目标打。
  static const Duration scanDedupeWindow = Duration(seconds: 3);

  // ── 文案 ─────────────────────────────────────────────────────────────

  static const String title = '统一登录 · 扫码';
  static const String description = '认证中心 OIDC 登录 + 扫码批准其他设备登录';

  static const String hintNoSession = '当前未登录统一认证中心';
  static const String hintIdpUnreachable =
      '认证中心不可达。可退回邮箱密码登录（业务后端自己的账号体系），'
      '但扫码批准功能不可用 —— 它必须有一个认证中心身份才能执行。';

  /// 确认页上最重要的这句话：点下去等价于在另一台机器上输入密码。
  static const String warnApproveMeaning =
      '确认后就等于在「上面那台机器」上登录你的账号。'
      '不是你自己发起的，请点「不是我操作」。';

  static const String btnSignIn = '用统一认证中心登录';
  static const String btnSignOut = '退出登录';
  static const String btnScan = '扫码批准';
  static const String btnApprove = '确认登录';
  static const String btnRefuse = '不是我操作';
  static const String btnSelfTest = '跑一次完整自测';

  /// 设备画像缺失时的说明 —— 此时必须禁用确认按钮。
  static const String errNoDeviceInfo =
      '没取到对方设备信息，无法核对是不是你本人的请求。请让对方刷新二维码后重扫。';

  // ── 日志 ─────────────────────────────────────────────────────────────

  static const String logTag = 'AuthLogin';

  /// 自测日志最多保留多少条。
  /// 无上限的话，一次长时间自测会把列表撑到滚动都困难，
  /// 而这个面板的作用恰恰是让人看见最近发生了什么。
  static const int maxLogLines = 60;
}
