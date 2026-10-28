import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../ui/global/chat/main.dart';

/// 自绘输入区：一体式胶囊（无 Material 的 OutlineInputBorder 方框感）。
///
/// 设计要点：整个输入区是一个圆角容器，输入框与附件/发送按钮**内嵌**其中，
/// 没有独立边框 —— 这是 ChatGPT/Claude 输入区不做成"表单框"的关键。
class PiComposer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final VoidCallback? onSend;
  final VoidCallback? onAttach;

  /// 中止（生成中时发送键变停止键 —— 评 P4：此前只有 AppBar 小图标，
  /// 移动端单手够不到）。
  final VoidCallback? onStop;

  /// 拍照入口（附件按钮长按）。
  final VoidCallback? onAttachCamera;
  final bool sending;
  final bool creating;

  const PiComposer({
    super.key,
    required this.controller,
    this.focusNode,
    this.onSend,
    this.onAttach,
    this.onAttachCamera,
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
            // 点击=相册；长按=相机（第 14 次复评：此前只有相册入口）
            tooltip: '添加图片（长按拍照）',
            onTap: busy ? null : onAttach,
            onLongPress: busy ? null : onAttachCamera,
          ),
          Expanded(
            child: ConstrainedBox(
              // 单行时与按钮等高（垂直居中），多行时自增高。
              // maxHeight=140：超长输入由 TextField 自身的 EditableText
              // scrollController 在 140px 容器内做内滚（不再依赖外层
              // SingleChildScrollView —— 第 17 次复评 P-2 自查：嵌套滚动
              // 容易触发双滚动 bug；TextField 自带的滚动已足够）。
              constraints: const BoxConstraints(
                  minHeight: 36, maxHeight: 140),
              child: Focus(
                // ★ 回车的语义（重构时误删，复评 P1）：桌面/外接键盘
                // Enter 发送、Shift+Enter 换行；软键盘仍是换行键。
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    // ★ IME composing 守卫（第 14 次复评前置 5）：中文输入法
                    // 组合期间按 Enter 是「确认候选词」，不是发送 —— 否则
                    // 会把半成品拼音直发出去（中文 App 的真实受众）。
                    if (controller.value.composing != TextRange.empty) {
                      return KeyEventResult.ignored;
                    }
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
                // maxLines=null + ConstrainedBox(maxHeight:140)：TextField
                // 自带 EditableText 内部 scrollController 在父层 maxHeight
                // 内做内滚——无需外层 SingleChildScrollView。
                maxLines: null,
                minLines: 1,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                onSubmitted: (_) => onSend?.call(),
                onChanged: (_) {
                  // 第 17 次复评 P-2：触顶震动条件改用「光标到首段 + 文本
                  // 超过视高能装下的字符数」—— 用换行数近似（折行越多越
                  // 可能顶到上限）+ 选中起始 < 30 表示用户主动回到顶部。
                  if (controller.text.length > 200 &&
                      controller.selection.baseOffset < 30) {
                    HapticFeedback.selectionClick();
                  }
                },
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
  final VoidCallback? onLongPress;

  const _ComposerIconButton({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
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


/// 工具活动行：细边框卡片而非实心块（agent 干活时的「过程感」）。
/// 长任务下固定 maxHeight + 内部滚动（信息全保留，不再顶爆气泡）。
class PiToolStrip extends StatelessWidget {
  final String text;

  const PiToolStrip({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final colors = PiChatColors.of(t);
    final lineCount = text.split('\n').length;
    final isLong = lineCount > 4;
    final shown = isLong
        ? '${text.split('\n').take(4).join('\n')}\n…等 ${lineCount - 4} 步'
        : text;

    return Container(
      margin: const EdgeInsets.only(bottom: PiChatTokens.s2),
      decoration: BoxDecoration(
        color: colors.toolSurface,
        borderRadius: BorderRadius.circular(PiChatTokens.rSm),
        border: Border.all(color: colors.bubbleBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 96),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: PiChatTokens.s3, vertical: PiChatTokens.s2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.terminal_rounded,
                  size: 13, color: colors.metaText.withValues(alpha: 0.9)),
              const SizedBox(width: PiChatTokens.s2),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.vertical,
                  child: Text(
                    shown,
                    style: t.textTheme.labelSmall?.copyWith(
                      color: colors.metaText,
                      height: 1.45,
                      fontFamily: 'monospace',
                      fontSize: 11.5,
                    ),
                  ),
                ),
              ),
              if (isLong)
                Padding(
                  padding: const EdgeInsets.only(left: 4, right: 2),
                  child: Icon(Icons.more_horiz,
                      size: 12,
                      color: colors.metaText.withValues(alpha: 0.6)),
                ),
            ],
          ),
        ),
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
