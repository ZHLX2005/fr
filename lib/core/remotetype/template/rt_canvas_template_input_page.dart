// lib/core/remotetype/template/rt_canvas_template_input_page.dart
//
// 内置布局模板 · 输入页（竖屏默认）：连接后落到的打字页本身——满屏
// composer 模块（工具行 + 快捷键托盘 + 输入框）。竖屏激活兜底取它
// （内置列表里第一套真竖屏）；hideShortcuts：托盘在模块内，画布按钮区
// 不重复渲染。

import '../rt_prefs.dart'
    show
        RtCanvasAnchor,
        RtCanvasLayout,
        RtCanvasNamedLayout,
        kRtCanvasModuleComposer,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetInputPage;

/// 输入页出厂模板（竖屏默认布局）。
const RtCanvasNamedLayout kRtCanvasTemplateInputPage = RtCanvasNamedLayout(
  id: kRtCanvasPresetInputPage,
  name: '输入页',
  builtIn: true,
  orientation: kRtCanvasOrientPortrait,
  data: RtCanvasLayout(
    hideShortcuts: true,
    modules: {
      kRtCanvasModuleComposer: RtCanvasAnchor(
        visible: true,
        x: 0.50,
        y: 0.50,
        w: 1.0,
        h: 1.0,
      ),
    },
  ),
);
