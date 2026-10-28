// game/home barrel —— 游戏大厅/入口类 UI 唯一入口（2026-10-28 职责清晰重构 N2）。
//
// 组成：
// - game_lobby_page.dart   通用大厅页（13 游戏接入）
// - _lobby_form.dart       大厅表单（私有，仅 game_lobby_page 内部用，不 export）
// - relay_v3_lobby.dart    v3 Lua 状态机大厅
// - lobby_participants.dart 大厅参与者圆环
//
// 家族总行数 1653 > 400，按规范用 barrel + 同目录实现文件并列。
// 依赖方向：ui/game/entry → ui/global/*（全局件）、game_kit（纯逻辑）、net_engine。

export 'game_lobby_page.dart';
export 'lobby_participants.dart';
export 'relay_v3_lobby.dart';
