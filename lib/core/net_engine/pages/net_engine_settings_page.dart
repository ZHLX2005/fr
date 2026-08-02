import 'package:flutter/material.dart';

import 'package:xiaodouzi_fr/core/net_engine/lan/lan_discovery.dart';

import '../net_engine_types.dart';

/// LAN 设置壳（v3 移除 Relay 模式独立设置；v3 直接使用 `RelayV3Widget`）
///
/// 业务侧零配置代码 — 只渲染对应 Discovery 的 buildSettingsPage()。
class NetEngineSettingsPage extends StatelessWidget {
  const NetEngineSettingsPage({
    super.key,
    this.mode = MessageNetMode.lan,
    this.multicastPort = 5678,
    this.multicastAddress = '239.255.255.255',
  });

  final MessageNetMode mode;
  final int multicastPort;
  final String multicastAddress;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: LanDiscovery(
        multicastPort: multicastPort,
        multicastAddress: multicastAddress,
      ).buildSettingsPage(
        onSaved: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
        ),
      ),
    );
  }
}
