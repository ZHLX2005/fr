import 'package:flutter/material.dart';

import '../../../design_tokens/radius.dart';

/// 无色块的边框容器：分块靠**边框**，不靠底色。
///
/// 用户的原话是「别出现色块，完全的边框表示块」「这种无边框设计都不太好看
/// 还是通过浅线条表示吧 需要无色块」——两条合起来就是：**要框，但框要浅**。
/// 所以这里用 outlineVariant（浅）做常规块、outline（中）做强调，内部一律透明。
///
/// 为什么不直接用 Material 的 [Card]：Card 默认带 surface 填充色，
/// 在浅色主题下多个块糊成一片（第一张截图的黄色块），层次全靠底色而丢了。
/// 而「层次靠线不靠面」正是本项目的视觉口径。
///
/// 单独成文件而不是塞进 mnws_home_page.dart：mn-ws 的三个页面（首页 /
/// 设置页 / 请求台）都要用它，放在其中一个页面里会让另外两个反向依赖首页。
class MnWsBlock extends StatelessWidget {
  const MnWsBlock({super.key, required this.child, this.margin, this.emphasized = false});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  /// 强调块：用 outline（中）而不是 outlineVariant（浅）。
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        border: Border.all(
          color: emphasized ? cs.outline : cs.outlineVariant,
          width: emphasized ? 1.6 : 1,
        ),
        borderRadius: AppBorderRadius.allMd,
      ),
      child: child,
    );
  }
}

/// 描边小标签：**不填充**，只用边框与文字颜色区分状态。
///
/// 为什么不用底色：底色块在浅色主题下糊成一片，状态信息
/// （"路由在别的 PC 上"）本该是提示，不该抢应用的注意力。
class MnWsTag extends StatelessWidget {
  const MnWsTag({super.key, required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: AppBorderRadius.allXs,
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color),
      ),
    );
  }
}
