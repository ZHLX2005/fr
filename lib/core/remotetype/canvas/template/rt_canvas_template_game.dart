// lib/core/remotetype/canvas/template/rt_canvas_template_game.dart
//
// 内置布局模板 · 游戏：纯手柄——左拖动轮盘 + 右 ABXY/肩键。
// 锚点与尺寸与 docs/prototypes/rt-canvas-gamepad.html 的 LAYOUTS.game 同源；
// 信号走 vpad 通道（vpad_dpad + vpad_button/trigger）；hideShortcuts：
// 快捷键按钮区归手柄模块，画布按钮不参与。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleDpad,
        kRtCanvasModuleVpad,
        kRtCanvasOrientLandscape,
        kRtCanvasPresetGame;

/// 游戏布局出厂模板（横屏）。
const RtCanvasNamedLayout kRtCanvasTemplateGame = RtCanvasNamedLayout(
  id: kRtCanvasPresetGame,
  name: '游戏布局',
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
