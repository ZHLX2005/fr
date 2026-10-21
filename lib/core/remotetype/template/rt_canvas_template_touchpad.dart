// lib/core/remotetype/template/rt_canvas_template_touchpad.dart
//
// 内置布局模板 · 触控屏：满屏触摸板（原型 full）。不锁横屏 → 双朝向可用。

import '../rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasOrientLandscape,
        kRtCanvasPresetTouchpad;

/// 触控屏布局出厂模板（满屏触摸板，双朝向可用）。
const RtCanvasNamedLayout kRtCanvasTemplateTouchpad = RtCanvasNamedLayout(
  id: kRtCanvasPresetTouchpad,
  name: '触控屏布局',
  builtIn: true,
  orientation: kRtCanvasOrientLandscape,
  data: RtCanvasLayout(
    modules: {
      'touchpad': RtCanvasAnchor(
        visible: true,
        x: 0.50,
        y: 0.50,
        w: 1.0,
        h: 1.0,
      ),
    },
  ),
);
