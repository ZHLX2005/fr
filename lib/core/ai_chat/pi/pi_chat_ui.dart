import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

/// 自绘输入区：一体式胶囊（无 Material 的 OutlineInputBorder 方框感）。
///
/// 设计要点：整个输入区是一个圆角容器，输入框与附件/发送按钮**内嵌**其中，
/// 没有独立边框 —— 这是 ChatGPT/Claude 输入区不做成"表单框"的关键。
class PiComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;

  /// 中止（生成中时发送键变停止键 —— 复评 P4：此前只有 AppBar 小图标，
  /// 移动端单手够不到）。
  final VoidCallback? onStop;
  final bool sending;
  final bool creating;

  const PiComposer({
    super.key,
    required this.controller,
    this.focusNode,
    this.onSend,
    this.onAttach,
    this.onStop,
    this.sending = false,
    this.creating = false,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final colors = PiChatColors.of(t);
    final busy = sending || creating;

    return Container(
      decoration: BoxDecoration(
        color: colors.composerSurface,
        borderRadius: BorderRadius.circular(PiChatTokens.rLg),
        border: Border.all(color: colors.bubbleBorder),
      ),
      padding: const EdgeInsets.fromLTRB(PiChatTokens.s2, PiChatTokens.s2,
          PiChatTokens.s2, PiChatTokens.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ComposerIconButton(
            icon: Icons.add_photo_alternate_outlined,
            tooltip: '添加图片',
            onTap: busy ? null : onAttach,
          ),
          Expanded(
            child: ConstrainedBox(
              // 单行时与按钮等高（垂直居中），多行时自增高
              constraints: const BoxConstraints(minHeight: 36),
              child: Focus(
                // ★ 回车的语义（重构时误删，复评 P1）：桌面/外接键盘
                // Enter 发送、Shift+Enter 换行；软键盘仍是换行键。
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    onSend?.call();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                controller: controller,
                focusNode: focusNode,
                // ★ 进页面即可打字（重构时误删，复评 P1）
                autofocus: true,
                minLines: 1,
                maxLines: 6,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => onSend?.call(),
                cursorColor: cs.primary,
                cursorRadius: const Radius.circular(2),
                style: t.textTheme.bodyMedium?.copyWith(height: 1.45),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: PiChatTokens.s2, vertical: PiChatTokens.s2 + 1),
                  hintText: '发消息…',
                  hintStyle: t.textTheme.bodyMedium?.copyWith(
                    color: colors.metaText.withValues(alpha: 0.7),
                  ),
                ),
                ),
              ),
            ),
          ),
          const SizedBox(width: PiChatTokens.s1),
          _SendButton(
            sending: sending,
            creating: creating,
            onSend: onSend,
            onStop: onStop,
          ),
        ],
      ),
    );
  }
}

/// 输入区内的圆形按钮（比 IconButton 轻，无 ink 涟漪的方框感）。
class _ComposerIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(PiChatTokens.rPill),
        child: Padding(
          padding: const EdgeInsets.all(PiChatTokens.s2),
          child: Icon(
            icon,
            size: 20,
            color: onTap == null
                ? t.colorScheme.onSurface.withValues(alpha: 0.3)
                : t.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}

/// 发送/停止按钮：一次点击语义随状态切换。
class _SendButton extends StatelessWidget {
  final bool sending;
  final bool creating;
  final VoidCallback? onSend;
  final VoidCallback? onStop;

  const _SendButton({
    required this.sending,
    required this.creating,
    this.onSend,
    this.onStop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final busy = sending || creating;
    // 生成中 → 停止键（可点）；创建中 → 转圈（不可点）
    final showStop = sending && onStop != null;
    return AnimatedContainer(
      duration: PiChatTokens.fast,
      curve: PiChatTokens.ease,
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: busy ? cs.onSurface.withValues(alpha: 0.08) : cs.primary,
        shape: BoxShape.circle,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: showStop ? onStop : (busy ? null : onSend),
          customBorder: const CircleBorder(),
          child: Center(
            child: showStop
                ? Icon(Icons.stop_rounded, size: 20, color: cs.onSurface)
                : busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: cs.onSurface.withValues(alpha: 0.5),
                        ),
                      )
                    : Icon(Icons.arrow_upward_rounded,
                        size: 20, color: cs.onPrimary),
          ),
        ),
      ),
    );
  }
}

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

/// 工具活动行：细边框卡片而非实心块（agent 干活时的「过程感」）。
class PiToolStrip extends StatelessWidget {
  final String text;

  const PiToolStrip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final colors = PiChatColors.of(t);
    return Container(
      margin: const EdgeInsets.only(bottom: PiChatTokens.s2),
      padding: const EdgeInsets.symmetric(
          horizontal: PiChatTokens.s3, vertical: PiChatTokens.s2),
      decoration: BoxDecoration(
        color: colors.toolSurface,
        borderRadius: BorderRadius.circular(PiChatTokens.rSm),
        border: Border.all(color: colors.bubbleBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.terminal_rounded,
              size: 13, color: colors.metaText.withValues(alpha: 0.9)),
          const SizedBox(width: PiChatTokens.s2),
          Expanded(
            child: Text(
              text,
              style: t.textTheme.labelSmall?.copyWith(
                color: colors.metaText,
                height: 1.5,
                fontFamily: 'monospace',
                fontSize: 11.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 待发图片缩略图（右上角删除）。
///
/// base64 解码只在 build 时按 content 缓存一次 —— 此前每帧 new MemoryImage
/// 导致 ImageCache 永不命中（每 50ms 全量解码 1600px JPEG，复评 P2-1）。
/// 缩略图 bytes 缓存。
///
/// 为什么必须有：`base64Decode` 每次返回**新** Uint8List，而 `Uint8List ==`
/// 是身份比较 → `MemoryImage` 每次 build 都是新 provider → ImageCache 永不
/// 命中 → 流式期间每 50ms 重解码一次 1600px JPEG（第 12 次复评探针实锤：
/// 4 次 build 后 imageCache 1→4）。按 base64 字符串缓存 bytes 即可命中。
final Map<String, Uint8List> _thumbBytesCache = {};

Uint8List _bytesOf(String base64) =>
    _thumbBytesCache.putIfAbsent(base64, () => base64Decode(base64));

class PiPendingThumb extends StatelessWidget {
  final String base64;
  final VoidCallback onRemove;

  const PiPendingThumb({super.key, required this.base64, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: PiChatTokens.s2),
      child: Stack(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(PiChatTokens.rSm),
              border: Border.all(color: PiChatColors.of(t).bubbleBorder),
              image: DecorationImage(
                image: MemoryImage(_bytesOf(base64)),
                fit: BoxFit.cover,
              ),
            ),
          ),
          Positioned(
            right: 0,
            top: 0,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: t.colorScheme.error,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 12, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
