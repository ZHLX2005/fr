// lib/core/remotetype/canvas/template/rt_canvas_template_game.dart
//
// 内置布局模板 · 方向键：四向十字（dir8=false）+ 键级直编排 vpad + 双摇杆。
// 锚点对齐 docs/prototypes/rt-gamepad-mode-dpad.html：
//   左上十字 / 右上面键 · 下 L/R 摇杆同高 · 肩扳贴左右侧缘 · Back/Start 居中偏上。
// 信号走 vpad 通道（vpad_dpad + vpad_button/trigger / vpad_axis）；
// hideShortcuts：快捷键按钮区归手柄键区，画布按钮不参与。
// 手柄 13 键无条目 = 出厂几何（rtVpadDefaultSlots 按画布尺寸实时算，
// 菱形间距不随宽高比变形）；显隐/摆位在编辑面板「手柄键区」区配置。
// 八向轮盘变体见 rt_canvas_template_game_wheel.dart（独立内置 id）。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleDpad,
        kRtCanvasModuleStickL,
        kRtCanvasModuleStickR,
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
    // 手柄键区区块在场：13 键无条目 = 出厂几何渲染 + 可见。
    vpadOn: true,
    modules: {
      // 左上四向十字。
      kRtCanvasModuleDpad: RtCanvasAnchor(
        visible: true,
        x: 0.21,
        y: 0.45,
        w: 0.18,
        h: 0.40,
      ),
      // 下双摇同高（左移 / 右瞄）。
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
