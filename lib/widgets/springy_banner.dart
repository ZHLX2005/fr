import 'dart:io';

import 'package:flutter/material.dart';

/// Banner 背景层 — 填满整个 layout 区域，承载用户图片或默认渐变。
///
/// 设计：原本在 widget 内做 spring 下拉拉伸，但 [SliverAppBar] 配 `stretch: true`
/// 已自带 iOS 风格的下拉拉伸 background，**完全由 SliverAppBar 自己驱动**，
/// 这里无需再叠一层 spring。把"q 弹"的弹性完全交给 SliverAppBar 即可。
///
/// 本 widget 仅负责：
///   - 优先展示 [imagePath] 对应的本地图片，[errorBuilder] 失败时回退 [fallback]
///   - 当 [imagePath] 为 `null` 时直接展示 [fallback]
///   - 图片用 [BoxFit.cover] 填满、点击触发 [onTap]
class SpringyBanner extends StatelessWidget {
  const SpringyBanner({
    super.key,
    required this.imagePath,
    required this.fallback,
    required this.onTap,
  });

  /// 用户选定的本地图片路径。`null` 时使用 [fallback]。
  final String? imagePath;

  /// 无图片时显示的占位组件（通常是渐变背景 + "点击设置 Banner" 提示）。
  final Widget fallback;

  /// 点击 banner 时触发的回调（沿用原有的"裁剪/移除"底部菜单）。
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox.expand(
        child: imagePath != null
            ? Image.file(
                File(imagePath!),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              )
            : fallback,
      ),
    );
  }
}
