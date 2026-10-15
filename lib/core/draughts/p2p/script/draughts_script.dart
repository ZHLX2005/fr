// lib/core/draughts/p2p/script/draughts_script.dart
//
// 国际跳棋的 net_p2p v3 Lua 状态机脚本入口（经 assembler 组装）。
//
// ## 拼接顺序（严格）
//
//   draughts_script.dart            ← 本文件：kDraughtsScript 入口
//   draughts_script_lifecycle.dart  ← helpers + on_init/on_join/on_leave
//   draughts_script_actions.dart    ← 所有 on_action_* handler
//   game_kit/emoji/emoji_script.dart ← 共享 emoji 段
//   game_kit/chat/chat_script.dart   ← 共享 chat 段
//
// 拼接顺序：lifecycle → actions → extraSegments(emoji, chat)。
// · Lua 全局查找发生在调用时 —— helper / on_init / on_join / on_leave
//   在 actions handler 调用时必须已定义。
// · 导出表 `return { definition, on_init, ... }` **由 assembler 统一生成放最后**：
//   handler 写在 return 表里而非顶层全局会触发 CreateRoom 400
//   （见 net-p2p-protocol-playbook 的 v3-lua-state-machine 易错点 #1）。
// · 每段 const String 末尾必须以 `\n` 结尾，保持 `_functionBlock` regex 块边界稳定。
//
// ## 服务端权威棋谱
//
// MOVE 只追加 `c.moves` + 更新 `c.fen`；**终局由客户端引擎判定后 CLAIM_END 上报**
// （与 chess_v5 同模式：relay 只做结构校验与轮次反证，不做跳棋规则推理）。
//
// ## 角色权限（action_permissions）
//
//   ACK          = "any"                双方都能在 lobby 阶段点准备
//   DEAL         = "host"               双方 ACK 后由 host 显式开局
//   SET_RULES    = "host"               准备阶段改执子色 / 残局（清 ready）
//   MOVE         = "current_player"     轮到谁走谁走
//   RESIGN       = "any"                任何一方任何时候都能投
//   DRAW_*       = "any"                议和流程任意一方发起
//   CLAIM_END    = "non_current_player" 刚走完的一方声明终局
//   RESET        = "host"               终局后 host 可重开
//   EMOJI / CHAT = "any"                共享段

import '../../../game_kit/chat/chat_script.dart' show kChatScriptSegment;
import '../../../game_kit/emoji/emoji_script.dart' show kEmojiScriptSegment;
import '../../../game_kit/emoji/lua_script_assembler.dart' show assembleLuaScript;
import 'draughts_script_actions.dart' show kDraughtsScriptActions;
import 'draughts_script_lifecycle.dart' show kDraughtsScriptLifecycle;

/// 国际跳棋 Lua 脚本（lifecycle + actions + emoji + chat）。
///
/// 在 net_p2p v3 的 `RelayV3Transport.createRoom()` 建对弈房时传入 —— 服务端按
/// sha256 缓存编译产物。拼接经由 [assembleLuaScript] 完成。
// ignore: prefer_const_declarations
final String kDraughtsScript = assembleLuaScript(
  lifecycle: kDraughtsScriptLifecycle,
  actions: kDraughtsScriptActions,
  extraSegments: [kEmojiScriptSegment, kChatScriptSegment],
);
