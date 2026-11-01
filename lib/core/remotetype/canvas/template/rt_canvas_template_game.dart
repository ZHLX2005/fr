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
        kRtCanvasModuleStickR,
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
      // 右摇杆（瞄准 / 视角）：落 dpad 与手柄键区之间的中缝空区。
      // anchor 语义 = 模块中心点，w/h 按画布归一化；摇杆实际直径取
      // min(w·W, h·H)（20:9 下 ≈120px），比「手动开启」时落在画布正中、
      // 扁成 0.46×0.18 的小球好用得多。h 取 0.34 让模块盒在 20:9 下接近
      // 正方——盒高与圆径齐平，命中区（圆的外接方框）不会大于可见控件。
      // x=0.51 是各比例下的安全位：摇杆命中方框与手柄键区的 L3 键不相交
      // （20:9 下圆与圆净距 ≈26px，命中方框右缘离 L3 键圆 ≈5px）。
      kRtCanvasModuleStickR: RtCanvasAnchor(
        visible: true,
        x: 0.51,
        y: 0.62,
        w: 0.15,
        h: 0.34,
      ),
    },
  ),
);
