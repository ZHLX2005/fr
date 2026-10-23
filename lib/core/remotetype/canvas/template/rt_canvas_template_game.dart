// lib/core/remotetype/canvas/template/rt_canvas_template_game.dart
//
// 内置布局模板 · 方向键：左四向键十字（dir8=false）+ 右 ABXY/肩键。
// 锚点与尺寸与 docs/prototypes/rt-canvas-layouts-manage.html 同源；
// 信号走 vpad 通道（vpad_dpad + vpad_button/trigger）；hideShortcuts：
// 快捷键按钮区归手柄模块，画布按钮不参与。
// 八向轮盘变体见 rt_canvas_template_game_wheel.dart（独立内置 id）。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleDpad,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasPresetGame;

/// 方向键布局出厂模板（横屏）。id 仍为 [kRtCanvasPresetGame]（持久化键不可改）。
const RtCanvasNamedLayout kRtCanvasTemplateGame = RtCanvasNamedLayout(
  id: kRtCanvasPresetGame,
  name: '方向键布局',
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
