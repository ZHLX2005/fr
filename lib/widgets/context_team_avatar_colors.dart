// BuildContext 扩展：`context.teamAvatar` 快捷访问 TeamAvatarStrategy。
//
//   context.teamAvatar   → 团队卡 6 头像色（识别色锁定）

import 'package:flutter/material.dart';

import '../core/theme/extensions/team_avatar_strategy_extension.dart';
import '../core/theme/colors/strategy/team_avatar_strategy/team_avatar_strategy.dart';
import '../core/theme/colors/strategy/team_avatar_strategy/themes/default.dart';

extension TeamAvatarColorContext on BuildContext {
  /// 当前生效的 TeamAvatarStrategy（双层兜底，绝不返回 null）。
  TeamAvatarStrategy get teamAvatar {
    final ext = Theme.of(this).extension<TeamAvatarStrategyExtension>();
    if (ext != null) return ext.strategy;
    return const DefaultTeamAvatarStrategy();
  }
}