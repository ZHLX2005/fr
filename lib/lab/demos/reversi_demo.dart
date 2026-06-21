import 'package:flutter/material.dart';
import '../lab_container.dart';
import '../../core/reversi/reversi.dart';

/// 黑白翻转棋（Othello / Reversi）Demo
///
/// 方案 b 导入：core/reversi 提供完整模块，本文件仅做 DemoPage 注册入口。
class ReversiDemo extends DemoPage {
  @override
  String get title => '黑白翻转棋';

  @override
  String get description => '经典 Othello：落子夹击翻转，双方各可悔棋';

  @override
  DemoType get type => DemoType.game;

  @override
  Widget buildPage(BuildContext context) {
    return const ReversiPage();
  }
}

void registerReversiDemo() {
  demoRegistry.register(ReversiDemo());
}
