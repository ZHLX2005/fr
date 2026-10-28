// pi 聊天设计 token —— 2026-10-28 自 lib/core/ai_chat/pi/pi_chat_ui.dart 拆出
//（任务 #7 组件收敛：聊天域通用样式件集中到 lib/core/ui/chat/）。
import 'package:flutter/material.dart';

/// pi 聊天的设计 token 与自绘组件。
///
/// 为什么独立成文件：此前页面里全是 Material 默认件（`OutlineInputBorder`
/// 输入框、平底色气泡、默认 ListTile），视觉上就是「套壳」——塑料感的来源
/// 不是配色，是**没有自己的度量体系**：圆角/间距/字阶各处硬编码，
/// 与 Material 的默认尺度打架。
///
/// 这里定一套自己的：4pt 栅格、独立圆角阶、克制的阴影、气泡尾角。
@immutable
class PiChatTokens {
  const PiChatTokens._();

  // ── 间距（4pt 栅格）──
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;

  // ── 圆角 ──
  static const double rSm = 8;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rPill = 999;

  /// 气泡圆角：靠说话人一侧收窄（尾角语义，非对称才有「对话感」）
  static const BorderRadius bubbleMine = BorderRadius.only(
    topLeft: Radius.circular(rLg),
    topRight: Radius.circular(rLg),
    bottomLeft: Radius.circular(rLg),
    bottomRight: Radius.circular(s1 + 2),
  );
  static const BorderRadius bubbleTheirs = BorderRadius.only(
    topLeft: Radius.circular(rLg),
    topRight: Radius.circular(rLg),
    bottomLeft: Radius.circular(s1 + 2),
    bottomRight: Radius.circular(rLg),
  );

  // ── 动效 ──
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 220);
  static const Curve ease = Curves.easeOutCubic;

  // ── 气泡最大宽度（绝对上限，避免横屏一行 70 字）──
  static const double bubbleMaxWidth = 520;

  // ── 内容列宽（宽屏居中，Claude/ChatGPT 的做法）──
  static const double contentMaxWidth = 760;
}

/// pi 聊天的语义配色（从 ColorScheme 派生，保证五套主题都成立）。
@immutable
class PiChatColors {
  final Color mineBubble;
  final Color mineText;
  final Color theirsBubble;
  final Color theirsText;
  final Color bubbleBorder;
  final Color metaText;
  final Color toolSurface;
  final Color composerSurface;

  const PiChatColors({
    required this.mineBubble,
    required this.mineText,
    required this.theirsBubble,
    required this.theirsText,
    required this.bubbleBorder,
    required this.metaText,
    required this.toolSurface,
    required this.composerSurface,
  });

  /// 从主题派生：不再用 `surfaceContainerHighest` 当气泡底（在部分主题下
  /// 与背景几乎无对比 → 一片灰，正是塑料感的来源之一）。
  factory PiChatColors.of(ThemeData t) {
    final cs = t.colorScheme;
    final dark = t.brightness == Brightness.dark;
    return PiChatColors(
      // 我方：品牌色微调（不用满饱和的 primaryContainer，太扎眼）
      mineBubble: Color.alphaBlend(
        cs.primary.withValues(alpha: dark ? 0.22 : 0.10),
        cs.surface,
      ),
      mineText: cs.onSurface,
      // 对方：surface 上抬一档 + 细边框（比纯色块有层次）
      theirsBubble: Color.alphaBlend(
        cs.onSurface.withValues(alpha: dark ? 0.06 : 0.035),
        cs.surface,
      ),
      theirsText: cs.onSurface,
      bubbleBorder: cs.onSurface.withValues(alpha: dark ? 0.10 : 0.07),
      metaText: cs.onSurfaceVariant,
      toolSurface: Color.alphaBlend(
        cs.secondary.withValues(alpha: dark ? 0.10 : 0.05),
        cs.surface,
      ),
      composerSurface: Color.alphaBlend(
        cs.onSurface.withValues(alpha: dark ? 0.05 : 0.03),
        cs.surface,
      ),
    );
  }
}

// ── PiDayDivider（聊天域分隔件）──

/// 日期分隔：不做成灰胶囊（那是 Material Chip 的观感），
/// 改用「细线 + 居中文字」，更安静。
class PiDayDivider extends StatelessWidget {
  final String label;

  const PiDayDivider({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final colors = PiChatColors.of(t);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: PiChatTokens.s4),
      child: Row(
        children: [
          Expanded(child: Divider(color: colors.bubbleBorder, height: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: PiChatTokens.s3),
            child: Text(
              label,
              style: t.textTheme.labelSmall?.copyWith(
                color: colors.metaText.withValues(alpha: 0.8),
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(child: Divider(color: colors.bubbleBorder, height: 1)),
        ],
      ),
    );
  }
}
