// lib/core/remotetype/ui/rt_virtual_keyboard.dart
//
// 自绘 5 行 QWERTY 软键盘 + 折叠 Fn 区，给「编排快捷键」面板用。
//
// 视觉对齐 docs/prototypes/remotetype-input.html 的茶禅调：圆角 10、奶白托
// 盘；按下键走 primaryContainer 染色 + AnimatedContainer 0.12s 缓动。
// 颜色全部走 context.colors.scheme —— ColorStrategy 已经在浅 / 深色下对齐过。
//
// 按键回调契约：
//   - modifier (win/ctrl/alt/shift) → 调用方切换 modifierState（toogle）
//   - 主键（其余任意 key）→ 调用方一次性得到 RtChord（modifiers+thisKey），之后
//     自己清空 modifierState
// 这是「先按住修饰、再单点主键完成」的最自然手势。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';

/// 单个虚拟按键按下时的回调。
///   - [keyId] = `RtChord.keys` 入参形态（'win' / 'r' / 'f5' / 'enter' …）
///   - [isModifier] 告诉调用方是否需要切换修饰键状态。
typedef RtKeyCallback = void Function(String keyId, {required bool isModifier});

/// 全键盘展示：5 行主键区 + 折叠的 Esc/F1-F12 行。
///
/// 自身 stateless：modifier 状态在父级持有（RtChordComposer）。
class RtVirtualKeyboard extends StatefulWidget {
  const RtVirtualKeyboard({
    super.key,
    required this.onKey,
    required this.activeModifiers,
    this.showFnRow = false,
    this.onToggleFnRow,
  });

  final RtKeyCallback onKey;

  /// 当前激活的修饰键集合（小写：'win'/'ctrl'/'alt'/'shift'）。用于把 modifier
  /// 键高亮（避免按了 Win 却看不到反馈）。
  final Set<String> activeModifiers;

  /// 默认折叠；点 "Fn ▾" 展开成 Esc + F1..F12 一行。
  final bool showFnRow;
  final VoidCallback? onToggleFnRow;

  @override
  State<RtVirtualKeyboard> createState() => _RtVirtualKeyboardState();
}

class _RtVirtualKeyboardState extends State<RtVirtualKeyboard> {
  // —— 修饰键定义 ——
  static const _mods = {'win', 'ctrl', 'alt', 'shift'};

  // —— 第 1 行：数字 + Backspace ——
  static const List<_KeyDef> _rowDigits = [
    _KeyDef('`', '`'),
    _KeyDef('1', '1'),
    _KeyDef('2', '2'),
    _KeyDef('3', '3'),
    _KeyDef('4', '4'),
    _KeyDef('5', '5'),
    _KeyDef('6', '6'),
    _KeyDef('7', '7'),
    _KeyDef('8', '8'),
    _KeyDef('9', '9'),
    _KeyDef('0', '0'),
    _KeyDef('-', '-'),
    _KeyDef('=', '='),
    _KeyDef('backspace', '⌫', flex: 1.6),
  ];

  // —— 第 2 行：Tab + QWER… + ] \ ——
  static const List<_KeyDef> _rowQwerty = [
    _KeyDef('tab', 'Tab', flex: 1.4),
    _KeyDef('q', 'Q'),
    _KeyDef('w', 'W'),
    _KeyDef('e', 'E'),
    _KeyDef('r', 'R'),
    _KeyDef('t', 'T'),
    _KeyDef('y', 'Y'),
    _KeyDef('u', 'U'),
    _KeyDef('i', 'I'),
    _KeyDef('o', 'O'),
    _KeyDef('p', 'P'),
    _KeyDef('[', '['),
    _KeyDef(']', ']'),
    _KeyDef('\\', '\\', flex: 1.2),
  ];

  // —— 第 3 行：Caps + ASDF… + Enter ——
  static const List<_KeyDef> _rowHome = [
    _KeyDef('caps', 'Caps', flex: 1.6),
    _KeyDef('a', 'A'),
    _KeyDef('s', 'S'),
    _KeyDef('d', 'D'),
    _KeyDef('f', 'F'),
    _KeyDef('g', 'G'),
    _KeyDef('h', 'H'),
    _KeyDef('j', 'J'),
    _KeyDef('k', 'K'),
    _KeyDef('l', 'L'),
    _KeyDef(';', ';'),
    _KeyDef("'", "'"),
    _KeyDef('enter', 'Enter', flex: 1.8),
  ];

  // —— 第 4 行：Shift + ZXCV… + 上箭头 ——
  static const List<_KeyDef> _rowBottom = [
    _KeyDef('shift', 'Shift', flex: 2.2),
    _KeyDef('z', 'Z'),
    _KeyDef('x', 'X'),
    _KeyDef('c', 'C'),
    _KeyDef('v', 'V'),
    _KeyDef('b', 'B'),
    _KeyDef('n', 'N'),
    _KeyDef('m', 'M'),
    _KeyDef(',', ','),
    _KeyDef('.', '.'),
    _KeyDef('/', '/'),
    _KeyDef('up', '↑', flex: 1.2),
  ];

