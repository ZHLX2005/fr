/// 网络环境 Tab 的数据模型
class WiFiInfo {
  final String? ssid;
  final String? bssid;
  final String? ip;
  final String? gateway;
  final String? submask;
  final String? ipv6;

  const WiFiInfo({
    this.ssid,
    this.bssid,
    this.ip,
    this.gateway,
    this.submask,
    this.ipv6,
  });

  static const empty = WiFiInfo();

  bool get isConnected => ip != null && ip!.isNotEmpty;
}

class PublicIpInfo {
  final String? ip;
  final String? city;
  final String? region;
  final String? country;
  final String? org;
  final bool loading;
  final String? error;

  const PublicIpInfo({
    this.ip,
    this.city,
    this.region,
    this.country,
    this.org,
    this.loading = false,
    this.error,
  });

  static const empty = PublicIpInfo(loading: true);

  PublicIpInfo copyWith({
    String? ip,
    String? city,
    String? region,
    String? country,
    String? org,
    bool? loading,
    String? error,
  }) {
    return PublicIpInfo(
      ip: ip ?? this.ip,
      city: city ?? this.city,
      region: region ?? this.region,
      country: country ?? this.country,
      org: org ?? this.org,
      loading: loading ?? this.loading,
      error: error,
    );
  }
}

class DnsResult {
  final String host;
  final String ip;
  final int ms;
  final bool ok;
  final String? error;

  const DnsResult({
    required this.host,
    required this.ip,
    required this.ms,
    required this.ok,
    this.error,
  });
}

class ProbeResult {
  final String name;
  final int statusCode;
  final int ms;
  final bool ok;
  final String? error;

  const ProbeResult({
    required this.name,
    required this.statusCode,
    required this.ms,
    required this.ok,
    this.error,
  });
}
