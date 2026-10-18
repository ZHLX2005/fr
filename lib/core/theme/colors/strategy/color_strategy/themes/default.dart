// Layer 3 — DefaultColorStrategy（基线）：从 ColorScheme 派生所有 6 角色。
//
// 单一实现：5 主题切换 = 换 scheme 实例（数据层），strategy 不感知主题。
// 同一 scheme 调用 .of() 多次返回同一实例（scheme 相等缓存去重，避免 GC 抖动）。

import 'package:flutter/material.dart';

import '../color_strategy.dart';

class DefaultColorStrategy extends ColorStrategy {
  @override
  final ColorScheme scheme;

  const DefaultColorStrategy({required this.scheme});

  static DefaultColorStrategy? _cached;

  /// 工厂：scheme 相等时复用缓存实例（避免 GC 抖动）。
  factory DefaultColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) return cached;
    final instance = DefaultColorStrategy(scheme: scheme);
    _cached = instance;
    return instance;
  }

  @override
  Color get accent => scheme.primary;

  @override
  Color get surface => scheme.surface;

  @override
  Color get outline => scheme.outline;

  @override
  Color get text => scheme.onSurface;

  @override
  Color get textMuted => scheme.onSurfaceVariant;

  @override
  Color get danger => scheme.error;
}