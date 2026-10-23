// lib/core/remotetype/canvas/template/rt_canvas_template_game_wheel.dart
//
// 内置布局模板 · 轮盘：左八向轮盘（dir8）+ 右 ABXY/肩键。
// 与「方向键布局」同锚点规格，仅 dpad.dir8=true 区分手感——四向键 vs 斜向轮盘。
// hideShortcuts：快捷键按钮区归手柄模块。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleDpad,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasPresetGameWheel;

/// 轮盘布局出厂模板（横屏）。
const RtCanvasNamedLayout kRtCanvasTemplateGameWheel = RtCanvasNamedLayout(
  id: kRtCanvasPresetGameWheel,
  name: '轮盘布局',
  builtIn: true,
  orientation: kRtCanvasOrientLandscape,
  data: RtCanvasLayout(
    hideShortcuts: true,
    modules: {
      kRtCanvasModuleDpad: RtCanvasAnchor(
        visible: true,
        x: 0.21,
        y: 0.54,
        w: 0.22,
        h: 0.52,
        dir8: true,
      ),
      kRtCanvasModuleVpad: RtCanvasAnchor(
        visible: true,
        x: 0.765,
        y: 0.53,
        w: 0.36,
        h: 0.70,
      ),
    },
  ),
);
