// nav 家族 barrel —— 全局导航件的唯一入口（2026-10-28 细粒度收敛 R3）。
//
// 组成：
// - app_nav_bar.dart          页头导航三样式（standard 规范 / floating 浮层 / pill 浮卡）
// - nav_entry_icon.dart       导航条目图标
// - quick_nav_bottom_bar.dart 胶囊式底部导航
//
// 依赖方向：ui/global/nav → ui/global/button（原子件）、ui/nav（路由与条目模型）、ui/lab（lab 域图标）。
// 家族总行数 674 > 400，按规范用 barrel + 同目录实现文件并列。

export 'app_nav_bar.dart';
export 'nav_entry_icon.dart';
export 'quick_nav_bottom_bar.dart';
