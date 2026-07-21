import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import '../localnet_types.dart';

/// LAN / Relay 综合设置壳
///
/// 业务侧零配置代码 — 只渲染对应 Discovery 的 buildSettingsPage()。
class LocalnetSettingsPage extends StatelessWidget {
  const LocalnetSettingsPage({
    super.key,
    required this.mode,
    this.multicastPort = 5678,
    this.multicastAddress = '239.255.255.255',
    this.relayUrl = 'http://47.110.80.47:8988',
  });

  final MessageNetMode mode;
  final int multicastPort;
  final String multicastAddress;
  final String relayUrl;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: mode == MessageNetMode.lan
          ? fw.LanDiscovery(
              multicastPort: multicastPort,
              multicastAddress: multicastAddress,
            ).buildSettingsPage(
              onSaved: () =>
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
                  ),
            )
          : fw.RelayDiscovery(relayUrl: relayUrl).buildSettingsPage(
              onSaved: () =>
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已保存'), duration: Duration(seconds: 1)),
                  ),
            ),
    );
  }
}
