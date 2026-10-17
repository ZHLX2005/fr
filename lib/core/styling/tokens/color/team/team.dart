// Layer 1 — 团队卡 6 头像色常量（识别色锁定，跨主题不变）。

import 'package:flutter/material.dart';
import '../base/base.dart';

class TeamColors {
  TeamColors._();

  /// 6 头像色（按角色索引 mod 6 取色）
  static const List<Color> avatarColors = [
    BaseColors.avatar1, BaseColors.avatar2, BaseColors.avatar3,
    BaseColors.avatar4, BaseColors.avatar5, BaseColors.avatar6,
  ];
}