// game 家族 barrel —— 联机 UI 件的唯一入口（2026-10-28 细粒度收敛 R6）。
//
// 组成：
// - game_ready_style.dart                就绪六件套（FloatCard / RoomCodeChip / TitleRule / Avatar / StatusBadge / CtaStyle）
// - game_lobby_page.dart                  通用大厅页（13 游戏接入）
// - _lobby_form.dart                     大厅表单（私有，仅 game_lobby_page 内部用，不 export）
// - board_chat_overlay.dart               棋盘聊天浮层
// - emoji_overlay.dart / emoji_panel.dart 表情飘字浮层 / 表情选择面板
// - relay_connection_bar.dart / relay_connection_status_badge.dart 连接状态条 / 徽标
// - lobby_participants.dart               大厅参与者圆环
// - relay_v3_lobby.dart                   v3 Lua 状态机大厅
//
// 家族总行数 3679 > 400，按规范用 barrel + 同目录实现文件并列。
// 依赖方向：ui/global/game → game_kit（纯逻辑）/ net_engine / core/nav。

export 'board_chat_overlay.dart';
export 'emoji_overlay.dart';
export 'emoji_panel.dart';
export 'game_lobby_page.dart';
export 'game_ready_style.dart';
export 'lobby_participants.dart';
export 'relay_connection_bar.dart';
export 'relay_connection_status_badge.dart';
export 'relay_v3_lobby.dart';
