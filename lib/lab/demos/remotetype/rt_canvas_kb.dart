// lib/lab/demos/remotetype/rt_canvas_kb.dart
//
// 画布虚拟键盘模块（键盘布局主体）：复用打字页的 RtVirtualKeyboard（5 行
// QWERTY + 折叠 Fn 区），接 hotkey 通道「按键即发」。
//   · 主键 → 合成 chord（粘滞修饰键 + 主键）一次性回报，随后清空修饰；
//   · 修饰键（win/ctrl/alt/shift）→ 本模块持有粘滞态，高亮反馈；
//   · caps → PC 端 parse_key_name 白名单外（mn-rt 已知缺口），直接吞掉
//     不发，避免每次点按都收到 PC 侧拒绝。
// 键序即 chord 键序（修饰在前、主键在后），与快捷键条 syncHotkey 同一形状。

import 'package:flutter/material.dart';

import 'rt_virtual_keyboard.dart' show RtVirtualKeyboard;

/// 修饰键粘滞态的标准序（合成 chord 时修饰键排前，键名与 hotkey 白名单一致）。
const List<String> _kModifierOrder = ['win', 'ctrl', 'alt', 'shift'];

/// PC 端 hotkey 白名单外的 keyId：吞掉不发送（caps lock 无法以 Click 语义表达）。
const Set<String> _kUnsupportedKeys = {'caps'};

class RtCanvasKb extends StatefulWidget {
  const RtCanvasKb({
    super.key,
    required this.enabled,
    required this.onChord,
  });

  /// false（未连接）：置灰且不响应。
  final bool enabled;

  /// 一次按键（修饰键 + 主键合成完毕）→ chord 键名列表，调用方发 hotkey。
  final ValueChanged<List<String>> onChord;

  @override
  State<RtCanvasKb> createState() => _RtCanvasKbState();
}

class _RtCanvasKbState extends State<RtCanvasKb> {
  final Set<String> _mods = <String>{};
  bool _showFn = false;

  void _onKey(String keyId, {required bool isModifier}) {
    if (!widget.enabled) return;
    if (isModifier) {
      setState(() => _mods.contains(keyId)
          ? _mods.remove(keyId)
          : _mods.add(keyId));
      return;
    }
    if (_kUnsupportedKeys.contains(keyId)) return;
    // chord = 粘滞修饰（标准序）+ 主键；无修饰就是单键。
    final keys = [
      for (final m in _kModifierOrder)
        if (_mods.contains(m)) m,
      keyId,
    ];
    if (_mods.isNotEmpty) setState(_mods.clear);
    widget.onChord(keys);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: widget.enabled ? 1.0 : 0.45,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Fn 折叠开关（RtVirtualKeyboard 自身不带 toggle UI，归调用方）。
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
              child: Row(
                children: [
                  Text(
                    '功能行 F1 – F12',
                    style: TextStyle(
                      fontSize: 10.5,
                      color: cs.onSurfaceVariant,
                      letterSpacing: 0.6,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() => _showFn = !_showFn),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      child: Text(
                        _showFn ? '收起 Fn 行' : '显示 Fn 行',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            RtVirtualKeyboard(
              onKey: _onKey,
              activeModifiers: _mods,
              showFnRow: _showFn,
            ),
          ],
        ),
      ),
    );
  }
}
