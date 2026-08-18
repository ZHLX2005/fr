// BuildContext 扩展：`context.colors` 快捷访问 ColorStrategy。
//
// 三层兜底（与 Base* 组件一致）：
//   1. Theme.of(context).extension<ColorStrategyExtension>()（全局注入）
//   2. DefaultColorStrategy.of(scheme)（终极兜底，绝不崩溃）
//
// 用法：
//   final c = context.colors;
//   Container(color: c.accent)                      // 核心角色
//   Text('Hi', style: TextStyle(color: c.text))     // 核心角色
//   Container(color: c.scheme.primaryContainer)     // 扩展角色

import 'package:flutter/material.dart';

import '../core/theme/extensions/color_strategy_extension.dart';
import '../core/theme/strategy/color_strategy.dart';
import '../core/theme/strategy/default_color_strategy.dart';

extension ColorStrategyContext on BuildContext {
  /// 当前生效的 ColorStrategy（三层兜底，绝不返回 null）。
  ColorStrategy get colors {
    final ext = Theme.of(this).extension<ColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultColorStrategy.of(Theme.of(this).colorScheme);
  }
}