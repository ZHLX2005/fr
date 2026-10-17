// Layer 1: 不可变 ColorStrategy 契约。
//
// 核心约束：
// 1. @immutable：子类必须 const 构造
// 2. == / hashCode 重写：让 Flutter 识别相同策略，避免不必要 rebuild
// 3. 颜色角色：6 个核心角色 + scheme 全量兜底

import 'package:flutter/material.dart';

@immutable
abstract class ColorStrategy {
  const ColorStrategy();

  /// 主色 / accent（按钮、icon 选中、tag 高亮）
  Color get accent;

  /// 容器底色（卡片、对话框、surface 区域）
  Color get surface;

  /// 边框色（统一 outline 2px 边框）
  Color get outline;

  /// 主文字色（标题、正文）
  Color get text;

  /// 次文字色（副标题、弱化文字）
  Color get textMuted;

  /// 破坏/错误色（删除按钮、错误状态）
  Color get danger;

  /// 全量 ColorScheme 兜底：核心 6 角色之外的扩展角色
  /// （primaryContainer / onPrimary / surfaceContainerHighest / tertiary 等）
  /// 通过 `context.colors.scheme.X` 访问。
  ColorScheme get scheme;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ColorStrategy &&
          runtimeType == other.runtimeType &&
          accent == other.accent &&
          surface == other.surface &&
          outline == other.outline &&
          text == other.text &&
          textMuted == other.textMuted &&
          danger == other.danger;

  @override
  int get hashCode =>
      Object.hash(accent, surface, outline, text, textMuted, danger);
}