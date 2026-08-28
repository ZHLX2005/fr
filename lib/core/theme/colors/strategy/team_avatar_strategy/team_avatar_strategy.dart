// Layer 2.5: 团队卡 6 头像色策略契约。
//
// 6 头像色是身份识别色（卧底/狼人/预言家/守卫/村民/女巫等），
// 跨主题锁定——切 zen/purple 不应该让卧底变绿、狼人变紫。

import 'package:flutter/material.dart';

@immutable
abstract class TeamAvatarStrategy {
  const TeamAvatarStrategy();

  /// 6 头像色（按角色索引 mod 6 取色）。
  List<Color> get avatarColors;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamAvatarStrategy &&
          runtimeType == other.runtimeType &&
          _listEq(avatarColors, other.avatarColors);

  @override
  int get hashCode => Object.hashAll(avatarColors);

  static bool _listEq(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}