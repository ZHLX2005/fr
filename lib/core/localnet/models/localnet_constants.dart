/// LocalNet 网络配置常量
///
/// 集中管理所有网络相关配置，方便修改和维护
class LocalnetConstants {
  LocalnetConstants._();

  // ========== 多播配置 ==========

  /// UDP 多播地址 (LocalLink 范围 224.0.0.0/24)
  /// 使用 224.0.0.167 作为应用专属地址
  static const String multicastAddress = '224.0.0.167';

  /// UDP 多播端口
  static const int multicastPort = 53317;

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
  static String buildMulticastData(String deviceId, int port) {
    return '$deviceId,$port';
  }

  /// 解析多播数据
  /// 返回 [deviceId, port] 或 null (解析失败)
  static ({String deviceId, int port})? parseMulticastData(String data) {
    final parts = data.split(',');
    if (parts.length < 2) return null;
    final deviceId = parts[0].trim();
    final port = int.tryParse(parts[1].trim());
    if (deviceId.isEmpty || port == null) return null;
    return (deviceId: deviceId, port: port);
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
