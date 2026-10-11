// 快捷导航根页 vs push 子页的路由判定。
//
// MainScreen 用 IndexedStack 挂钉选页：与壳同属一条 Navigator route，
// `canPop == false`。此时不应画「返回」——点了也只是 maybePop 空转。
// 从 Lab / 游戏中心 push 进来时 `canPop == true`，返回照常显示。

import 'package:flutter/material.dart';

/// 当前页是否还能往 Navigator 栈下 pop（非快捷底栏根页）。
bool navCanPop(BuildContext context) =>
    ModalRoute.of(context)?.canPop ?? false;

extension NavRouteContext on BuildContext {
  /// 同 [navCanPop]。
  bool get navCanPop => ModalRoute.of(this)?.canPop ?? false;
}
