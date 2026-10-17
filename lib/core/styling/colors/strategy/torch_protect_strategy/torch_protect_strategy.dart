// Layer 2.5: 灯具护眼色策略契约。
//
// 4 个保护色（暖黄/暖橙/中性/冷白）从 ColorScheme 派生；
// 10 个补光预设为实际输出色（主题豁免，固定 hex，见 TorchColors.protectPresets）。

import 'package:flutter/material.dart';

@immutable
abstract class TorchProtectStrategy {
  const TorchProtectStrategy();

  ColorScheme get scheme;

  Color get protectWarmYellow;
  Color get protectWarmOrange;
  Color get protectNeutral;
  Color get protectCoolWhite;

  /// 10 种护眼色预设（torch 灯具选择，固定补光色）
  List<Color> get protectPresets;

  /// 10 种护眼色名称（与 protectPresets 一一对应）
  List<String> get protectPresetNames;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TorchProtectStrategy &&
          runtimeType == other.runtimeType &&
          scheme == other.scheme &&
          protectWarmYellow == other.protectWarmYellow &&
          protectWarmOrange == other.protectWarmOrange &&
          protectNeutral == other.protectNeutral &&
          protectCoolWhite == other.protectCoolWhite &&
          _listEq(protectPresets, other.protectPresets) &&
          _listStrEq(protectPresetNames, other.protectPresetNames);

  @override
  int get hashCode => Object.hash(
    scheme, protectWarmYellow, protectWarmOrange,
    protectNeutral, protectCoolWhite,
    Object.hashAll(protectPresets),
    Object.hashAll(protectPresetNames),
  );

  static bool _listEq(List<Color> a, List<Color> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static bool _listStrEq(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}