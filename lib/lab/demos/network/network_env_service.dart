import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'const_network.dart';
import 'network_env_models.dart';

/// 网络环境数据获取服务（静态方法，无状态）
class NetworkEnvService {
  NetworkEnvService._();

  static final NetworkInfo _networkInfo = NetworkInfo();

  /// 读取 WiFi 信息
  static Future<WiFiInfo> loadWifi() async {
    try {
      return WiFiInfo(
        ssid: await _networkInfo.getWifiName(),
        bssid: await _networkInfo.getWifiBSSID(),
        ip: await _networkInfo.getWifiIP(),
        gateway: await _networkInfo.getWifiGatewayIP(),
        submask: await _networkInfo.getWifiSubmask(),
        ipv6: await _networkInfo.getWifiIPv6(),
      );
    } catch (e) {
      debugPrint('WiFi info error: $e');
      return WiFiInfo.empty;
    }
  }

  /// 读取网卡列表
  static Future<List<NetworkInterface>> loadInterfaces() async {
    try {
      return await NetworkInterface.list(
        includeLoopback: true,
        includeLinkLocal: true,
      );
    } catch (e) {
      debugPrint('Network interfaces error: $e');
      return const [];
    }
  }

  /// 查询公网 IP（含运营商/位置）
  static Future<PublicIpInfo> loadPublicIp() async {
    try {
      final resp = await http
          .get(Uri.parse(NetworkConst.publicIpInfoApi))
          .timeout(NetworkConst.httpProbeTimeout);
      if (resp.statusCode == 200) {
        final body = resp.body;
        return PublicIpInfo(
          ip: _jsonValue(body, 'ip'),
          city: _jsonValue(body, 'city'),
          region: _jsonValue(body, 'region'),
          country: _jsonValue(body, 'country_name'),
          org: _jsonValue(body, 'org'),
          loading: false,
        );
      }
      // fallback：只取纯 IP
      final resp2 = await http
          .get(Uri.parse(NetworkConst.publicIpApi))
          .timeout(NetworkConst.httpProbeTimeout);
      if (resp2.statusCode == 200) {
        return PublicIpInfo(
          ip: _jsonValue(resp2.body, 'ip'),
          loading: false,
        );
      }
      return PublicIpInfo(
        loading: false,
        error: 'HTTP ${resp.statusCode}',
      );
    } catch (e) {
      return PublicIpInfo(loading: false, error: e.toString());
    }
  }

  /// 测试一个域名的 DNS 解析延迟
  static Future<DnsResult> probeDns(String host) async {
    final sw = Stopwatch()..start();
    try {
      final addrs = await InternetAddress.lookup(host)
          .timeout(NetworkConst.dnsLookupTimeout);
      sw.stop();
      return DnsResult(
        host: host,
        ip: addrs.isEmpty ? '—' : addrs.first.address,
        ms: sw.elapsedMilliseconds,
        ok: addrs.isNotEmpty,
      );
    } catch (e) {
      sw.stop();
      return DnsResult(
        host: host,
        ip: 'fail',
        ms: sw.elapsedMilliseconds,
        ok: false,
        error: e.toString(),
      );
    }
  }

  /// HTTP 连通性测试单个 URL
  static Future<ProbeResult> probeHttp(String name, String url) async {
    final sw = Stopwatch()..start();
    try {
      final resp = await http
          .get(Uri.parse(url))
          .timeout(NetworkConst.httpProbeTimeout);
      sw.stop();
      return ProbeResult(
        name: name,
        statusCode: resp.statusCode,
        ms: sw.elapsedMilliseconds,
        ok: resp.statusCode > 0 && resp.statusCode < 400,
      );
    } catch (e) {
      sw.stop();
      return ProbeResult(
        name: name,
        statusCode: 0,
        ms: sw.elapsedMilliseconds,
        ok: false,
        error: e.toString(),
      );
    }
  }

  /// 极简 JSON value 提取，避免引入新依赖
  static String? _jsonValue(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
    final m = pattern.firstMatch(json);
    return m?.group(1);
  }

  /// network_info_plus 在某些机型上 SSID 会带 "" 包裹
  static String cleanSsid(String? raw) {
    if (raw == null) return '未知';
    var s = raw;
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    return s.isEmpty ? '未知' : s;
  }
}
