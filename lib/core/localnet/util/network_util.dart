import 'dart:io';

/// 网络工具集
class NetworkUtil {
  NetworkUtil._();

  /// 探测本机 IPv4（路由可达的接口 IP）
  ///
  /// Android 上 [NetworkInterface.list] 经常只返回 `lo` 或空集，
  /// 因此先通过 DNS 反查让系统选路填充真实活跃接口 IP；
  /// 空集合时回退枚举网络接口。
  static Future<String?> detectLocalIp() async {
    // 1) DNS 反查：让系统帮我们挑活跃接口
    try {
      final addrs = await InternetAddress.lookup('dns.google')
          .timeout(const Duration(seconds: 2));
      for (final addr in addrs) {
        final ip = addr.address;
        if (ip.isNotEmpty && ip != '0.0.0.0') return ip;
      }
    } catch (_) {}

    // 2) 回退：枚举网络接口
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
      );
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          final ip = addr.address;
          if (ip.isEmpty || ip == '0.0.0.0') continue;
          if (ip.startsWith('192.168.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
    } catch (_) {}

    return null;
  }
}
