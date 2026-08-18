import 'package:flutter/material.dart';

/// 网络模块常量
class NetworkConst {
  NetworkConst._();

  // ===== 默认值 =====
  static const String defaultHttpUrl =
      'https://jsonplaceholder.typicode.com/posts/1';
  static const String defaultWsUrl = 'wss://echo.websocket.org';
  static const String defaultWsMessage = 'Hello WebSocket';
  static const String defaultHttpHeaders = 'Content-Type: application/json';

  // ===== 公网 IP 查询服务 =====
  /// 公网 IP/地理位置查询（json 直接返回）
  static const String publicIpApi = 'https://api.ipify.org?format=json';
  static const String publicIpInfoApi = 'https://ipapi.co/json/';

  // ===== DNS 测试目标 =====
  static const List<String> dnsTestHosts = <String>[
    'baidu.com',
    'google.com',
    'cloudflare.com',
    'github.com',
  ];

  /// HTTP 连通性测试目标
  static const List<({String name, String url})> httpProbes = [
    (name: 'Baidu', url: 'https://www.baidu.com'),
    (name: 'Google', url: 'https://www.google.com/generate_204'),
    (name: 'Cloudflare', url: 'https://1.1.1.1'),
    (name: 'GitHub', url: 'https://api.github.com'),
  ];

  // ===== 常用端口说明 =====
  static const List<({String name, String port})> commonPorts = [
    (name: 'HTTP', port: '80'),
    (name: 'HTTPS', port: '443'),
    (name: 'SSH', port: '22'),
    (name: 'Telnet', port: '23'),
    (name: 'FTP', port: '21'),
    (name: 'SMTP', port: '25'),
    (name: 'DNS', port: '53'),
    (name: 'mDNS', port: '5353'),
    (name: 'LocalSend', port: '53317'),
  ];

  // ===== 信号强度阈值 (dBm) =====
  static const int rssiExcellent = -50;
  static const int rssiGood = -70;
  static const int rssiFair = -80;
  static const int rssiMinDefault = -100;

  // ===== 蓝牙扫描 =====
  static const Duration bleScanTimeout = Duration(seconds: 5);
  static const Duration bleConnectTimeout = Duration(seconds: 10);

  // ===== HTTP/网络测试超时 =====
  static const Duration httpProbeTimeout = Duration(seconds: 5);
  static const Duration dnsLookupTimeout = Duration(seconds: 3);

  // ===== 颜色 =====
  static const Color colorSuccess = Colors.green;
  static const Color colorError = Colors.red;
  static const Color colorWarn = Colors.orange;
  static const Color colorInfo = Colors.blue;
  static const Color colorMuted = Colors.grey;

  // ===== 私有 IP 段说明 =====
  static const List<({String range, String desc})> privateIpRanges = [
    (range: '10.0.0.0/8', desc: 'A 类私有'),
    (range: '172.16.0.0/12', desc: 'B 类私有'),
    (range: '192.168.0.0/16', desc: 'C 类私有'),
    (range: '169.254.0.0/16', desc: 'APIPA 链路本地'),
    (range: '127.0.0.0/8', desc: 'Loopback 回环'),
  ];
}
