// lib/core/remotetype/canvas/template/rt_canvas_template_game_wheel.dart
//
// 内置布局模板 · 轮盘：左八向轮盘（dir8）+ 分布式 vpad + 双摇杆。
// 与「方向键布局」同锚点骨架（docs/prototypes/rt-gamepad-mode-wheel.html），
// 仅 dpad.dir8=true 区分手感——四向键 vs 斜向轮盘。
// hideShortcuts：快捷键按钮区归手柄模块。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleDpad,
        kRtCanvasModuleStickL,
        kRtCanvasModuleStickR,
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
        y: 0.45,
        w: 0.18,
        h: 0.40,
        dir8: true,
      ),
      kRtCanvasModuleVpad: RtCanvasAnchor(
        visible: true,
        x: 0.50,
        y: 0.50,
        w: 0.98,
        h: 0.92,
      ),
      kRtCanvasModuleStickL: RtCanvasAnchor(
        visible: true,
        x: 0.29,
        y: 0.82,
        w: 0.15,
        h: 0.28,
      ),
      kRtCanvasModuleStickR: RtCanvasAnchor(
        visible: true,
        x: 0.71,
        y: 0.82,
        w: 0.15,
        h: 0.28,
      ),
    },
  ),
);
