// lib/core/remotetype/settings/rt_settings_page.dart
//
// 远程输入设置页：RT 的「编排」与偏好落点。
//
// 布局区 = 一张大卡（RtLayoutsCard，见 rt_layouts_card.dart）：
//   · 上栏「竖屏」组、下栏「横屏」组，两组各自独立管理——点行切激活、
//     把手组内拖拽排序、行尾 ⋯ 管理菜单、卡下新建虚线行；
//   · 旧的「布局列表 / 布局管理 / 模块与布局 / 在画布上拖拽编辑」四段
//     顶层入口全部收敛进大卡：管理只从 ⋯ 进，摆位编排归画布编辑态。
//
// 偏好区：回车行为 / 触摸板灵敏度 / 编辑快捷键——与布局无关，维持原样。
//
// 刻意不做的事：「编辑布局」不摊在主路径上——用户要编排时从行 ⋯ 或
// 画布胶囊进，而不是在设置页顶层开一堆编辑入口。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../canvas/rt_touch_surface.dart' show showRtSensitivitySheet;
import '../canvas/template/rt_canvas_presets.dart';
import '../data/rt_constants.dart';
import '../data/rt_layout_ops.dart'
    show
        rtLayoutsCopyToCustom,
        rtLayoutsDeleteCustom,
        rtLayoutsRename,
        rtLayoutsReorder,
        rtLayoutsResetBuiltin;
import '../data/rt_prefs.dart';
import '../ui/rt_shortcut_bar.dart' show showRtShortcutListEditor;
import 'rt_layouts_card.dart';
import 'rt_new_layout_row.dart';

/// 打开远程输入设置页。
///
/// [onEditCanvasLayout] 非空时（从 RT 页进入、有会话）：行 ⋯ 菜单展示
/// 「在画布上编辑」；页面负责关掉自己并带上布局 id（页面侧切布局、
/// 自动转向并进编辑）。从应用设置进本页时没有这项。
Future<void> showRtSettingsPage(
  BuildContext context, {
  ValueChanged<String>? onEditCanvasLayout,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => RtSettingsPage(onEditCanvasLayout: onEditCanvasLayout),
    ),
  );
}

/// 远程输入设置页（自持状态：自己读盘自己落盘；调用方返回后自行重载）。
class RtSettingsPage extends StatefulWidget {
  const RtSettingsPage({super.key, this.onEditCanvasLayout});

  /// 参数 = 要编辑的布局 id（可跨朝向；页面侧负责转向）。
  final ValueChanged<String>? onEditCanvasLayout;

  @override
  State<RtSettingsPage> createState() => _RtSettingsPageState();
}

