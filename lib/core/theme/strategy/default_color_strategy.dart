// 默认 ColorStrategy：完全跟 ColorScheme。
//
// 切到任何主题时（墨青/夜间/茶禅...），普通组件读这个策略，
// 颜色完全由当前 ColorScheme 决定。

import 'package:flutter/material.dart';

import 'color_strategy.dart';

class DefaultColorStrategy extends ColorStrategy {
  @override
  final ColorScheme scheme;

  // ★ 单例缓存：相同 scheme 复用同一实例，避免 GC 抖动
  static DefaultColorStrategy? _cached;

  factory DefaultColorStrategy.of(ColorScheme scheme) {
    final cached = _cached;
    if (cached != null && cached.scheme == scheme) {
      return cached;
    }
    final instance = DefaultColorStrategy._(scheme);
    _cached = instance;
    return instance;
  }

  const DefaultColorStrategy._(this.scheme);

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