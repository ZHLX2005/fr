// Lab 下拉面板的性能日志开关。
//
// 面板同时跑手势、动画、状态机三条线，出问题时最需要的是"这一帧到底发生了
// 什么"。开关默认关闭，打开后只在 debug 模式打印，release 里连字符串都不会拼。

import 'package:flutter/foundation.dart';

/// 打开后会打印面板的手势/动画/状态迁移与慢帧日志。
const bool kLabPanelPerfDebug = false;

void labPerfLog(String message) {
  if (kLabPanelPerfDebug && kDebugMode) {
    debugPrint('[LabPagePerf] $message');
  }
}
