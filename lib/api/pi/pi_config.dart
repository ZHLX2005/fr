/// pi（nx-as 网关）后端配置。
///
/// **手机端唯一对话通道是 nx-as 的 `/m/v1/*`，不是 pi-web 的 `/api/*`** ——
/// 网关在这一层校验 device token 后注入机机凭据，pi-web 零改动即可用。
/// 路径契约：`<通道前缀>/<pi-web 路径去掉 /api>`。
///
/// 线上是 nginx 模式，前缀 `/_nxas/m/v1`；本机直连（direct）模式为 `/m/v1`。
class PiConfig {
  /// 站点根，例如 `http://47.110.80.47:18080`
  final String baseUrl;

  /// 手机通道前缀（见上）。默认按线上 nginx 模式。
  final String channelPrefix;

  /// device token（`nxas_d1.<id>.<secret>`），由使用方从安全存储注入。
  final String token;

  /// 会话工作目录（**服务端容器内路径**，如 `/data`）。
  ///
  /// ⚠️ `/models`、`/skills`、`/plugins`、`/subagents/profiles` 必须带它，
  /// 否则 403 Access denied 或 400 cwd required。
  final String cwd;

  const PiConfig({
    this.baseUrl = '',
    this.channelPrefix = kPiNginxPrefix,
    this.token = '',
    this.cwd = '/data',
  });

  /// 是否已具备发起请求的最低配置。
  bool get isConfigured => baseUrl.isNotEmpty && token.isNotEmpty;

  /// 通道内某个路径的完整 URL。
  Uri uri(String path, [Map<String, String>? query]) {
    final base = Uri.parse(baseUrl);
    return base.replace(
      path: '$channelPrefix$path',
      queryParameters: (query == null || query.isEmpty) ? null : query,
    );
  }

  /// 只覆盖已传入的字段（null 保留原值）。
  PiConfig copyWith({
    String? baseUrl,
    String? channelPrefix,
    String? token,
    String? cwd,
  }) =>
      PiConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        channelPrefix: channelPrefix ?? this.channelPrefix,
        token: token ?? this.token,
        cwd: cwd ?? this.cwd,
      );

  @override
  String toString() =>
      'PiConfig(baseUrl=$baseUrl, prefix=$channelPrefix, cwd=$cwd, '
      'token=${token.isEmpty ? '(空)' : '已设置'})';
}

/// 线上 nginx 模式：nx-as 自有内容收在 `/_nxas/` 前缀下。
const String kPiNginxPrefix = '/_nxas/m/v1';

/// 本机 direct 模式：无前缀。
const String kPiDirectPrefix = '/m/v1';
