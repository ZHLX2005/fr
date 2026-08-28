// BuildContext 扩展：`context.torchProtect` 快捷访问 TorchProtectStrategy。
//
//   context.torchProtect → 灯具护眼色（4 保护色 + 10 预设，跟主题）

import 'package:flutter/material.dart';

import '../core/theme/extensions/torch_protect_strategy_extension.dart';
import '../core/theme/colors/strategy/torch_protect_strategy/torch_protect_strategy.dart';
import '../core/theme/colors/strategy/torch_protect_strategy/themes/default.dart';

extension TorchProtectColorContext on BuildContext {
  /// 当前生效的 TorchProtectStrategy（双层兜底，绝不返回 null）。
  TorchProtectStrategy get torchProtect {
    final ext = Theme.of(this).extension<TorchProtectStrategyExtension>();
    if (ext != null) return ext.strategy;
    return DefaultTorchProtectStrategy.of(Theme.of(this).colorScheme);
  }
}