  // —— 第 5 行：Ctrl / Alt / Win / Space / AltGr / ←↓→ / Del ——
  static const List<_KeyDef> _rowSpace = [
    _KeyDef('ctrl', 'Ctrl', flex: 1.4),
    _KeyDef('alt', 'Alt', flex: 1.2),
    _KeyDef('win', 'Win', flex: 1.2),
    _KeyDef('space', ' ', flex: 5.0),
    _KeyDef('alt', 'AltGr', flex: 1.2),
    _KeyDef('left', '←'),
    _KeyDef('down', '↓'),
    _KeyDef('right', '→'),
    _KeyDef('del', 'Del', flex: 1.2),
  ];

  // —— 折叠行：Esc + F1..F12 ——
  static const List<_KeyDef> _rowFn = [
    _KeyDef('escape', 'Esc', flex: 1.2),
    _KeyDef('f1', 'F1'),
    _KeyDef('f2', 'F2'),
    _KeyDef('f3', 'F3'),
    _KeyDef('f4', 'F4', flex: 1.0),
    _KeyDef('f5', 'F5'),
    _KeyDef('f6', 'F6'),
    _KeyDef('f7', 'F7'),
    _KeyDef('f8', 'F8', flex: 1.0),
    _KeyDef('f9', 'F9'),
    _KeyDef('f10', 'F10'),
    _KeyDef('f11', 'F11'),
    _KeyDef('f12', 'F12', flex: 1.0),
  ];

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        // 5 行主键 + 可选 Fn 行。屏宽卡在 container 内（≤420dp 即可读）。
        final width = constraints.maxWidth;
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showFnRow)
                _buildRow(width, _rowFn, gap: 6, rowKey: 'fn'),
              const SizedBox(height: 6),
              _buildRow(width, _rowDigits, gap: 6, rowKey: 'digits'),
              const SizedBox(height: 6),
              _buildRow(width, _rowQwerty, gap: 6, rowKey: 'qwerty'),
              const SizedBox(height: 6),
              _buildRow(width, _rowHome, gap: 6, rowKey: 'home'),
              const SizedBox(height: 6),
              _buildRow(width, _rowBottom, gap: 6, rowKey: 'bottom'),
              const SizedBox(height: 6),
              _buildRow(width, _rowSpace, gap: 6, rowKey: 'space'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(
    double totalWidth,
    List<_KeyDef> keys, {
    required double gap,
    required String rowKey,
  }) {
    // 与设备像素级一致：用宽度比例分配，剩 1px 累计到最后一格。
    final flexTotal = keys.fold<double>(0, (a, b) => a + b.flex);
    var consumed = 0.0;
    final children = <Widget>[];
    for (var i = 0; i < keys.length; i++) {
      final k = keys[i];
      final isLast = i == keys.length - 1;
      final w = isLast
          ? (totalWidth - consumed - gap * (keys.length - 1))
          : ((totalWidth - gap * (keys.length - 1)) * k.flex / flexTotal);
      consumed += w;
      children.add(
        SizedBox(
          width: w,
          height: 38,
          child: _KeyTile(
            keyId: k.id,
            label: k.label,
            active:
                _mods.contains(k.id) && widget.activeModifiers.contains(k.id),
            onTap: () => widget.onKey(k.id, isModifier: _mods.contains(k.id)),
          ),
        ),
      );
      if (!isLast) children.add(SizedBox(width: gap));
    }
    return Row(
      key: ValueKey('kb_row_$rowKey'),
      mainAxisSize: MainAxisSize.max,
      children: children,
    );
  }
}

class _KeyDef {
  const _KeyDef(this.id, this.label, {this.flex = 1.0});
  final String id;
  final String label;
  final double flex;
}

class _KeyTile extends StatefulWidget {
  const _KeyTile({
    required this.keyId,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String keyId;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  State<_KeyTile> createState() => _KeyTileState();
}

class _KeyTileState extends State<_KeyTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final active = widget.active;
    final bg = active ? cs.primaryContainer : cs.surfaceContainerHighest;
    final fg = active ? cs.onPrimaryContainer : c.text;
    return Listener(
      // 按压缩放回弹（Q 弹键帽）：pointer down/up 驱动，onTap 语义不变
      // ——快捷键编辑器与画布键盘共用本件，两边手感一致。
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: Material(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(8),
            splashColor: cs.primary.withValues(alpha: 0.10),
            highlightColor: cs.primary.withValues(alpha: 0.06),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: Curves.easeOut,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: cs.shadow.withValues(alpha: 0.06)),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: widget.label.length <= 2 ? 13 : 11,
                    fontWeight: FontWeight.w700,
                    color: fg,
                    letterSpacing: widget.label.length <= 1 ? 0.4 : 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
