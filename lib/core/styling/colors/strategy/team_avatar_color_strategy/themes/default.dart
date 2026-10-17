// Layer 2 — DefaultTeamAvatarColorStrategy：6 头像色从 tokens/color/team 锁定。

import 'package:flutter/material.dart';

import '../../../../tokens/color/team.dart';
import '../team_avatar_color_strategy.dart';

class DefaultTeamAvatarColorStrategy extends TeamAvatarColorStrategy {
  const DefaultTeamAvatarColorStrategy();

  @override
  List<Color> get avatarColors => TeamColors.avatarColors;
}