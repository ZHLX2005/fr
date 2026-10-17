// Layer 1 — 团队卡 6 头像色常量（识别色锁定，跨主题不变）。

import 'package:flutter/material.dart';

class TeamColors {
  TeamColors._();

  /// 6 头像色（按角色索引 mod 6 取色，跨主题锁定）
  ///
  /// 2026-10 自旧 BaseColors.avatar1..6 别名链内联（视觉零变化）；
  /// 单一定义处即本文件。
  static const List<Color> avatarColors = [
    Color(0xFF00BCD4), // avatar1
    Color(0xFFFFC107), // avatar2
    Color(0xFF9C27B0), // avatar3
    Color(0xFF4CAF50), // avatar4
    Color(0xFF1976D2), // avatar5
    Color(0xFFFF9800), // avatar6
  ];
}
