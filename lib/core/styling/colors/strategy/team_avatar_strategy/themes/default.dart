// Layer 2 — DefaultTeamAvatarStrategy：6 头像色从 tokens/color/team 锁定。

import 'package:flutter/material.dart';

import '../../../../tokens/color/team/team.dart';
import '../team_avatar_strategy.dart';

class DefaultTeamAvatarStrategy extends TeamAvatarStrategy {
  const DefaultTeamAvatarStrategy();

  @override
  List<Color> get avatarColors => TeamColors.avatarColors;
}