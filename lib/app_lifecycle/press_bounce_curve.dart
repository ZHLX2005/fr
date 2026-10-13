// iOS 风格按压曲线：前 70% 推进到 1.08（8% 过冲），后 30% 弹回 1.0。
// 用于底栏 / 「更多」弹窗格子按压时序——按下微弹放大、松手弹回原大小。
//
// 注意：本曲线不是 Curve 0..1 → 0..1 的物理曲线，而是「按下进度」→
// 「scale 偏移」映射（1.0 = 原大小，1.08 = 峰值）。调用方通过
// AnimationController 反向播放时，传入 1-t 才能正确收回。
import 'package:flutter/animation.dart';

class PressBounceCurve extends Curve {
  const PressBounceCurve();

  @override
  double transformInternal(double t) {
    // 1.0 为原大小基线；前 70% 弹到 1.08（8% 过冲），后 30% 收回 1.0
    if (t < 0.7) {
      return 1.0 + (t / 0.7) * 0.08;
    }
    final k = (t - 0.7) / 0.3;
    return 1.08 - k * 0.08; // 1.08 → 1.00
  }
}
