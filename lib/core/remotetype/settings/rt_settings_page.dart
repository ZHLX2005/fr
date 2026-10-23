// lib/core/remotetype/settings/rt_settings_page.dart
//
// 远程输入设置页：RT 的「编排」与偏好落点。
//
// 从画布/写字页搬过来的东西：
//   · 布局管理（改名 / 删除 / 新建 / 恢复出厂）——原挂在画布的布局面板；
//   · 模块与布局（模块开关 + 九宫格位置 + 三档尺寸）——原挂在画布左上角
//     胶囊的「模块编排」；画布现在只留「切换布局」。
//   · 发送 / 换行（回车注入方式）——原是写字页工具行上的两颗小按钮
//     （页面级内存态，切走即丢）；现在持久化在这里，写字页是固定形态。
//
// 刻意不做的事：「编辑布局」不提到常用功能列表，只做这里的设置项——
// 用户要编排时进设置，而不是在主路径上摊开一堆编辑入口。

import 'package:flutter/material.dart';

import '../../../core/theme/context/colors.dart';
import '../canvas/rt_canvas_layouts_sheet.dart';
import '../canvas/rt_canvas_module_page.dart';
import '../canvas/rt_touch_surface.dart' show showRtSensitivitySheet;
import '../canvas/template/rt_canvas_presets.dart';
import '../data/rt_constants.dart';
import '../data/rt_prefs.dart';
import '../ui/rt_shortcut_bar.dart' show showRtShortcutListEditor;

/// 打开远程输入设置页。
///
/// [onEditCanvasLayout] 非空时（从 RT 页进入、画布在场）：布局管理「修改」
/// 与「在画布上拖拽编辑」会带上布局 id；页面负责切布局、自动转向并进编辑。
/// 从应用设置进本页时没有这两项。
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

  /// 当前朝向（决定「当前布局」与可用列表）。
  String get _orientation =>
      MediaQuery.orientationOf(context) == Orientation.landscape
      ? kRtCanvasOrientLandscape
      : kRtCanvasOrientPortrait;

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

  Future<void> _saveLayouts(RtCanvasLayouts next) async {
    setState(() => _layouts = next);
    await RtPrefs.saveCanvasLayouts(next);
  }

  // ── 布局管理（改名 / 删除 / 新建 / 恢复出厂 / 切换）──────────────────

  Future<void> _openLayoutManager() async {
    await showRtCanvasLayoutsPanel(
      context,
      layouts: _layouts,
      activeId: _layouts.activeFor(_orientation)?.id ?? '',
      orientation: _orientation,
      onLayoutsChanged: _saveLayouts,
      onEdit: widget.onEditCanvasLayout == null
          ? null
          : (id) {
              // 关布局面板 → 关设置页 → 交给 RT 页切布局 + 自动转向 + 进编辑。
              // 不要求当前朝向可用：竖屏也可点「修改」横屏布局，页面会转过去。
              Navigator.of(context).pop();
              Navigator.of(context).pop();
              widget.onEditCanvasLayout!(id);
            },
    );
  }

  Future<void> _openModuleArrange() async {
    final active = _layouts.activeFor(_orientation);
    if (active == null) return;
    await showRtCanvasModulePage(
      context,
      layoutName: active.name,
      connected: true,
      visibleOf: (id) => active.data.modules[id]?.visible ?? false,
      anchorOf: (id) =>
          active.data.modules[id] ?? const RtCanvasAnchor(visible: false, x: 0.5, y: 0.5),
      onToggleModule: (id, on) {
        final anchor = active.data.modules[id] ??
            const RtCanvasAnchor(visible: false, x: 0.5, y: 0.5);
        _saveLayouts(
          _layouts.withUpdatedActiveFor(
            _orientation,
            active.data.withModule(id, anchor.copyWith(visible: on)),
          ),
        );
      },
      onSetAnchor: (id, anchor) {
        _saveLayouts(
          _layouts.withUpdatedActiveFor(
            _orientation,
            active.data.withModule(id, anchor),
          ),
        );
      },
      onOpenLayouts: _openLayoutManager,
    );
  }

  /// 布局列表里的一条：可用的直接点即切；不可用的（另一朝向专属）置灰。
  Widget _layoutTile(RtCanvasNamedLayout p, ColorScheme cs) {
    final c = context.colors;
    final usable = rtCanvasLayoutUsableIn(_orientation, p);
    final active = p.id == _layouts.activeFor(_orientation)?.id;
    return ListTile(
      dense: true,
      enabled: usable,
      leading: Icon(
        p.kind == RtLayoutKind.writer
            ? Icons.keyboard_alt_outlined
            : Icons.dashboard_customize_outlined,
        color: active ? cs.primary : c.textMuted,
      ),
      title: Text(
        p.name,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? cs.primary : c.text,
        ),
      ),
      // 固定死的布局没有编辑入口——标出来，免得用户去找。
      subtitle: p.editable
          ? null
          : Text(
              '固定布局',
              style: TextStyle(fontSize: 11, color: c.textMuted),
            ),
      trailing: active ? Icon(Icons.check, color: cs.primary) : null,
      onTap: () => _saveLayouts(_layouts.withActiveFor(_orientation, p.id)),
    );
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
        unawaitedSave(v);
      },
    );
  }

  void unawaitedSave(double v) {
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
          _SectionHeader('布局'),
          // 第一层就是布局列表：所有布局都列出来，点一下即切（常用操作）。
          // 管理类动作（改名 / 删除 / 新建 / 恢复出厂）收在下一行「布局管理」。
          for (final p in _layouts.list)
            _layoutTile(p, cs),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('布局管理'),
            subtitle: const Text('拖拽排序 · 改名 / 删除 / 新建 / 恢复'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openLayoutManager,
          ),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('模块与布局'),
            subtitle: const Text('模块开关与摆放位置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _openModuleArrange,
          ),
          if (widget.onEditCanvasLayout != null)
            ListTile(
              leading: const Icon(Icons.open_with),
              title: const Text('在画布上拖拽编辑'),
              subtitle: const Text('直接拖动模块与按钮摆位'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                final id = _layouts.activeFor(_orientation)?.id;
                if (id == null) return;
                Navigator.of(context).pop();
                widget.onEditCanvasLayout!(id);
              },
            ),
          _SectionHeader('输入'),
          ListTile(
            leading: const Icon(Icons.keyboard_return),
            title: const Text('回车行为'),
            subtitle: Text(isEnter ? '发送（普通 Enter）' : '换行（Shift+Enter）'),
            trailing: Icon(
              isEnter ? Icons.swap_horiz : Icons.swap_horiz,
              color: cs.primary,
            ),
            onTap: _toggleEnterMode,
          ),
          _SectionHeader('其他'),
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
