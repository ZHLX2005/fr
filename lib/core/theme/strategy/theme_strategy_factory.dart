// Layer 2: 编译期安全工厂。
//
// 用 switch 表达式映射 AppThemeMode → ColorStrategy，杜绝运行时 KeyError。
// v7 简化：所有主题统一走 DefaultColorStrategy（无特例策略）。

import 'package:flutter/material.dart';

import 'color_strategy.dart';
import 'default_color_strategy.dart';

class ThemeStrategyFactory {
  /// 工厂入口：所有主题统一走 DefaultColorStrategy。
  static ColorStrategy create(ColorScheme scheme) {
    return DefaultColorStrategy.of(scheme);
  }
}