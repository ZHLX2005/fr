// lib/lab/demos/remotetype/rt_input_view.dart
//
// 输入页 UI（纯展示）：回车注入小开关 + 快捷键托盘 + 可伸展 composer
// 浮卡（同步轻闪 / 字数）+ 清空。
// 语音不再由 demo 内置（原 mic 大按钮 + speech_to_text 已移除）：用户用手机
// 输入法自带的语音听写，识别文本直接落进输入框，走同一条全文同步管线。
// 同步触发、连接状态都在 rt_page / rt_text_sync，这里只收 props 和回调。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';
import '../../../widgets/quick_nav_bottom_bar.dart';
import 'rt_constants.dart';
import 'rt_prefs.dart';
import 'rt_shortcut_bar.dart';

/// 输入页。
class RtInputView extends StatelessWidget {
  const RtInputView({
    super.key,
    required this.controller,
    required this.enterMode,
    required this.onEnterModeChanged,
    required this.syncFlash,
    required this.onClear,
    required this.onReplay,
    required this.onComposerTapOutside,
    required this.onTextChanged,
    required this.shortcuts,
    required this.barDisplay,
    required this.connected,
    required this.firingId,
    required this.onFire,
    required this.onEdit,
    required this.onHistory,
    required this.onBarDisplay,
  });

  final TextEditingController controller;

  /// 回车注入方式：'enter' = 发送 / 'shift_enter' = 换行。
  final String enterMode;
  final ValueChanged<String> onEnterModeChanged;

  /// 「已同步」轻闪（对齐原型 composer sync flash）。
  final bool syncFlash;

  final VoidCallback onClear;

  /// 重放当前输入框全文：PC 端焦点丢失时注入没落进目标框，用这个原样重打。
  final VoidCallback onReplay;

  /// 点到输入框外：composing 还挂着时补发一笔（收尾兜底）。
  final VoidCallback onComposerTapOutside;

  /// 每次文本变化（页面 setState 刷新字数——对齐原行为）。
  final VoidCallback onTextChanged;

  // 快捷键托盘直通参数
  final List<RtShortcutItem> shortcuts;
  final RtBarDisplay barDisplay;
  final bool connected;
  final String? firingId;
  final Future<void> Function(RtShortcutItem item) onFire;
  final VoidCallback onEdit;
  final VoidCallback onHistory;
  final VoidCallback onBarDisplay;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final charCount = controller.text.characters.length;

    // 主壳浮层底栏：勿 SafeArea(bottom)，避免底部 Scaffold 色条。
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          12 + QuickNavBottomBar.bodyBottomReserve(context),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 模式开关只是小控制，靠左占一行，不再做通栏大 tab。
            Align(
              alignment: Alignment.centerLeft,
              child: _EnterModeToggle(
                enterMode: enterMode,
                onChanged: onEnterModeChanged,
              ),
            ),
            const SizedBox(height: 10),
            RtShortcutBar(
              shortcuts: shortcuts,
              display: barDisplay,
              connected: connected,
              firingId: firingId,
              onFire: onFire,
              onEdit: onEdit,
              onHistory: onHistory,
              onDisplay: onBarDisplay,
            ),
            const SizedBox(height: 12),
            // 语音按钮移除后，纵向空间让给输入区：composer 占满剩余高度。
            Expanded(
              child: AnimatedScale(
                scale: syncFlash ? 1.01 : 1.0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: Material(
                  color: c.surface,
                  elevation: syncFlash ? 3 : 1,
                  shadowColor: cs.shadow.withValues(alpha: 0.1),
                  surfaceTintColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => onTextChanged(),
                          onTapOutside: (_) {
                            if (controller.value.composing !=
                                TextRange.empty) {
                              onComposerTapOutside();
                            }
                          },
                          maxLines: null,
                          expands: true,
                          maxLength: kRtMaxTextLength,
                          textAlignVertical: TextAlignVertical.top,
                          style: TextStyle(
                            fontSize: 17,
                            height: 1.45,
                            color: c.text,
                          ),
                          cursorColor: cs.primary,
                          // 对齐原型 .composer textarea：无描边、透明底，焦点也不出框。
                          decoration: InputDecoration(
                            hintText: '打字或语音听写，内容会同步到电脑…',
                            hintStyle: TextStyle(
                              color: c.textMuted.withValues(alpha: 0.7),
                            ),
                            filled: false,
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            disabledBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.fromLTRB(
                              16,
                              16,
                              16,
                              6,
                            ),
                            counterText: '',
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: Row(
                          children: [
                            AnimatedOpacity(
                              opacity: syncFlash ? 1 : 0,
                              duration: const Duration(milliseconds: 220),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '已同步',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.onPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$charCount/$kRtMaxTextLength',
                              style: TextStyle(
                                fontSize: 11,
                                color: c.textMuted,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _FlatMiniBtn(label: '清空', onTap: onClear),
                const SizedBox(width: 8),
                _FlatMiniBtn(label: '重放', onTap: onReplay),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 清空 / 重放这类行内小动作按钮：浮卡样式，与原型 .btn 一致。
class _FlatMiniBtn extends StatelessWidget {
  const _FlatMiniBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return Material(
      color: c.surface,
      elevation: 1,
      shadowColor: cs.shadow.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 回车注入方式小开关（发送 / 换行）：本质只是模式控制，紧凑 pill，
/// 点选切换。不再做成通栏大 tab（那是给高频误触场景的冗余面积）。
class _EnterModeToggle extends StatelessWidget {
  const _EnterModeToggle({required this.enterMode, required this.onChanged});

  final String enterMode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    final isEnter = enterMode == 'enter';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _seg(
            context,
            label: '发送',
            selected: isEnter,
            onTap: () {
              if (enterMode == 'enter') return;
              onChanged('enter');
            },
          ),
          _seg(
            context,
            label: '换行',
            selected: !isEnter,
            onTap: () {
              if (enterMode == 'shift_enter') return;
              onChanged('shift_enter');
            },
          ),
        ],
      ),
    );
  }

  Widget _seg(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    final cs = c.scheme;
    return Material(
      color: selected ? cs.primary : Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.keyboard_return,
                size: 12,
                color: selected ? cs.onPrimary : c.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? cs.onPrimary : c.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
