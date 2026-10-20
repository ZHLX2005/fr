// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 横屏画布内置布局预设：默认 / 游戏 / 键盘 / 触控屏 四套（代码内置，
// 可被用户在画布里自由编辑；编辑后存为「用户改过的版本」，下次启动沿用）。
// 用户从「布局」sheet 复制当前为新自定义，做个人编排；自定义无数量上限。
//
// 与「键盘布局」/「触控屏布局」等命名保持口语（用户记忆点 = 用途，
// 不是几何）。预设只定义模块锚点（含宽高 + 显隐）与预排按钮位；缺省部分
// 由画布兜底（模块缺失 = 隐藏，编辑态 chip 可随时加回）。
// 游戏 = 纯手柄：左轮盘（方向键连发）+ 右圆形按钮簇（ABXY 菱形 + 双肩键）；
// 触控屏 = 只有一块触摸板；默认 = 触摸板 + 输入框 + 按钮栅格；键盘 = 大输入条。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasButtonPos,
        RtCanvasButtonShape,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleDpad,
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
      // 2. 游戏：纯手柄形态——左侧方向轮盘（上下左右移动，按住连发），
      //    右侧圆形按钮簇：4 颗主键菱形（ABXY 位）+ 顶部双肩键（LT/RT 位）
      //    + 次键补位。触摸板 / 输入框不进这套布局（编辑态可随时加回）。
      //    按键全部圆形（shape: circle），标签显示末位主键短名。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetGame,
        name: '游戏布局',
        builtIn: true,
        data: RtCanvasLayout(
          modules: {
            kRtCanvasModuleDpad: RtCanvasAnchor(
              visible: true,
              x: 0.24,
              y: 0.52,
              w: 0.30,
              h: 0.78,
            ),
          },
          buttons: {
            // 菱形主键（上/右/下/左 = ABXY 位）
            'default_0': RtCanvasButtonPos(
                x: 0.80, y: 0.40, s: 1.0, shape: RtCanvasButtonShape.circle),
            'default_1': RtCanvasButtonPos(
                x: 0.93, y: 0.56, s: 1.0, shape: RtCanvasButtonShape.circle),
            'default_2': RtCanvasButtonPos(
                x: 0.80, y: 0.72, s: 1.0, shape: RtCanvasButtonShape.circle),
            'default_3': RtCanvasButtonPos(
                x: 0.66, y: 0.56, s: 1.0, shape: RtCanvasButtonShape.circle),
            // 双肩键（LT / RT 位）
            'default_4': RtCanvasButtonPos(
                x: 0.58, y: 0.28, s: 0.75, shape: RtCanvasButtonShape.circle),
            'default_5': RtCanvasButtonPos(
                x: 0.94, y: 0.28, s: 0.75, shape: RtCanvasButtonShape.circle),
            // 次键补位（簇中心 + 底部一排）
            'default_8': RtCanvasButtonPos(
                x: 0.80, y: 0.56, s: 0.7, shape: RtCanvasButtonShape.circle),
            'default_6': RtCanvasButtonPos(
                x: 0.70, y: 0.88, s: 0.7, shape: RtCanvasButtonShape.circle),
            'default_7': RtCanvasButtonPos(
                x: 0.90, y: 0.88, s: 0.7, shape: RtCanvasButtonShape.circle),
            'default_9': RtCanvasButtonPos(
                x: 0.52, y: 0.88, s: 0.7, shape: RtCanvasButtonShape.circle),
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
