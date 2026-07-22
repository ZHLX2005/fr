// lib/core/localnet_biz/localnet_discovery_host.dart
//
// LocalNet biz 入口 — 演示 localnet 一体化 2 人房聊天（开箱即用）
//
// 业务层 0 逻辑：直接调 fw.RelayRoomChatWidget（discovery+transport+room+chat 都包好）

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

/// biz 入口 — 直接渲染 localnet 的 2 人房聊天 widget
class LocalnetBizHostPage extends StatelessWidget {
  const LocalnetBizHostPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalNet Demo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => fw.LocalnetSettingsPage(
                  mode: fw.MessageNetMode.relay,
                  multicastPort: 5678,
                  multicastAddress: '239.255.255.255',
                  relayUrl: 'http://47.110.80.47:8988',
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.bug_report),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const fw.LocalnetDebugPage()),
            ),
          ),
        ],
      ),
      body: const fw.RelayRoomChatWidget(
        relayUrl: 'http://47.110.80.47:8988',
      ),
    );
  }
}
