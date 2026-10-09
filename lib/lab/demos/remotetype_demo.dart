// lib/lab/demos/remotetype_demo.dart
//
// Lab 注册入口：远程输入（手机 → 电脑焦点输入框，端到端加密 + 实时对齐）。
// 业务实现在 demos/remotetype/ 目录；配对与加密协议见其目录内注释。

import 'package:flutter/material.dart';

import '../lab_container.dart';
import 'remotetype/rt_page.dart';

/// Lab demo 注册项
class RemoteTypeDemo extends DemoPage {
  @override
  String get title => '远程输入（联机）';

  @override
  String get slug => 'remotetype';

  @override
  String get description => '手机语音/打字 → 电脑焦点输入框实时对齐（含删除）· 端到端加密';

  @override
  bool get preferFullScreen => true;

  @override
  DemoType get type => DemoType.tool;

  @override
  Widget buildPage(BuildContext context) => const RemoteTypePage();
}

void registerRemoteTypeDemo() => demoRegistry.register(RemoteTypeDemo());
