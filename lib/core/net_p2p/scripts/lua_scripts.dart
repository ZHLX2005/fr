// lib/core/net_p2p/scripts/lua_scripts.dart
//
// 所有 Lua 状态机脚本集中管理。
// 脚本是服务端权威的业务逻辑：客户端上传 → 后端 gopher-lua 执行 → snapshot 驱动。
//
// 按业务分类：
//   - lobbyChat：大厅等待 + 聊天（默认）
//   - ...扩展：可在同一文件追加新脚本

/// 大厅等待 + 聊天脚本（lobbyChat）
///
/// 包含两阶段状态机：
///   1. `lobby` — 房主建房，玩家加入等待，房主点"开始"
///   2. `playing` — 开始后切换到聊天模式
///
/// 状态 (state):
///   - "" (空) → 初始
///   - "lobby" → 大厅等待
///   - "playing" → 游戏中
///
/// context:
///   - `host_id` — 房主 device_id
///   - `players` — {device_id: alias, ...}
///   - `max_players` — 房间容量
///   - `started` — bool，是否已开始
///   - `messages` — 聊天消息列表
///
/// 事件类型 (ApplyAction type):
///   - `START` → 房主触发开始游戏
///   - `CHAT` → 发送聊天消息
///
/// ## 错误案例
///
/// | 错误写法 | 后果 | 正确写法 |
/// |----------|------|---------|
/// | `force_leave = {[d2]=true}` | 静默不生效 | `force_leave = {"d2"}` |
/// | handler 写在 return 表里而非全局 | CreateRoom 400 | handler 先顶层定义 `on_xxx=function...end` |
/// | `type: "action_CHAT"` | 后端再补 `action_` → 422 | `type: "CHAT"` |
///
/// ## handlers 必须是顶层全局函数
///
/// ```lua
/// -- ✅ 正确：先全局定义，再在 return 表里引用
/// on_init = function(c, p) ... end
/// return { definition = { functions = {"on_init"} }, on_init = on_init }
///
/// -- ❌ 错误：匿名函数不识别
/// return { definition = { functions = {"on_init"} },
///          on_init = function(c, p) ... end }
/// ```
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

/// 纯聊天脚本（无大厅阶段）
///
/// 适合不需要等待、直接聊天的场景（LAN 模式可直接对接）。
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
