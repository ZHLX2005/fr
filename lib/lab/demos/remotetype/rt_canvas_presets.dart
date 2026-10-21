// lib/lab/demos/remotetype/rt_canvas_presets.dart
//
// 横竖屏画布内置布局预设：横屏 默认 / 游戏 / 键盘 / 触控屏 四套 +
// 竖屏 触控屏·竖 一套（代码内置，可被用户在画布里自由编辑；编辑后存为
// 「用户改过的版本」，下次启动沿用）。用户从「布局」面板复制当前为新
// 自定义（自选横屏 / 竖屏），做个人编排；自定义无数量上限。
//
// 与「键盘布局」/「触控屏布局」等命名保持口语（用户记忆点 = 用途，
// 不是几何）。预设只定义模块锚点（含宽高 + 显隐）与 hideShortcuts 语义；
// 缺省部分由画布兜底（模块缺失 = 隐藏，编辑态 chip 可随时加回）。
// 游戏 = 纯手柄：左轮盘（vpad 十字键）+ 右手柄键区（ABXY + 肩键/扳机）；
// 键盘 = 顶部小触摸板 + 大虚拟键盘（无输入条，按键即发 hotkey）；
// 触控屏 = 只有一块触摸板；默认 = 触摸板 + 输入框 + 按钮栅格。

import 'rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasLayouts,
        RtCanvasNamedLayout,
        kRtCanvasInputDefH,
        kRtCanvasInputDefW,
        kRtCanvasModuleDpad,
        kRtCanvasModuleKb,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasOrientPortrait,
        kRtCanvasPadDefH,
        kRtCanvasPadDefW,
        kRtCanvasPresetDefault,
        kRtCanvasPresetGame,
        kRtCanvasPresetKeyboard,
        kRtCanvasPresetTouchpad,
        kRtCanvasPresetTouchpadN;

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
      // 3. 键盘：顶部小触摸板（鼠标仍是刚需）+ 大虚拟键盘（按键即发
      //    hotkey）。无输入条——全文同步的输入条归默认布局与打字页。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetKeyboard,
        name: '键盘布局',
        builtIn: true,
        data: RtCanvasLayout(
          hideShortcuts: true,
          modules: {
            'touchpad': RtCanvasAnchor(
              visible: true,
              x: 0.50,
              y: 0.15,
              w: 0.96,
              h: 0.26,
            ),
            kRtCanvasModuleKb: RtCanvasAnchor(
              visible: true,
              x: 0.50,
              y: 0.63,
              w: 0.96,
              h: 0.70,
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
      // 5. 触控屏·竖：竖屏侧的出厂兜底（横竖屏布局相互隔离，竖屏列表
      //    永远不为空）。满屏触摸板，归一化坐标下横竖通吃。
      RtCanvasNamedLayout(
        id: kRtCanvasPresetTouchpadN,
        name: '触控屏 · 竖',
        builtIn: true,
        orientation: kRtCanvasOrientPortrait,
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

/// 保证布局集里 5 套内置（横 4 + 竖 1）总在场（缺的补出厂版），且横屏
/// 内置在前、竖屏内置随后、自定义跟后；两个朝向的激活 id 都必须落在
/// 对应侧的布局上。
///
/// 背景：旧版 `rt_canvas_layout_v1` 迁移路径只会产出一条「导入布局」，列表里
/// 没有内置——不补的话那批用户永远见不到内置预设。已齐全且顺序一致、两侧
/// 激活都有效时原样返回（不产生新实例，页面层据此跳过无谓落盘）。纯函数，
/// 规则改动须同步单测（rt_canvas_layout_test.dart）。
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
  // 激活有效性：横屏 activeId 必须在表内；竖屏 activeIdPortrait 必须指向
  // 真竖屏布局（空 = activeFor 兜底第一条，算有效）。
  final landscapeOk = merged.any((p) => p.id == layouts.activeId);
  final portraitOk = layouts.activeIdPortrait.isEmpty ||
      merged.any((p) =>
          p.id == layouts.activeIdPortrait &&
          p.orientation == kRtCanvasOrientPortrait);
  if (sameShape && landscapeOk && portraitOk) {
    return layouts;
  }
  var next = RtCanvasLayouts(
    list: merged,
    activeId: layouts.activeId,
    activeIdPortrait: layouts.activeIdPortrait,
  );
  if (!merged.any((p) => p.id == next.activeId)) {
    next = next.withActiveFor(kRtCanvasOrientLandscape, kRtCanvasPresetDefault);
  }
  final portraitBad = next.activeIdPortrait.isNotEmpty &&
      !merged.any(
        (p) =>
            p.id == next.activeIdPortrait &&
            p.orientation == kRtCanvasOrientPortrait,
      );
  if (portraitBad) {
    // 竖屏激活悬空：清空，读侧 activeFor 兜底竖屏第一条。
    next = RtCanvasLayouts(
      list: next.list,
      activeId: next.activeId,
      activeIdPortrait: '',
    );
  }
  return next;
}
