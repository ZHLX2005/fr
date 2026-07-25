// lib/core/net_p2p/scripts/lobby_chat_script.dart
//
// 大厅等待 + 聊天（Lobby Chat）— net_p2p 的默认房间脚本。
// 简单：建房 → 等对手 → 房主点 START → 进入聊天模式。

/// 大厅等待 + 聊天脚本（kLobbyChatScript）
///
/// 包含两阶段状态机：
///   1. `lobby`  — 房主建房，玩家加入等待，房主点"开始"
///   2. `playing` — 开始后切换到聊天模式
///
/// ## context 字段
///
///   - `host_id`   : string, 房主 device_id
///   - `players`   : {device_id → alias}
///   - `max_players` : int, 房间容量
///   - `started`   : bool, 是否已开始
///   - `messages`  : [{text, alias, ...}, ...]
///
/// ## 事件类型
///
///   - `START`  → 房主触发（host_id 校验）→ state="playing"
///   - `CHAT`   → 任意玩家发消息 → 追加到 messages
///
/// ## 错误案例
///
/// | 错误写法 | 后果 | 正确写法 |
/// |----------|------|---------|
/// | `force_leave = {[d2]=true}` | 静默不生效 | `force_leave = {"d2"}` |
/// | handler 写在 return 表里而非全局 | CreateRoom 400 | handler 先顶层定义 `on_xxx=function...end` 再在 return 表里引用 |
/// | `type: "action_CHAT"` | 后端再补 `action_` → 422 | `type: "CHAT"` |
const String kLobbyChatScript = r'''
on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.max_players = p.max_players or 8
  c.started = false
  c.messages = {}
  state = "lobby"
  return c
end

on_join = function(c, p)
  c.players[p.device_id] = p.alias
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  return c
end

on_action_START = function(c, p)
  if c.host_id ~= p.device_id then
    return c
  end
  c.started = true
  state = "playing"
  return c
end

on_action_CHAT = function(c, p)
  table.insert(c.messages, p)
  return c
end

return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_START", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_START = on_action_START,
  on_action_CHAT = on_action_CHAT,
}
''';

/// 纯聊天脚本（kChatOnlyScript）— 无 lobby 阶段
///
/// 适合不需要等待、直接聊天的场景。
/// context: `{messages: [{text, alias, ...}]}`
const String kChatOnlyScript = r'''
on_init = function(c, p) c.messages = {}; return c end
on_join = function(c, p) return c end
on_leave = function(c, p) return c end
on_action_CHAT = function(c, p) table.insert(c.messages, p); return c end
return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_CHAT" } },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_CHAT = on_action_CHAT,
}
''';
