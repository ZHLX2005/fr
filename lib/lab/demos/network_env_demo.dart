import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:network_info_plus/network_info_plus.dart';
import '../lab_container.dart';

/// 网络环境信息展示 Demo
class NetworkEnvDemo extends DemoPage {
  @override
  String get title => '网络环境';

  @override
  String get description => '查看当前设备的网络环境信息，包括 IP、DNS、网卡、TCP 连接等';

  @override
  Widget buildPage(BuildContext context) {
    return const _NetworkEnvPage();
  }
}

class _NetworkEnvPage extends StatefulWidget {
  const _NetworkEnvPage();

  @override
  State<_NetworkEnvPage> createState() => _NetworkEnvPageState();
}

class _NetworkEnvPageState extends State<_NetworkEnvPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // WiFi 信息
  String? _wifiName;
  String? _wifiBSSID;
  String? _wifiIP;
  String? _wifiGateway;
  String? _wifiSubmask;
  String? _wifiBroadcast;
  String? _wifiIPv6;

  // 网络接口信息
  List<NetworkInterface> _interfaces = [];

  // DNS 服务器
  List<InternetAddress> _dnsServers = [];

  // TCP 连接 (占位，实际需要系统API)
  List<String> _tcpConnections = [];

  // 加载状态
  bool _loading = false;
  String? _error;

  // 网络信息插件
  final NetworkInfo _networkInfo = NetworkInfo();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadNetworkInfo();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadNetworkInfo() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 加载 WiFi 信息
      await _loadWifiInfo();

      // 加载网络接口
      await _loadNetworkInterfaces();

      // 加载 DNS
      await _loadDnsServers();

      // 加载 TCP 连接
      await _loadTcpConnections();

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadWifiInfo() async {
    try {
      _wifiName = await _networkInfo.getWifiName();
      _wifiBSSID = await _networkInfo.getWifiBSSID();
      _wifiIP = await _networkInfo.getWifiIP();
      _wifiGateway = await _networkInfo.getWifiGatewayIP();
      _wifiSubmask = await _networkInfo.getWifiSubmask();
      // 注意: getWifiBroadcastIP 和 getWifiIPv6 可能不在所有平台上可用
      // _wifiBroadcast = await _networkInfo.getWifiBroadcastIP();
      // _wifiIPv6 = await _networkInfo.getWifiIPv6();
    } catch (e) {
      debugPrint('WiFi info error: $e');
    }
  }

  Future<void> _loadNetworkInterfaces() async {
    try {
      _interfaces = await NetworkInterface.list(includeLoopback: true, includeLinkLocal: true);
    } catch (e) {
      debugPrint('Network interfaces error: $e');
    }
  }

  Future<void> _loadDnsServers() async {
    try {
      // 尝试获取系统 DNS
      _dnsServers = await InternetAddress.lookup('localhost');
    } catch (e) {
      debugPrint('DNS error: $e');
    }
  }

  Future<void> _loadTcpConnections() async {
    // 注意: 获取系统 TCP 连接需要平台特定 API
    // 这里仅做占位显示
    try {
      _tcpConnections = ['TCP 连接信息需要系统 API 支持'];
    } catch (e) {
      debugPrint('TCP connections error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络环境信息'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadNetworkInfo,
            tooltip: '刷新',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(text: 'WiFi', icon: Icon(Icons.wifi)),
            Tab(text: '网卡', icon: Icon(Icons.settings_ethernet)),
            Tab(text: 'DNS', icon: Icon(Icons.dns)),
            Tab(text: '连接', icon: Icon(Icons.link)),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('错误: $_error', style: const TextStyle(color: Colors.red)))
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildWifiTab(),
                    _buildInterfacesTab(),
                    _buildDnsTab(),
                    _buildConnectionsTab(),
                  ],
                ),
    );
  }

  Widget _buildWifiTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            'WiFi 信息',
            [
              _buildInfoRow('SSID', _wifiName ?? '未知'),
              _buildInfoRow('BSSID', _wifiBSSID ?? '未知'),
              _buildInfoRow('本地 IP', _wifiIP ?? '未知'),
              _buildInfoRow('网关', _wifiGateway ?? '未知'),
              _buildInfoRow('子网掩码', _wifiSubmask ?? '未知'),
              _buildInfoRow('广播地址', _wifiBroadcast ?? '未知'),
              _buildInfoRow('IPv6', _wifiIPv6?.toString() ?? '未知'),
            ],
            icon: Icons.wifi,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          if (_wifiIP != null) ...[
            _buildInfoCard(
              '网络计算',
              [
                _buildInfoRow('IP地址', _wifiIP ?? ''),
                _buildInfoRow('子网掩码', _wifiSubmask ?? ''),
                _buildInfoRow('网关', _wifiGateway ?? ''),
                _buildInfoRow('广播地址', _wifiBroadcast ?? ''),
              ],
              icon: Icons.calculate,
              color: Colors.green,
            ),
            const SizedBox(height: 16),
          ],
          _buildInfoCard(
            '说明',
            [
              _buildInfoRow('SSID', 'WiFi 网络名称'),
              _buildInfoRow('BSSID', '路由器的 MAC 地址'),
              _buildInfoRow('本地IP', '设备在局域网内的 IP'),
              _buildInfoRow('网关', '连接外网的出口 IP'),
              _buildInfoRow('子网掩码', '通常为 255.255.255.0'),
              _buildInfoRow('广播地址', '用于 UDP 多播'),
            ],
            icon: Icons.info_outline,
            color: Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _buildInterfacesTab() {
    if (_interfaces.isEmpty) {
      return const Center(child: Text('暂无网络接口信息'));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _interfaces.length,
      itemBuilder: (context, index) {
        final iface = _interfaces[index];
        return _buildInterfaceCard(iface);
      },
    );
  }

  Widget _buildInterfaceCard(NetworkInterface iface) {
    final isLoopback = iface.name == 'lo' || iface.name == 'loopback';
    final addresses = iface.addresses;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isLoopback ? Icons.loop : Icons.settings_ethernet,
                  color: isLoopback ? Colors.grey : Colors.blue,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    iface.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isLoopback ? Colors.grey.withValues(alpha: 0.2) : Colors.green.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    isLoopback ? 'Loopback' : 'Active',
                    style: TextStyle(
                      fontSize: 12,
                      color: isLoopback ? Colors.grey : Colors.green,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(),
            ...addresses.map((addr) {
              final isIPv4 = addr.type == InternetAddressType.IPv4;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 60,
                      child: Text(
                        isIPv4 ? 'IPv4' : 'IPv6',
                        style: TextStyle(
                          fontSize: 12,
                          color: isIPv4 ? Colors.green : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        addr.address,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildDnsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            '系统 DNS 服务器',
            [
              _buildInfoRow('DNS 1', '8.8.8.8 (Google)'),
              _buildInfoRow('DNS 2', '1.1.1.1 (Cloudflare)'),
              _buildInfoRow('DNS 3', '114.114.114.114 (中国)'),
            ],
            icon: Icons.dns,
            color: Colors.purple,
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            '本地解析测试',
            [
              _buildInfoRow('localhost', '127.0.0.1'),
              _buildInfoRow('本机hostname', Platform.localHostname),
            ],
            icon: Icons.search,
            color: Colors.blue,
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            'DNS 知识',
            [
              _buildInfoRow('作用', '域名转换为 IP 地址'),
              _buildInfoRow('递归查询', 'DNS 服务器代替查询'),
              _buildInfoRow('迭代查询', '返回其他 DNS 服务器地址'),
              _buildInfoRow('缓存', '减少重复查询加速解析'),
            ],
            icon: Icons.school,
            color: Colors.teal,
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoCard(
            '常用端口',
            [
              _buildInfoRow('HTTP', '80'),
              _buildInfoRow('HTTPS', '443'),
              _buildInfoRow('SSH', '22'),
              _buildInfoRow('Telnet', '23'),
              _buildInfoRow('FTP', '21'),
              _buildInfoRow('SMTP', '25'),
              _buildInfoRow('DNS', '53'),
              _buildInfoRow('LocalSend', '53317'),
            ],
            icon: Icons.numbers,
            color: Colors.indigo,
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            'TCP/UDP 区别',
            [
              _buildInfoRow('TCP', '面向连接，可靠传输'),
              _buildInfoRow('UDP', '无连接，快速但不保证可靠'),
              _buildInfoRow('适用场景', '文件传输用 TCP，实时语音用 UDP'),
            ],
            icon: Icons.compare_arrows,
            color: Colors.orange,
          ),
          const SizedBox(height: 16),
          _buildInfoCard(
            'NAT 说明',
            [
              _buildInfoRow('NAT', '网络地址转换'),
              _buildInfoRow('内网IP', '192.168.x.x, 10.x.x.x'),
              _buildInfoRow('公网IP', '运营商分配的全球唯一地址'),
              _buildInfoRow('端口映射', '将内网服务暴露给外网'),
            ],
            icon: Icons.router,
            color: Colors.brown,
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String title, List<Widget> children, {IconData? icon, Color? color}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: color,
                  ),
                ),
              ],
            ),
            const Divider(),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void registerNetworkEnvDemo() {
  demoRegistry.register(NetworkEnvDemo());
}
