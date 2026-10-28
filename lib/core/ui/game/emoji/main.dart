// game/emoji barrel —— 游戏表情 UI 唯一入口（2026-10-28 职责清晰重构 N2）。
//
// 组成：
// - emoji_overlay.dart  表情飘字浮层
// - emoji_panel.dart    表情选择面板
//
// 家族总行数 490 > 400，按规范用 barrel + 同目录实现文件并列。
// 依赖方向：ui/game/emoji → ui/global/notification、game_kit（emoji bundle/snapshot/file_resolver）。

export 'emoji_overlay.dart';
export 'emoji_panel.dart';
