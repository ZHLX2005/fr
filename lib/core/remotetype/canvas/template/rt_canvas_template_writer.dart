// lib/core/remotetype/canvas/template/rt_canvas_template_writer.dart
//
// 内置布局模板 · 写字页（kind=writer）：连接后落到的打字页本身。
//
// 与其它内置模板的关键差别——它是**固定死**的默认布局：
//   · editable = false：不做模块化编排（不拆锚点模块、不摆按钮位），
//     持久化里的任何改动一律忽略，用户也不能重命名 / 删除；
//   · kind = writer：由 rt_page 的写字渲染路径接管，不进画布；
//   · orientation = portrait：横屏没有写字形态（横屏只有画布）。
//
// 「打完字接着操作」是 RT 的主场景，默认入口就该是它——所以它排在
// 内置列表第一位。

import '../../data/rt_prefs.dart'
    show
        RtCanvasLayout,
        RtCanvasNamedLayout,
        RtLayoutKind,
        kRtCanvasOrientPortrait,
        kRtCanvasPresetWriter;

/// 写字页出厂模板（固定死的默认布局）。
const RtCanvasNamedLayout kRtCanvasTemplateWriter = RtCanvasNamedLayout(
  id: kRtCanvasPresetWriter,
  name: '写字',
  builtIn: true,
  editable: false,
  kind: RtLayoutKind.writer,
  orientation: kRtCanvasOrientPortrait,
  data: RtCanvasLayout(),
);
