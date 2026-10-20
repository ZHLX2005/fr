// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 横屏画布内置布局预设：默认 / 游戏 / 键盘 / 触控屏 四套（代码内置，
// 可被用户在画布里自由编辑；编辑后存为「用户改过的版本」，下次启动沿用）。
// 用户从「布局」sheet 复制当前为新自定义，做个人编排；自定义无数量上限。
//
// 与「键盘布局」/「触控屏布局」等命名保持口语（用户记忆点 = 用途，
// 不是几何）。预设只定义模块锚点（含宽高 + 显隐）与 hideShortcuts 语义；
// 缺省部分由画布兜底（模块缺失 = 隐藏，编辑态 chip 可随时加回）。
// 游戏 = 纯手柄：左轮盘（vpad 十字键）+ 右手柄键区（ABXY + 肩键/扳机）；
// 触控屏 = 只有一块触摸板；默认 = 触摸板 + 输入框 + 按钮栅格；键盘 = 大输入条。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleDpad,
        kRtCanvasModuleVpad,
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
      // 2. 游戏：纯手柄形态——左侧方向轮盘（vpad 十字键，回中 = none）
      //    + 右侧手柄键区（ABXY 菱形 + LB/LT/RT/RB 肩键行），全部走 PC 端
      //    虚拟手柄协议。快捷键按钮不参与（hideShortcuts：按钮区归手柄
      //    模块）；触摸板 / 输入框不内嵌（编辑态 chip 可随时加回）。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetGame,
        name: '游戏布局',
        builtIn: true,
        data: RtCanvasLayout(
          hideShortcuts: true,
          modules: {
            kRtCanvasModuleDpad: RtCanvasAnchor(
              visible: true,
              x: 0.22,
              y: 0.52,
              w: 0.30,
              h: 0.78,
            ),
            kRtCanvasModuleVpad: RtCanvasAnchor(
              visible: true,
              x: 0.77,
              y: 0.53,
              w: 0.42,
              h: 0.92,
            ),
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
      // 4. 触控屏：只有一块触摸板（最大化，接外部键盘时用）。
      //    不含任何其它模块——纯净版；编辑态 chip 可随时加回输入框 / 轮盘。
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
