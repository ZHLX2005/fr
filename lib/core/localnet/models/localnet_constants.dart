/// LocalNet 网络配置常量
///
/// 集中管理所有网络相关配置，方便修改和维护
class LocalnetConstants {
  LocalnetConstants._();

  // ========== 多播配置 ==========

  /// UDP 多播地址 (ADMINSCOPE 范围 239.0.0.0/8)
  /// 相比 224.0.0.0/24 (LocalLink, TTL=1, 多数家用/办公路由器不转发)，
  /// 239.0.0.0/8 是 IANA 分配给私有应用的多播段，
  /// 路由器通常会正常转发。
  /// 兜底：若路由器仍阻断，可改用 255.255.255.255（有限广播）。
  static const String multicastAddress = '239.255.255.255';

  /// UDP 多播端口 — 故意与 httpPort 错开
  ///
  /// 历史原因：旧实现同端口跑 UDP 多播 + HTTP，依赖 Linux 同协议号可共享
  /// 端口。实际场景下：
  /// - Android 某些 ROM 会因为 TCP 占着 53317 导致 UDP bind 失败
  /// - TIME_WAIT 状态下重启会撞 errno=98
  /// 拆到 5678（IANA 临时端口段高位）避免冲突。
  static const int multicastPort = 5678;

  /// 多播数据格式：deviceId,port (纯文本，逗号分隔)
  static const String multicastDataFormat = 'deviceId,port';

  /// 多播广播间隔 (秒)
  static const int broadcastIntervalSeconds = 3;

  /// 设备离线判定时间 (秒) - 超过此时间未收到心跳视为离线
  static const int deviceTimeoutSeconds = 15;

  /// 清理定时器间隔 (秒)
  static const int cleanupIntervalSeconds = 10;

  // ========== HTTP 服务器配置 ==========

  /// HTTP 服务器端口 (复用多播端口，实现 UDP + HTTP 一端口)
  static const int httpPort = 53317;

  /// HTTP 请求超时 (毫秒)
  static const int httpTimeoutMillis = 10000;

  /// HTTP 消息路径
  static const String httpPathMessage = '/message';

  /// HTTP 加入路径
  static const String httpPathJoin = '/join';

  /// HTTP 信息路径
  static const String httpPathInfo = '/info';

  // ========== 协议配置 ==========

  /// 协议版本
  static const String protocolVersion = '1.0';

  /// 设备类型
  static const String deviceType = 'Flutter';

  // ========== 默认配置 ==========

  /// 默认设备别名
  static const String defaultDeviceAlias = 'Flutter Device';

  /// 默认端口
  static const int defaultPort = 53317;

  // ========== 辅助方法 ==========

  /// 构建多播数据
  ///
  /// [extras] 扩展字段，如 `['g:surround', 'r:roomA', 'p:1/2']`
  /// 完整格式: `deviceId,port[,key:value,...]`
  static String buildMulticastData(
    String deviceId,
    int port, [
    List<String>? extras,
  ]) {
    if (extras == null || extras.isEmpty) {
      return '$deviceId,$port';
    }
    return '$deviceId,$port,${extras.join(',')}';
  }

  /// 解析多播数据
  /// 返回 (deviceId, port, extrasMap) 或 null (解析失败)
  static ({String deviceId, int port, Map<String, String> extras})?
      parseMulticastData(String data) {
    final parts = data.split(',');
    if (parts.length < 2) return null;
    final deviceId = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    if (deviceId.isEmpty || port == null) return null;

    final extras = <String, String>{};
    for (var i = 2; i < parts.length; i++) {
      final kv = parts[i].split(':');
      if (kv.length == 2) {
        extras[kv[0].trim()] = kv[1].trim();
      }
    }

    return (deviceId: deviceId, port: port, extras: extras);
  }

  /// 构建 HTTP Join 请求体 (application/x-www-form-urlencoded)
  static String buildJoinBody(String deviceId, String name, int port) {
    return 'deviceId=$deviceId&name=$name&port=$port';
  }

  /// 生成 HTTP URL
  static String buildHttpUrl(String ip, int port, String path) {
    return 'http://$ip:$port$path';
  }
}
