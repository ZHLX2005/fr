// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 横屏画布内置布局预设：默认 / 游戏 / 键盘 / 触控屏 四套（代码内置，
// 可被用户在画布里自由编辑；编辑后存为「用户改过的版本」，下次启动沿用）。
// 用户从「布局」sheet 复制当前为新自定义，做个人编排；自定义无数量上限。
//
// 与「键盘布局」/「触控屏布局」等命名保持口语（用户记忆点 = 用途，
// 不是几何）。预设只定义模块锚点（含宽高 + 显隐）；按钮位默认留空——
// 首跑按候选槽自动找位。例外：游戏布局预排手柄按钮簇（4 颗主键菱形 +
// 四角次键 + 中心 Start 位），为后期接入虚拟手柄预留 ABXY 区形态。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW,
        kRtCanvasPresetDefault,
        kRtCanvasPresetGame,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad;

/// 内置预设列表（按 UI 展示顺序）。用户可改；改后存盘，下次启动沿用用户版。
const List<RtCanvasNamedLayout> kRtCanvasBuiltinPresets = [
      // 1. 默认：左手触摸 + 右上输入 + 右侧按钮区（原手柄形态）。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetDefault,
        name: '默认布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.27,
              y: 0.55,
              w: kRtCanvasPadDefW,
              h: kRtCanvasPadDefH,
            ),
            'input': RtCanvasAnchor(
              visible: true,
              x: 0.73,
              y: 0.16,
              w: kRtCanvasInputDefW,
              h: kRtCanvasInputDefH,
            ),
          },
        ),
      ),
      // 2. 游戏：完全手柄形态——左侧触摸板 = 摇杆区，右侧按钮簇 = 手柄
      //    按键区（菱形主键 + 四角次键 + 中心），输入框隐藏。后期接入
      //    虚拟手柄时按钮簇即 ABXY 区，直接就位。前 9 条默认快捷键预排
      //    就座；更多 / 自定义快捷键仍走候选槽自动找位。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetGame,
        name: '游戏布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.26,
              y: 0.50,
              w: 0.46,
              h: 0.90,
            ),
            'input': RtCanvasAnchor(
              visible: false,
              x: 0.73,
              y: 0.16,
              w: kRtCanvasInputDefW,
              h: kRtCanvasInputDefH,
            ),
          },
          buttons: {
            // 菱形主键（上/右/下/左，倍率 0.9 大键）
            'default_0': RtCanvasButtonPos(x: 0.79, y: 0.36, s: 0.9),
            'default_1': RtCanvasButtonPos(x: 0.92, y: 0.54, s: 0.9),
            'default_2': RtCanvasButtonPos(x: 0.79, y: 0.72, s: 0.9),
            'default_3': RtCanvasButtonPos(x: 0.66, y: 0.54, s: 0.9),
            // 四角次键（倍率 0.8）
            'default_4': RtCanvasButtonPos(x: 0.66, y: 0.36, s: 0.8),
            'default_5': RtCanvasButtonPos(x: 0.92, y: 0.36, s: 0.8),
            'default_6': RtCanvasButtonPos(x: 0.66, y: 0.72, s: 0.8),
            'default_7': RtCanvasButtonPos(x: 0.92, y: 0.72, s: 0.8),
            // 中心（Start 位）
            'default_8': RtCanvasButtonPos(x: 0.79, y: 0.54, s: 0.8),
          },
        ),
      ),
      // 3. 键盘：底部满宽输入条为主、触摸板退居顶部小区域。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetKeyboard,
        name: '键盘布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.27,
              y: 0.20,
              w: 0.50,
              h: 0.30,
            ),
            'input': RtCanvasAnchor(
              visible: true,
              x: 0.50,
              y: 0.72,
              w: 0.96,
              h: 0.22,
            ),
          },
        ),
      ),
      // 4. 触控屏：触摸板最大化、输入框隐藏（接外部键盘时用）。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetTouchpad,
        name: '触控屏布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.50,
              y: 0.50,
              w: 0.96,
              h: 0.92,
            ),
            'input': RtCanvasAnchor(
              visible: false,
              x: 0.73,
              y: 0.16,
              w: kRtCanvasInputDefW,
              h: kRtCanvasInputDefH,
            ),
          },
        ),
      ),
    ];

/// 按 id 查内置预设出厂条目（「恢复默认布局」用）；自定义 id 查不到返回 null。
RtCanvasNamedLayout? rtBuiltinPresetOf(String id) {
  for (final p in kRtCanvasBuiltinPresets) {
    if (p.id == id) return p;
  }
  return null;
}

/// 保证布局集里 4 套内置总在场（缺的补出厂版），且排在前、自定义跟后。
///
/// 背景：旧版 `rt_canvas_layout_v1` 迁移路径只会产出一条「导入布局」，列表里
/// 没有 4 套内置——不补的话那批用户永远见不到内置预设。已齐全且顺序一致时
/// 原样返回（不产生新实例，页面层据此跳过无谓落盘）。纯函数，规则改动须同步
/// 单测（rt_canvas_layout_test.dart）。
RtCanvasLayouts rtEnsureBuiltinPresets(RtCanvasLayouts layouts) {
  final byId = {for (final p in layouts.list) p.id: p};
  final merged = [
    for (final b in kRtCanvasBuiltinPresets) byId[b.id] ?? b,
    ...layouts.list.where((p) => !p.builtIn),
  ];
  var sameShape = merged.length == layouts.list.length;
  if (sameShape) {
    for (var i = 0; i < merged.length; i++) {
      if (merged[i].id != layouts.list[i].id) {
        sameShape = false;
        break;
      }
    }
  }
  if (sameShape && layouts.list.any((p) => p.id == layouts.activeId)) {
    return layouts;
  }
  var next = RtCanvasLayouts(list: merged, activeId: layouts.activeId);
  if (!merged.any((p) => p.id == next.activeId)) {
    next = next.withActive(kRtCanvasPresetDefault);
  }
  return next;
}
