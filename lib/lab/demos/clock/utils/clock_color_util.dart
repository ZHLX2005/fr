import 'dart:ui';
import 'package:flutter/material.dart';

/// 时钟颜色工具类
///
/// 根据倒计时状态动态调整颜色，提供视觉反馈
class ClockColorUtil {
  /// 根据剩余时间和原始时长计算颜色
  ///
  /// - 当 remainingSeconds >= 0 时：返回原始颜色
  /// - 当 remainingSeconds < 0 时：逐渐向黑色/深灰色过渡
  /// - 过渡比例基于超时时间与原始时长的比值
  ///
  /// [baseColor] 原始时钟颜色
  /// [remainingSeconds] 剩余秒数（可为负数）
  /// [durationSeconds] 原始倒计时时长
  /// [maxDarkness] 最大变暗程度（0.0 = 不变，1.0 = 纯黑），默认 0.7
  /// [curve] 缓动曲线，控制颜色变化速率
  static Color getClockColor({
    required Color baseColor,
    required int remainingSeconds,
    required int durationSeconds,
    double maxDarkness = 0.7,
    double Function(double)? curve,
  }) {
    // 未超时或无效时长，返回原色
    if (remainingSeconds >= 0 || durationSeconds <= 0) {
      return baseColor;
    }

    // 计算超时比例（0 ~ 1）
    final overRatio =
        (-remainingSeconds).clamp(0, durationSeconds) / durationSeconds;

    // 应用缓动函数（默认使用 easeInQuad 让变化逐渐加快）
    final adjustedRatio = (curve ?? _easeInQuad)(overRatio);

    // 混合黑色，模拟颜色变暗
    return Color.lerp(baseColor, Colors.black, adjustedRatio * maxDarkness) ??
        baseColor;
  }

  /// 获取带透明度的背景色（用于卡片背景）
  ///
  /// 背景色比主色更透明，在超时时也会变暗
  static Color getBackgroundColor({
    required Color baseColor,
    required int remainingSeconds,
    required int durationSeconds,
    double baseOpacity = 0.08,
    double maxDarkness = 0.6,
  }) {
    final mainColor = getClockColor(
      baseColor: baseColor,
      remainingSeconds: remainingSeconds,
      durationSeconds: durationSeconds,
      maxDarkness: maxDarkness,
    );

    return mainColor.withOpacity(baseOpacity);
  }

  /// 获取边框颜色（比主色更透明）
  static Color getBorderColor({
    required Color baseColor,
    required int remainingSeconds,
    required int durationSeconds,
    double baseOpacity = 0.2,
    double maxDarkness = 0.5,
  }) {
    final mainColor = getClockColor(
      baseColor: baseColor,
      remainingSeconds: remainingSeconds,
      durationSeconds: durationSeconds,
      maxDarkness: maxDarkness,
    );

    return mainColor.withOpacity(baseOpacity);
  }

  /// 获取进度条颜色（用于显示超时进度）
  ///
  /// 返回一个从绿色到红色的渐变色，表示超时严重程度
  static Color getProgressColor({
    required int remainingSeconds,
    required int durationSeconds,
  }) {
    if (remainingSeconds >= 0) {
      // 未超时：蓝色
      return const Color(0xFF007AFF);
    }

    final overRatio =
        (-remainingSeconds).clamp(0, durationSeconds) / durationSeconds;

    // 超时：从橙色渐变到红色
    if (overRatio < 0.5) {
      return Color.lerp(
            const Color(0xFFFF9500),
            const Color(0xFFFF3B30),
            overRatio * 2,
          ) ??
          const Color(0xFFFF9500);
    } else {
      return Color.lerp(
            const Color(0xFFFF3B30),
            const Color(0xFF000000),
            (overRatio - 0.5) * 2,
          ) ??
          const Color(0xFFFF3B30);
    }
  }

  /// 获取超时状态描述
  static String getOvertimeStatus({
    required int remainingSeconds,
    required int durationSeconds,
  }) {
    if (remainingSeconds >= 0) {
      return '';
    }

    final overRatio = (-remainingSeconds) / durationSeconds;

    if (overRatio < 0.1) {
      return '刚超时';
    } else if (overRatio < 0.3) {
      return '轻度超时';
    } else if (overRatio < 0.6) {
      return '中度超时';
    } else if (overRatio < 1.0) {
      return '严重超时';
    } else {
      return '极度超时';
    }
  }

  // ========== 缓动函数 ==========

  /// 线性（无缓动）
  static double _linear(double t) => t;

  /// 二方缓入（逐渐加速）
  static double _easeInQuad(double t) => t * t;

  /// 三次方缓入（更明显的加速）
  static double _easeInCubic(double t) => t * t * t;

  /// 二方缓出（逐渐减速）
  static double _easeOutQuad(double t) => 1 - (1 - t) * (1 - t);

  /// 缓入缓出（先加速后减速）
  static double _easeInOutQuad(double t) =>
      t < 0.5 ? 2 * t * t : 1 - 2 * (1 - t) * (1 - t);

  /// 预设缓动函数
  static const curves = {
    'linear': _linear,
    'easeIn': _easeInQuad,
    'easeOut': _easeOutQuad,
    'easeInOut': _easeInOutQuad,
    'easeInCubic': _easeInCubic,
  };
}
