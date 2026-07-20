import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/localnet_biz/pages/localnet_discover_page.dart';

/// MessageNet 跨网络消息通讯 Demo
///
/// 底层基于 `lib/core/localnet/` 引擎（Lan/Relay 双后端）：
/// - LAN 模式：UDP 多播发现 + HTTP P2P 消息（同 WiFi/同子网）
/// - Relay 模式：HTTP 控制面（房间号）+ WS 多路复用消息（跨网络）
///
/// 业务层 Service 见 `lib/core/localnet_biz/localnet_service.dart`。
class MessageNetDemo extends DemoPage {
  @override
  String get title => 'MessageNet';

  @override
  String get slug => 'message_net';

  @override
  String get description => '局域网 / 跨网络消息通讯（LAN + Relay）';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const LocalnetDiscoverPage();
  }
}

void registerMessageNetDemo() {
  demoRegistry.register(MessageNetDemo());
}
