import 'package:flutter/material.dart';

import '../../lab_container.dart';
import 'recorder_page.dart';

// re-export 控制器常量供 widget 入口 / handler 引用,
// 避免 handler / page 重复写 enum。
export 'const_recorder.dart' show RecorderState, RecorderPermissionStatus;
export 'recorder_page.dart' show recorderPageKey, markRecorderAutoStart, recorderAutoStartPending;
// RecorderController 不在 export 列表 —— 避免 handler 引入 controller 拖入
// 整个录音栈(权限/文件系统),handler 只关心 key + autostart flag。

/// 录音机 Demo 入口 —— Lab 页网格里的卡片。
///
/// slug 命名:纯 ASCII 小写 + 连字符(`recorder`),与 widget 深链
/// `fr://lab/demo/recorder` 严格对齐。
/// 设计文档:[references/Flutter-fr路由-注册规范与防腐蚀.md]
class RecorderDemo extends DemoPage {
  @override
  String get title => '录音机';

  @override
  String get slug => 'recorder';

  @override
  String get description => '一键录音并保存到本地(v1 仅落盘到 app 沙盒)';

  /// RecorderDemoPage 已有自己的 AppBar,不再要 Lab 默认 wrapper。
  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) {
    return const RecorderDemoPage();
  }
}

/// Lab bootstrap 调用入口。
///
/// 在 `lib/lab/lab_bootstrap.dart` 的 `registerAllDemos()` 内追加一行
/// `registerRecorderDemo();` 即可挂上。
void registerRecorderDemo() {
  demoRegistry.register(RecorderDemo());
}