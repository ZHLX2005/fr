/// 认证中心返回的数据模型（目前只有扫码登录用到）。
///
/// 字段名一律保留后端的 snake_case（与仓库既有约定一致：后端怎么发就怎么接，
/// 中间加一层驼峰映射只会多一处对不上的地方）。
///
/// 原先这里的 AuthTokenSet / IdpUser / OidcEndpoints 已随"App 直连认证中心
/// 换 token"那条设计一起退场 —— App 不再持有认证中心的 token，
/// 只持有登录态（见 idp_session_store.dart）。
library;

/// 扫码票据状态。取值与后端 `entity.QRStatus*` 一一对应，**是契约不是提示**。
enum QrStatus {
  pending,
  scanned,
  confirmed,
  consumed,
  cancelled,
  expired;

  static QrStatus parse(String? raw) => QrStatus.values.firstWhere(
        (s) => s.name == raw,
        // 认不出的状态按 pending 处理而不是抛异常：后端将来加新状态时，
        // 旧版本 App 应该继续等待并允许用户刷新，而不是整个确认页崩掉。
        orElse: () => QrStatus.pending,
      );

  /// 手机端可发起确认的状态（终态与已批准都不行）
  bool get canApprove => this == QrStatus.pending || this == QrStatus.scanned;

  bool get isTerminal =>
      this == QrStatus.consumed ||
      this == QrStatus.cancelled ||
      this == QrStatus.expired;
}

/// `POST /api/qr/sessions` 的结果（PC 侧建的票，本 App 只作为扫码方使用其 URL）。
class QrSession {
  final String ticket;
  final String qrContent;
  final int expiresIn;
  final int intervalMs;

  const QrSession({
    required this.ticket,
    required this.qrContent,
    required this.expiresIn,
    required this.intervalMs,
  });

  factory QrSession.fromJson(Map<String, dynamic> json) => QrSession(
        ticket: json['ticket'] as String? ?? '',
        qrContent: json['qr_content'] as String? ?? '',
        expiresIn: (json['expires_in'] as num?)?.toInt() ?? 120,
        intervalMs: (json['interval_ms'] as num?)?.toInt() ?? 1500,
      );
}

/// `GET /api/qr/sessions/{ticket}/preview` —— 手机确认页的全部素材。
///
/// [pc] 是用户点"确认登录"前**唯一**能核对的东西：点下去等价于在另一台机器上
/// 输入自己的密码。所以这个结构缺字段时界面必须拒绝出确认按钮。
class QrPreview {
  final QrStatus status;
  final String pcUa;
  final String pcIp;
  final String pcGeo;
  final String pcCreatedAt;

  const QrPreview({
    required this.status,
    required this.pcUa,
    required this.pcIp,
    required this.pcGeo,
    required this.pcCreatedAt,
  });

  factory QrPreview.fromJson(Map<String, dynamic> json) {
    final pc = json['pc'] as Map<String, dynamic>? ?? const {};
    return QrPreview(
      status: QrStatus.parse(json['status'] as String?),
      pcUa: pc['ua'] as String? ?? '',
      pcIp: pc['ip'] as String? ?? '',
      pcGeo: pc['geo'] as String? ?? '',
      pcCreatedAt: pc['created_at'] as String? ?? '',
    );
  }

  /// 设备画像是否足够让人做出判断。
  ///
  /// 只要 ua 与 ip 全空，就宁可让用户重扫 —— 对着一条无法验证的信息点确认，
  /// 比不给确认按钮更危险。
  bool get hasMeaningfulDeviceInfo =>
      pcUa.trim().isNotEmpty || pcIp.trim().isNotEmpty;
}
