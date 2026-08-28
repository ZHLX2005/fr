// lib/lab/demos/cowrite_lua/cowrite_lua_script.dart
//
// Co-Write Notebook（双人协作笔记本）— v3 Lua 状态机脚本。
//
// ## 状态机
//
// ```
//    tryJoinOrCreate → state="lobby"   不需要 ACK，直接进 playing
//    EDIT            → state 不变      双方实时同步笔记内容
//    START_BROADCAST → state 不变      申请占用首行广播权（仅当无人占用）
//    STOP_BROADCAST  → state 不变      主动释放
//    BROADCAST_LINE  → state 不变      持有者更新视图首行行号
//    SET_FOLLOW      → state 不变      开关"自动对齐到对方首行"
//    LEAVE           → 自动清理（on_leave）
// ```
//
// ## context 字段（服务端权威）
//
//   - `players`            : {device_id: alias, …}
//   - `content`            : string                笔记全文（任意一方 EDIT 都会更新）
//   - `broadcaster_id`     : string|nil           占用首行广播权的人
//   - `broadcaster_line`   : number|nil           持有者广播的"视图首行行号"（1-indexed）
//   - `broadcaster_version`: number|nil           单调递增版本号（防止旧视图覆盖新视图）
//   - `follow_settings`    : {device_id: bool}    谁开启"自动对齐到对方首行"
//   - `max_players`        : number               = 2
//
// ## 协作模型
//
//   - 内容：任意人 EDIT 全量覆盖（O(text) 网络开销；2 人协作可接受；不存历史）
//   - 广播权：单一持有者；先到先得（rejected_join / 抢锁）；自己主动 STOP 才放手
//   - 自动对齐：开启者收到广播 → 把自己的滚动位置调到"自己的第 N 行"
//
// ## 不需要 ACK
//
//   这是协作工具不是游戏 —— 输入房间号即进（max_players 校验仍在 on_join 里做）。

const String kCoWriteScript = r'''
-- 角色权限检查（轻量版：只用到 host / any 两种）
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  return false
end

on_init = function(c, p)
  c.host_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.content = ""                    -- 笔记初始为空
  c.broadcaster_id = nil            -- 无广播持有者
  c.broadcaster_line = nil
  c.broadcaster_version = nil
  c.follow_settings = {}            -- 自动对齐开关表
  c.max_players = p.max_players or 2
  c.action_permissions = {
    EDIT            = "any",       -- 双方都能编辑
    START_BROADCAST = "any",       -- 任意人可申请（抢锁式）
    STOP_BROADCAST  = "broadcaster",-- 只有当前持有者能停
    BROADCAST_LINE  = "broadcaster",-- 只有当前持有者能更新行号
    SET_FOLLOW      = "any",       -- 任意人可改自己的 follow 偏好
  }
  state = "lobby"
  return c
end

-- 角色 rule = "broadcaster"：只有当前持有者
function role_check_broadcaster(c, p)
  if c.players[p.device_id] == nil then return false end
  return p.device_id == c.broadcaster_id
end

on_join = function(c, p)
  -- 幂等：同 device_id 重连不重复入
  if c.players[p.device_id] ~= nil then return c end
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  if count >= c.max_players then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
  c.players[p.device_id] = p.alias
  -- 离开期间广播权被服务端清掉？保留（持有者退出时 on_leave 已清）
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.follow_settings[p.device_id] = nil
  -- 持有者离开 → 自动释放广播权
  if c.broadcaster_id == p.device_id then
    c.broadcaster_id = nil
    c.broadcaster_line = nil
    c.broadcaster_version = nil
  end
  -- 房间空了 → 清空内容（隐私；新用户进来从零开始）
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  if count == 0 then
    c.content = ""
  end
  return c
end

on_action_EDIT = function(c, p)
  if not role_check(c, p, "EDIT") then return c end
  if c.players[p.device_id] == nil then return c end
  if type(p.content) ~= "string" then return c end
  -- 长度截断（防御）
  if #p.content > 20000 then
    p.content = string.sub(p.content, 1, 20000)
  end
  c.content = p.content
  return c
end

on_action_START_BROADCAST = function(c, p)
  if not role_check(c, p, "START_BROADCAST") then return c end
  if c.players[p.device_id] == nil then return c end
  -- 抢锁式：已被他人占 → 拒绝（不踢人；前端提示等待）
  if c.broadcaster_id ~= nil and c.broadcaster_id ~= p.device_id then
    return c
  end
  -- 自己已经是 → 幂等
  c.broadcaster_id = p.device_id
  c.broadcaster_line = 1
  c.broadcaster_version = (c.broadcaster_version or 0) + 1
  return c
end

on_action_STOP_BROADCAST = function(c, p)
  if not role_check_broadcaster(c, p) then return c end
  c.broadcaster_id = nil
  c.broadcaster_line = nil
  c.broadcaster_version = (c.broadcaster_version or 0) + 1
  return c
end

on_action_BROADCAST_LINE = function(c, p)
  if not role_check_broadcaster(c, p) then return c end
  if type(p.line) ~= "number" or p.line < 1 then return c end
  c.broadcaster_line = math.floor(p.line)
  c.broadcaster_version = (c.broadcaster_version or 0) + 1
  return c
end

on_action_SET_FOLLOW = function(c, p)
  if not role_check(c, p, "SET_FOLLOW") then return c end
  if c.players[p.device_id] == nil then return c end
  c.follow_settings[p.device_id] = (p.follow == true)
  return c
end

return {
  definition = { functions = {
    "on_init", "on_join", "on_leave",
    "on_action_EDIT",
    "on_action_START_BROADCAST", "on_action_STOP_BROADCAST",
    "on_action_BROADCAST_LINE", "on_action_SET_FOLLOW",
  }},
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_EDIT = on_action_EDIT,
  on_action_START_BROADCAST = on_action_START_BROADCAST,
  on_action_STOP_BROADCAST = on_action_STOP_BROADCAST,
  on_action_BROADCAST_LINE = on_action_BROADCAST_LINE,
  on_action_SET_FOLLOW = on_action_SET_FOLLOW,
}
''';
