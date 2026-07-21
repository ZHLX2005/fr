// lib/lab/demos/team_card/team_card_types.dart
// 团建卡牌模块共享模型

import 'package:flutter/material.dart';

/// 身份定义（可编辑）
class RoleDef {
  RoleDef({required this.label, this.count = 1, this.key})
      : nameCtrl = TextEditingController(text: label),
        countCtrl = TextEditingController(text: count.toString());

  String label;
  int count;
  final String? key;
  final TextEditingController nameCtrl;
  final TextEditingController countCtrl;

  /// 从 controller 同步数据到字段（编辑时实时）
  void sync() {
    label = nameCtrl.text;
    count = int.tryParse(countCtrl.text) ?? 1;
  }

  void dispose() {
    nameCtrl.dispose();
    countCtrl.dispose();
  }
}

/// 发牌结果中的一张卡牌
class CardInfo {
  final String deviceId;
  final String alias;
  final String role;
  CardInfo({required this.deviceId, required this.alias, required this.role});
}

/// 身份颜色映射
Color roleColor(ThemeData theme, String role) {
  if (role == '卧底' || role == '狼人') return theme.colorScheme.error;
  if (role == '预言家') return Colors.blue;
  if (role == '女巫') return Colors.purple;
  return theme.colorScheme.primary;
}
