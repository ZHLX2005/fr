// renderers 家族 barrel —— 渲染器/画布类通用件的唯一入口（2026-10-28 细粒度收敛 R5）。
//
// 组成：
// - markdown_renderer_widget.dart       Markdown 渲染
// - html_renderer_widget.dart           HTML 渲染
// - image_picker_widget.dart            图片选择 + 裁剪（555 行，本身已超 400 行阈值，待专项拆）
// - hexagon_radar_painter.dart          六边形雷达图绘制
// - springy_banner.dart                 可拉伸 banner
// - bounded_bouncing_scroll_physics.dart 边界回弹滚动物理
//
// 家族总行数 1097 > 400，按规范用 barrel + 同目录实现文件并列。

export 'bounded_bouncing_scroll_physics.dart';
export 'hexagon_radar_painter.dart';
export 'html_renderer_widget.dart';
export 'image_picker_widget.dart';
export 'markdown_renderer_widget.dart';
export 'springy_banner.dart';
