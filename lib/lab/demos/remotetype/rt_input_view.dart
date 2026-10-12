// lib/lab/demos/remotetype/rt_input_view.dart
//
// 输入页 UI（纯展示）：回车注入分段条 + 快捷键托盘 + 固定高度 composer
// 浮卡（同步轻闪 / 字数）+ 清空 + 麦克风大按钮。
// 同步触发、ASR、连接状态都在 rt_page / rt_text_sync / rt_asr，
// 这里只收 props 和回调。

import 'package:flutter/material.dart';

import '../../../widgets/context_colors.dart';
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
    required this.listening,
    required this.onToggleMic,
    required this.onClear,
    required this.onComposerTapOutside,
    required this.onTextChanged,
    required this.shortcuts,
    required this.connected,
    required this.firingId,
    required this.onFire,
    required this.onEdit,
    required this.onHistory,
  });

  final TextEditingController controller;

  /// 回车注入方式：'enter' = 发送 / 'shift_enter' = 换行。
  final String enterMode;
  final ValueChanged<String> onEnterModeChanged;

  /// 「已同步」轻闪（对齐原型 composer sync flash）。
  final bool syncFlash;

  /// ASR 录音中（mic 按钮换色）。
  final bool listening;
  final VoidCallback onToggleMic;
  final VoidCallback onClear;

  /// 点到输入框外：composing 还挂着时补发一笔（收尾兜底）。
  final VoidCallback onComposerTapOutside;

  /// 每次文本变化（页面 setState 刷新字数——对齐原行为）。
  final VoidCallback onTextChanged;

  // 快捷键托盘直通参数
  final List<RtShortcutItem> shortcuts;
  final bool connected;
  final String? firingId;
  final Future<void> Function(RtShortcutItem item) onFire;
  final VoidCallback onEdit;
  final VoidCallback onHistory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final charCount = controller.text.characters.length;
    // 对齐原型：composer 固定矮卡，键盘直接盖住底部。
    const double fieldHeight = 148;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EnterSeg(enterMode: enterMode, onChanged: onEnterModeChanged),
            const SizedBox(height: 16),
            RtShortcutBar(
              shortcuts: shortcuts,
              connected: connected,
              firingId: firingId,
              onFire: onFire,
              onEdit: onEdit,
              onHistory: onHistory,
            ),
            const SizedBox(height: 16),
            AnimatedScale(
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
                child: SizedBox(
                  height: fieldHeight,
                  child: Column(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          onChanged: (_) => onTextChanged(),
                          onTapOutside: (_) {
                            if (controller.value.composing != TextRange.empty) {
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
                            hintText: '打字或说话，内容会同步到电脑…',
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
            Align(
              alignment: Alignment.centerLeft,
              child: Material(
                color: c.surface,
                elevation: 1,
                shadowColor: cs.shadow.withValues(alpha: 0.06),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onClear,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Text(
                      '清空',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const Spacer(),
            Center(
              child: Material(
                color: listening ? cs.tertiary : cs.primary,
                elevation: 4,
                shadowColor: (listening ? cs.tertiary : cs.primary).withValues(
                  alpha: 0.3,
                ),
                surfaceTintColor: Colors.transparent,
                borderRadius: BorderRadius.circular(20),
                child: InkWell(
                  onTap: onToggleMic,
                  borderRadius: BorderRadius.circular(20),
                  child: SizedBox(
                    width: 64,
                    height: 64,
                    child: Icon(
                      Icons.mic,
                      size: 26,
                      color: listening ? cs.onTertiary : cs.onPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// 全宽滑动分段：发送 / 换行（对齐原型 .seg）。
class _EnterSeg extends StatelessWidget {
  const _EnterSeg({required this.enterMode, required this.onChanged});

  final String enterMode;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = context.colors.scheme;
    final isEnter = enterMode == 'enter';
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(3),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final half = constraints.maxWidth / 2;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 340),
                curve: Curves.easeOutBack,
                left: isEnter ? 0 : half,
                top: 0,
                bottom: 0,
                width: half,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: cs.primary.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _segBtn(
                      context,
                      label: '发送',
                      selected: isEnter,
                      onTap: () {
                        if (enterMode == 'enter') return;
                        onChanged('enter');
                      },
                    ),
                  ),
                  Expanded(
                    child: _segBtn(
                      context,
                      label: '换行',
                      selected: !isEnter,
                      onTap: () {
                        if (enterMode == 'shift_enter') return;
                        onChanged('shift_enter');
                      },
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _segBtn(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final c = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(11),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 11),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: selected ? c.scheme.onPrimary : c.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}
