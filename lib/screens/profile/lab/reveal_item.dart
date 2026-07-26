// 逐项错峰入场动画 —— Lab demo 网格与游戏中心共用。
//
// 第 index 项在 controller 进度 [index*delayStep, +itemDuration] 区间内
// 从「下移 translateY + 全透明」缓动到原位；delay 封顶 maxDelay，保证长列表
// 尾部不会等太久。动画完成后直接返回 child，不再包 Opacity/Transform。
//
// 节奏默认取 Lab 的常量；游戏中心传入自己的节奏（见 const_game_center.dart）。

import 'package:flutter/material.dart';

import 'lab_panel/const_lab_panel.dart';

class RevealItem extends StatelessWidget {
  const RevealItem({
    super.key,
    required this.index,
    required this.controller,
    required this.child,
    this.delayStep = kLabRevealDelayStep,
    this.maxDelay = kLabRevealMaxDelay,
    this.itemDuration = kLabRevealItemDuration,
    this.translateY = kLabRevealTranslateY,
  });

  final int index;
  final AnimationController controller;
  final Widget child;

  /// 第 n 项的起始延迟 = n * delayStep（controller 进度 0~1 计）
  final double delayStep;
  final double maxDelay;
  final double itemDuration;
  final double translateY;

  double _progress(double t) {
    final start = (index * delayStep).clamp(0.0, maxDelay);
    final end = start + itemDuration;
    if (t < start) return 0.0;
    if (t >= end) return 1.0;
    return Curves.easeOutCubic.transform((t - start) / (end - start));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      child: child,
      builder: (context, builderChild) {
        final p = _progress(controller.value);
        if (p >= 1.0) return builderChild!;
        return Opacity(
          opacity: p,
          child: Transform.translate(
            offset: Offset(0, translateY * (1 - p)),
            child: builderChild,
          ),
        );
      },
    );
  }
}