class _RtSettingsPageState extends State<RtSettingsPage> {
  RtCanvasLayouts _layouts = const RtCanvasLayouts(
    list: kRtCanvasBuiltinPresets,
    activeId: kRtCanvasPresetTouchpad,
  );
  String _enterMode = 'enter';
  double _sensitivity = kRtPadSensitivityDefault;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var layouts = await RtPrefs.loadCanvasLayouts();
    if (layouts.list.isEmpty) {
      // 首跑空表：内存里铺内置（与 rt_page 同一套语义，不写盘）。
      layouts = const RtCanvasLayouts(
        list: kRtCanvasBuiltinPresets,
        activeId: kRtCanvasPresetTouchpad,
      );
      await RtPrefs.saveCanvasBuiltinFactoryRev(kRtCanvasBuiltinFactoryRev);
    } else {
      final factoryRev = await RtPrefs.loadCanvasBuiltinFactoryRev();
      final ensured = rtEnsureBuiltinPresets(
        layouts,
        persistedFactoryRev: factoryRev,
      );
      if (!identical(ensured, layouts)) {
        layouts = ensured;
        await RtPrefs.saveCanvasLayouts(layouts);
      }
      // 与 rt_page 对齐：ensure 用过新工厂后把修订号写上，避免下次再刷一遍。
      if (factoryRev < kRtCanvasBuiltinFactoryRev) {
        await RtPrefs.saveCanvasBuiltinFactoryRev(kRtCanvasBuiltinFactoryRev);
      }
    }
    final enterMode = await RtPrefs.loadEnterMode();
    final sensitivity = await RtPrefs.loadTouchpadSensitivity();
    if (!mounted) return;
    setState(() {
      _layouts = layouts;
      _enterMode = enterMode;
      _sensitivity = sensitivity;
    });
  }

  /// 最近一次落盘的 Future：关页跳转前要等它落地（见 _editOnCanvas）。
  Future<void> _lastSave = Future.value();

  Future<void> _saveLayouts(RtCanvasLayouts next) async {
    setState(() => _layouts = next);
    final saving = RtPrefs.saveCanvasLayouts(next);
    _lastSave = saving;
    await saving;
  }

  /// 行 ⋯「在画布上编辑」：关菜单（调用方已关）→ 关设置页 → 交给 RT 页
  /// 切布局 + 自动转向 + 进编辑。不要求当前朝向可用：竖屏也可编辑横屏布局。
  Future<void> _editOnCanvas(String id) async {
    final cb = widget.onEditCanvasLayout;
    if (cb == null) return;
    // 等最后一次落盘落地再关页：RT 页在本页关闭后会回读磁盘，
    // 若读到旧快照再回写就会抹掉刚才的改动。
    await _lastSave;
    if (!mounted) return;
    Navigator.of(context).pop();
    cb(id);
  }

  // ── 输入偏好 ───────────────────────────────────────────────────────

  Future<void> _toggleEnterMode() async {
    final next = _enterMode == 'enter' ? 'shift_enter' : 'enter';
    setState(() => _enterMode = next);
    await RtPrefs.saveEnterMode(next);
  }

  Future<void> _openSensitivity() async {
    await showRtSensitivitySheet(
      context,
      value: _sensitivity,
      onChanged: (v) {
        setState(() => _sensitivity = v);
        _unawaitedSave(v);
      },
    );
  }

  void _unawaitedSave(double v) {
    RtPrefs.saveTouchpadSensitivity(v);
  }

  Future<void> _editShortcuts() async {
    final current = await RtPrefs.loadShortcuts();
    if (!mounted) return;
    final next = await showRtShortcutListEditor(
      context: context,
      current: current,
    );
    if (next == null) return;
    await RtPrefs.saveShortcuts(next);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final cs = c.scheme;
    final isEnter = _enterMode == 'enter';
    return Scaffold(
      appBar: AppBar(title: const Text('远程输入设置'), centerTitle: false),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const _SectionHeader('布局'),
          RtLayoutsCard(
            layouts: _layouts,
            canEditOnCanvas: widget.onEditCanvasLayout != null,
            onSwitch: (orient, id) =>
                _saveLayouts(_layouts.withActiveFor(orient, id)),
            onReorder: (orient, oldIndex, newIndex) => _saveLayouts(
              rtLayoutsReorder(_layouts, orient, oldIndex, newIndex),
            ),
            onEditOnCanvas: widget.onEditCanvasLayout == null
                ? null
                : _editOnCanvas,
            onResetBuiltin: (id) =>
                _saveLayouts(rtLayoutsResetBuiltin(_layouts, id)),
            onRename: (id, name) => _saveLayouts(rtLayoutsRename(_layouts, id, name)),
            onDelete: (id) => _saveLayouts(rtLayoutsDeleteCustom(_layouts, id)),
          ),
          RtNewLayoutRow(
            onCreate: (orient) =>
                _saveLayouts(rtLayoutsCopyToCustom(_layouts, orient)),
          ),
          const _SectionHeader('输入'),
          ListTile(
            leading: const Icon(Icons.keyboard_return),
            title: const Text('回车行为'),
            subtitle: Text(isEnter ? '发送（普通 Enter）' : '换行（Shift+Enter）'),
            trailing: Icon(
              Icons.swap_horiz,
              color: cs.primary,
            ),
            onTap: _toggleEnterMode,
          ),
          const _SectionHeader('其他'),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('触摸板灵敏度'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openSensitivity,
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('编辑快捷键'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _editShortcuts,
          ),
        ],
      ),
    );
  }
}

/// 分区标题（与模块页同款观感）。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.textMuted,
        ),
      ),
    );
  }
}
