import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:network_info_plus/network_info_plus.dart';

import 'const_network.dart';
import 'network_widgets.dart';

/// 网络环境 Tab —— 一站式查看当前设备的网络状态
///
/// 设计目标：让 adb logcat / 手机用户能在不打开 PC 工具的情况下
/// 直观看到网络状态，每条都可复制，便于排查问题。
class NetworkEnvTab extends StatefulWidget {
  const NetworkEnvTab({super.key});

  @override
  State<NetworkEnvTab> createState() => _NetworkEnvTabState();
}

class _NetworkEnvTabState extends State<NetworkEnvTab>
    with AutomaticKeepAliveClientMixin {
  final NetworkInfo _networkInfo = NetworkInfo();

  // ===== WiFi =====
  String? _wifiName;
  String? _wifiBSSID;
  String? _wifiIP;
  String? _wifiGateway;
  String? _wifiSubmask;
  String? _wifiIPv6;

  // ===== 公网 IP =====
  String? _publicIp;
  String? _publicIpCity;
  String? _publicIpRegion;
  String? _publicIpCountry;
  String? _publicIpOrg;
  bool _publicIpLoading = false;
  String? _publicIpError;

  // ===== 网卡 =====
  List<NetworkInterface> _interfaces = [];

  // ===== DNS 测试 =====
  final Map<String, _DnsResult> _dnsResults = {};
  bool _dnsTesting = false;

  // ===== HTTP 连通性 =====
  final Map<String, _ProbeResult> _httpProbes = {};
  bool _probeTesting = false;

  // ===== 全局加载状态 =====
  bool _loading = false;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await Future.wait<void>([
        _loadWifiInfo(),
        _loadInterfaces(),
      ]);
      // 异步 + 不阻塞主体
      unawaited(_loadPublicIp());
      unawaited(_runDnsTests());
      unawaited(_runHttpProbes());
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _loadWifiInfo() async {
    try {
      _wifiName = await _networkInfo.getWifiName();
      _wifiBSSID = await _networkInfo.getWifiBSSID();
      _wifiIP = await _networkInfo.getWifiIP();
      _wifiGateway = await _networkInfo.getWifiGatewayIP();
      _wifiSubmask = await _networkInfo.getWifiSubmask();
      _wifiIPv6 = await _networkInfo.getWifiIPv6();
    } catch (e) {
      debugPrint('WiFi info error: $e');
    }
  }

  Future<void> _loadInterfaces() async {
    try {
      _interfaces = await NetworkInterface.list(
        includeLoopback: true,
        includeLinkLocal: true,
      );
    } catch (e) {
      debugPrint('Network interfaces error: $e');
    }
  }

  Future<void> _loadPublicIp() async {
    if (!mounted) return;
    setState(() {
      _publicIpLoading = true;
      _publicIpError = null;
    });
    try {
      final resp = await http
          .get(Uri.parse(NetworkConst.publicIpInfoApi))
          .timeout(NetworkConst.httpProbeTimeout);
      if (resp.statusCode == 200) {
        // ipapi.co 返回 json
        final body = resp.body;
        _publicIp = _jsonValue(body, 'ip');
        _publicIpCity = _jsonValue(body, 'city');
        _publicIpRegion = _jsonValue(body, 'region');
        _publicIpCountry = _jsonValue(body, 'country_name');
        _publicIpOrg = _jsonValue(body, 'org');
      } else {
        // fallback：只取纯 IP
        final resp2 = await http
            .get(Uri.parse(NetworkConst.publicIpApi))
            .timeout(NetworkConst.httpProbeTimeout);
        if (resp2.statusCode == 200) {
          _publicIp = _jsonValue(resp2.body, 'ip');
        } else {
          _publicIpError = 'HTTP ${resp.statusCode}';
        }
      }
    } catch (e) {
      _publicIpError = e.toString();
    } finally {
      if (mounted) setState(() => _publicIpLoading = false);
    }
  }

  /// 极简 JSON value 提取，避免引入新依赖
  String? _jsonValue(String json, String key) {
    final pattern = RegExp('"$key"\\s*:\\s*"([^"]*)"');
    final m = pattern.firstMatch(json);
    return m?.group(1);
  }

  Future<void> _runDnsTests() async {
    if (!mounted) return;
    setState(() {
      _dnsTesting = true;
      _dnsResults.clear();
    });

    for (final host in NetworkConst.dnsTestHosts) {
      final sw = Stopwatch()..start();
      try {
        final addrs = await InternetAddress.lookup(host)
            .timeout(NetworkConst.dnsLookupTimeout);
        sw.stop();
        if (mounted) {
          setState(() {
            _dnsResults[host] = _DnsResult(
              host: host,
              ip: addrs.isEmpty ? '—' : addrs.first.address,
              ms: sw.elapsedMilliseconds,
              ok: addrs.isNotEmpty,
            );
          });
        }
      } catch (e) {
        sw.stop();
        if (mounted) {
          setState(() {
            _dnsResults[host] = _DnsResult(
              host: host,
              ip: 'fail',
              ms: sw.elapsedMilliseconds,
              ok: false,
              error: e.toString(),
            );
          });
        }
      }
    }
    if (mounted) setState(() => _dnsTesting = false);
  }

  Future<void> _runHttpProbes() async {
    if (!mounted) return;
    setState(() {
      _probeTesting = true;
      _httpProbes.clear();
    });

    final futures = NetworkConst.httpProbes.map((probe) async {
      final sw = Stopwatch()..start();
      try {
        final resp = await http
            .get(Uri.parse(probe.url))
            .timeout(NetworkConst.httpProbeTimeout);
        sw.stop();
        if (mounted) {
          setState(() {
            _httpProbes[probe.name] = _ProbeResult(
              name: probe.name,
              statusCode: resp.statusCode,
              ms: sw.elapsedMilliseconds,
              ok: resp.statusCode > 0 && resp.statusCode < 400,
            );
          });
        }
      } catch (e) {
        sw.stop();
        if (mounted) {
          setState(() {
            _httpProbes[probe.name] = _ProbeResult(
              name: probe.name,
              statusCode: 0,
              ms: sw.elapsedMilliseconds,
              ok: false,
              error: e.toString(),
            );
          });
        }
      }
    }).toList();

    await Future.wait(futures);
    if (mounted) setState(() => _probeTesting = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '加载失败: $_error',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadAll,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildWifiCard(),
          const SizedBox(height: 12),
          _buildPublicIpCard(),
          const SizedBox(height: 12),
          _buildHttpProbeCard(),
          const SizedBox(height: 12),
          _buildDnsCard(),
          const SizedBox(height: 12),
          _buildInterfacesCard(),
          const SizedBox(height: 12),
          _buildPlatformCard(),
          const SizedBox(height: 12),
          _buildPortsCard(),
        ],
      ),
    );
  }

  // ===== Card builders =====

  Widget _buildWifiCard() {
    return NetworkWidgets.infoCard(
      title: 'WiFi 状态',
      icon: Icons.wifi,
      color: NetworkConst.colorInfo,
      trailing: NetworkWidgets.statusPill(
        _wifiIP != null && _wifiIP!.isNotEmpty ? '在线' : '未连接',
        ok: _wifiIP != null && _wifiIP!.isNotEmpty,
        icon: Icons.wifi,
      ),
      children: [
        NetworkWidgets.infoRow(context, 'SSID', _cleanSsid(_wifiName)),
        NetworkWidgets.infoRow(context, 'BSSID', _wifiBSSID ?? '未知'),
        NetworkWidgets.infoRow(context, '本地 IP', _wifiIP ?? '未知'),
        NetworkWidgets.infoRow(context, '网关', _wifiGateway ?? '未知'),
        NetworkWidgets.infoRow(context, '子网掩码', _wifiSubmask ?? '未知'),
        NetworkWidgets.infoRow(context, 'IPv6', _wifiIPv6 ?? '未知'),
      ],
    );
  }

  Widget _buildPublicIpCard() {
    return NetworkWidgets.infoCard(
      title: '公网 IP',
      icon: Icons.public,
      color: Colors.deepPurple,
      trailing: _publicIpLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _loadPublicIp,
              tooltip: '刷新公网 IP',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: [
        if (_publicIpError != null)
          NetworkWidgets.infoRow(context, '错误', _publicIpError!)
        else ...[
          NetworkWidgets.infoRow(context, '公网 IP', _publicIp ?? '查询中...'),
          NetworkWidgets.infoRow(context, '国家', _publicIpCountry ?? '—'),
          NetworkWidgets.infoRow(context, '省份', _publicIpRegion ?? '—'),
          NetworkWidgets.infoRow(context, '城市', _publicIpCity ?? '—'),
          NetworkWidgets.infoRow(context, '运营商', _publicIpOrg ?? '—'),
        ],
      ],
    );
  }

  Widget _buildHttpProbeCard() {
    return NetworkWidgets.infoCard(
      title: 'HTTP 连通性测试',
      icon: Icons.cloud_done,
      color: Colors.teal,
      trailing: _probeTesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _runHttpProbes,
              tooltip: '重新测试',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: NetworkConst.httpProbes.map((probe) {
        final r = _httpProbes[probe.name];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  probe.name,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                ),
              ),
              if (r == null)
                const Text('...', style: TextStyle(color: Colors.grey))
              else ...[
                Icon(
                  r.ok ? Icons.check_circle : Icons.cancel,
                  color: r.ok
                      ? NetworkConst.colorSuccess
                      : NetworkConst.colorError,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  r.statusCode > 0 ? '${r.statusCode}' : 'fail',
                  style: TextStyle(
                    fontSize: 13,
                    fontFamily: 'monospace',
                    color: r.ok
                        ? NetworkConst.colorSuccess
                        : NetworkConst.colorError,
                  ),
                ),
                const Spacer(),
                Text(
                  '${r.ms}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDnsCard() {
    return NetworkWidgets.infoCard(
      title: 'DNS 解析测试',
      icon: Icons.dns,
      color: Colors.purple,
      trailing: _dnsTesting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : IconButton(
              icon: const Icon(Icons.refresh, size: 18),
              onPressed: _runDnsTests,
              tooltip: '重新解析',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
      children: NetworkConst.dnsTestHosts.map((host) {
        final r = _dnsResults[host];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  host,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (r == null)
                const Text('...', style: TextStyle(color: Colors.grey))
              else ...[
                Icon(
                  r.ok ? Icons.check_circle : Icons.cancel,
                  color: r.ok
                      ? NetworkConst.colorSuccess
                      : NetworkConst.colorError,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SelectableText(
                    r.ip,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: r.ok
                          ? NetworkConst.colorSuccess
                          : NetworkConst.colorError,
                    ),
                  ),
                ),
                Text(
                  '${r.ms}ms',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildInterfacesCard() {
    if (_interfaces.isEmpty) {
      return NetworkWidgets.infoCard(
        title: '网卡列表',
        icon: Icons.settings_ethernet,
        color: Colors.indigo,
        children: const [Text('无可用网卡')],
      );
    }
    return NetworkWidgets.infoCard(
      title: '网卡列表 (${_interfaces.length})',
      icon: Icons.settings_ethernet,
      color: Colors.indigo,
      children: _interfaces.map(_buildInterfaceRow).toList(),
    );
  }

  Widget _buildInterfaceRow(NetworkInterface iface) {
    final isLoopback = iface.name == 'lo' || iface.name == 'loopback';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isLoopback ? Icons.loop : Icons.cable,
                size: 16,
                color: isLoopback ? Colors.grey : Colors.green,
              ),
              const SizedBox(width: 6),
              Text(
                iface.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: isLoopback
                      ? Colors.grey.withValues(alpha: 0.2)
                      : Colors.green.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isLoopback ? 'Loopback' : 'Active',
                  style: TextStyle(
                    fontSize: 10,
                    color: isLoopback ? Colors.grey : Colors.green,
                  ),
                ),
              ),
            ],
          ),
          ...iface.addresses.map((addr) {
            final isIPv4 = addr.type == InternetAddressType.IPv4;
            return Padding(
              padding: const EdgeInsets.only(left: 22, top: 2, bottom: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      isIPv4 ? 'IPv4' : 'IPv6',
                      style: TextStyle(
                        fontSize: 10,
                        color: isIPv4 ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: SelectableText(
                      addr.address,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPlatformCard() {
    return NetworkWidgets.infoCard(
      title: '平台信息',
      icon: Icons.computer,
      color: Colors.brown,
      children: [
        NetworkWidgets.infoRow(context, 'hostname', Platform.localHostname),
        NetworkWidgets.infoRow(
          context,
          'OS',
          '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          mono: false,
        ),
        NetworkWidgets.infoRow(
          context,
          'Dart 版本',
          Platform.version.split(' ').first,
        ),
        NetworkWidgets.infoRow(
          context,
          '时区',
          DateTime.now().timeZoneName,
        ),
      ],
    );
  }

  Widget _buildPortsCard() {
    return NetworkWidgets.infoCard(
      title: '常用端口参考',
      icon: Icons.numbers,
      color: Colors.deepOrange,
      children: NetworkConst.commonPorts
          .map(
            (p) => NetworkWidgets.infoRow(
              context,
              p.name,
              p.port,
              copyable: false,
            ),
          )
          .toList(),
    );
  }

  /// network_info_plus 在某些机型上 SSID 会带 "" 包裹
  String _cleanSsid(String? raw) {
    if (raw == null) return '未知';
    var s = raw;
    if (s.startsWith('"') && s.endsWith('"') && s.length >= 2) {
      s = s.substring(1, s.length - 1);
    }
    return s.isEmpty ? '未知' : s;
  }
}

class _DnsResult {
  final String host;
  final String ip;
  final int ms;
  final bool ok;
  final String? error;

  _DnsResult({
    required this.host,
    required this.ip,
    required this.ms,
    required this.ok,
    this.error,
  });
}

class _ProbeResult {
  final String name;
  final int statusCode;
  final int ms;
  final bool ok;
  final String? error;

  _ProbeResult({
    required this.name,
    required this.statusCode,
    required this.ms,
    required this.ok,
    this.error,
  });
}
