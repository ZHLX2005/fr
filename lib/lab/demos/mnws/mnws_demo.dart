// lib/lab/demos/mnws/mnws_demo.dart
//
// Lab 注册入口：mn-ws 双向桥（把电脑上的 HTTP 服务经 WebSocket 桥给远端客户端）。
//
// 分层（mn-ws 是一个完整的域）：
//   · lib/api/mnws/        —— 生命周期 + 元数据（配置 / 端点 / 模型 / 凭据 / 编排）
//       └─ lib/api/mnws/<应用>/ —— 每个应用一个子目录（接口客户端）
//   · lib/lab/demos/mnws/  —— 这个子目录负责提供应用的 UI
//       └─ lib/lab/demos/mnws/<应用>/ —— 每个应用一个子目录（界面）

import 'package:flutter/material.dart';

import '../../lab_container.dart';
import 'mnws_home_page.dart';

/// Lab demo 注册项
class MnWsDemo extends DemoPage {
  @override
  String get title => 'mn-ws 双向桥';

  @override
  String get slug => 'mn-ws';

  @override
  String get description => '统一登录后按电脑分组看应用 · 点进去用原生界面调它';

  @override
  DemoType get type => DemoType.tool;

  @override
  Widget buildPage(BuildContext context) => const MnWsHomePage();
}

void registerMnWsDemo() => demoRegistry.register(MnWsDemo());
