// lib/core/remotetype/canvas/template/rt_canvas_template_keyboard.dart
//
// 内置布局模板 · 键盘：全键盘（Fn 行折叠，按键即发 hotkey）。
// 无输入条、无内嵌触摸板；hideShortcuts：键盘即打字面，画布按钮区不参与。

import '../../data/rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleKb,
        kRtCanvasOrientLandscape,
        kRtCanvasPresetKeyboard;

/// 键盘布局出厂模板（横屏）。
const RtCanvasNamedLayout kRtCanvasTemplateKeyboard = RtCanvasNamedLayout(
  id: kRtCanvasPresetKeyboard,
  name: '键盘布局',
  builtIn: true,
  orientation: kRtCanvasOrientLandscape,
  data: RtCanvasLayout(
    hideShortcuts: true,
    modules: {
      kRtCanvasModuleKb: RtCanvasAnchor(
        visible: true,
        x: 0.50,
        y: 0.55,
        w: 0.94,
        h: 0.82,
      ),
    },
  ),
);
