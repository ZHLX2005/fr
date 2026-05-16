import 'package:flutter/material.dart';

import '../lab_container.dart';
import 'network/network_ble_tab.dart';
import 'network/network_env_tab.dart';
import 'network/network_http_tab.dart';
import 'network/network_ws_tab.dart';

/// 网络综合 Demo —— 一个 Demo 覆盖网络全场景
///
/// Tab：环境 / HTTP / WebSocket / 蓝牙 BLE。
class NetworkDemo extends DemoPage {
  @override
  String get title => '网络';

  @override
  String get description => '网络环境/HTTP/WebSocket/蓝牙 BLE 综合调试';

  @override
  Widget buildPage(BuildContext context) {
    return const _NetworkDemoPage();
  }
}

class _NetworkDemoPage extends StatefulWidget {
  const _NetworkDemoPage();

  @override
  State<_NetworkDemoPage> createState() => _NetworkDemoPageState();
}

class _NetworkDemoPageState extends State<_NetworkDemoPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = <Tab>[
    Tab(text: '环境', icon: Icon(Icons.network_check)),
    Tab(text: 'HTTP', icon: Icon(Icons.http)),
    Tab(text: 'WebSocket', icon: Icon(Icons.cable)),
    Tab(text: '蓝牙', icon: Icon(Icons.bluetooth)),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TabBar(controller: _tabController, tabs: _tabs),
      body: TabBarView(
        controller: _tabController,
        children: const [
          NetworkEnvTab(),
          NetworkHttpTab(),
          NetworkWsTab(),
          NetworkBleTab(),
        ],
      ),
    );
  }
}

void registerNetworkDemo() {
  demoRegistry.register(NetworkDemo());
}
