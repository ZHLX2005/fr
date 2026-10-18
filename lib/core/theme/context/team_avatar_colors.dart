// BuildContext 扩展：`context.teamAvatar` 快捷访问 TeamAvatarColorStrategy。
//
//   context.teamAvatar   → 团队卡 6 头像色（识别色锁定）

import 'package:flutter/material.dart';

import '../extensions/team_avatar_color_strategy_extension.dart';
import '../colors/strategy/team_avatar_color_strategy/team_avatar_color_strategy.dart';
import '../colors/strategy/team_avatar_color_strategy/themes/default.dart';

extension TeamAvatarColorContext on BuildContext {
  /// 当前生效的 TeamAvatarColorStrategy（双层兜底，绝不返回 null）。
  TeamAvatarColorStrategy get teamAvatar {
    final ext = Theme.of(this).extension<TeamAvatarColorStrategyExtension>();
    if (ext != null) return ext.strategy;
    return const DefaultTeamAvatarColorStrategy();
  }
}