// lib/lab/demos/mn_ws_demo.dart
//
// Lab 注册入口：mn-ws 双向桥（把本机 nx 服务经 WebSocket 桥给远端 HTTP 客户端）。
// 业务实现在 core/mnws/ 目录（config / endpoint / service / models 分层）。

import 'package:flutter/material.dart';

import '../lab_container.dart';
import '../../core/mnws/mnws.dart';

/// Lab demo 注册项
class MnWsDemo extends DemoPage {
  @override
  String get title => 'mn-ws 双向桥';

  @override
  String get slug => 'mn-ws';

  @override
  String get description => '统一登录后看服务端支持哪些应用 · 经桥调本机 nx 服务';

  @override
  DemoType get type => DemoType.tool;

  @override
  Widget buildPage(BuildContext context) => const MnWsPage();
}

void registerMnWsDemo() => demoRegistry.register(MnWsDemo());
