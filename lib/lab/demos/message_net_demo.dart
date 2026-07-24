import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/net_engine_biz/net_engine_discovery_host.dart';

/// MessageNet 跨网络消息通讯 Demo
///
/// 底层基于 `lib/core/net_engine/` 引擎（Lan/Relay 双后端）：
/// - LAN 模式：UDP 多播发现 + HTTP P2P 消息（同 WiFi/同子网）
/// - Relay 模式：HTTP 控制面（房间号）+ WS 多路复用消息（跨网络）
///
/// 业务层零连接代码：直接渲染 [NetEngineBizHostPage]，由 net_engine widget
/// 处理发现和连接。
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
    return const NetEngineBizHostPage();
  }
}

void registerMessageNetDemo() {
  demoRegistry.register(MessageNetDemo());
}
