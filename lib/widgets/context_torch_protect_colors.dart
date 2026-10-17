// BuildContext 扩展：`context.torchProtect` 快捷访问 TorchProtectColorStrategy。
//
//   context.torchProtect → 灯具护眼色（4 环境保护色跟主题 + 10 固定补光预设）

import 'package:flutter/material.dart';

import '../core/styling/extensions/torch_protect_color_strategy_extension.dart';
import '../core/styling/colors/strategy/torch_protect_color_strategy/torch_protect_color_strategy.dart';
import '../core/styling/colors/strategy/torch_protect_color_strategy/themes/default.dart';

extension TorchProtectColorContext on BuildContext {
  /// 当前生效的 TorchProtectColorStrategy（双层兜底，绝不返回 null）。
  TorchProtectColorStrategy get torchProtect {
    final ext = Theme.of(this).extension<TorchProtectColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultTorchProtectColorStrategy.of(Theme.of(this).colorScheme);
  }
}