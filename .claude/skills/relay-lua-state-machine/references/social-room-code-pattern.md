# 社交房间号模式 — 自定义房间号 + 房主自动判定

> 何时读：实现"用户自行约定房间号 + 第一个进入自动成为房主"的双人对战房间时。
> 与 `[[versus-game-room-template]]` 互补——模板讲"先建后加"流程，本文讲"两边输入同一号码，谁先到谁是房主"。

---

## 1. 设计目标

**社交场景**（微信群/Discord/线下面对面）：玩家在群里说"来 `GAME` 房间"，双方各自打开 app 输入 `GAME` + 昵称，第一个进入的自动成为房主（黑方先手），后到者执白。客户端不需要"建房 / 加入"两个按钮。

### 三层责任分布

| 层级 | 职责 |
|---|---|
| **服务端** | 提供机制：① `requested_code` 撞号返 409；② `rejected_join` 字段 → 409；③ 不强制业务规则 |
| **Lua 脚本** | 业务规则：① 第 1 个进入 = 房主（host_id）；② 人数上限通过 `rejected_join` 兜底 |
| **客户端** | UX：单按钮 + 区分"撞号"与"满员"两种 409 message |

服务端只提供机制，业务规则由 Lua 把守——**这是 v3 的核心设计**。

---

## 2. 服务端机制（无需改 Go 代码）

### 2.1 自定义房间号

```http
POST /api/v3/relay/rooms
{
  "script": "...",
  "initial_params": {...},
  "requested_code": "GAME",   // ← 新增
  "max_players": 2
}
```

| 场景 | 响应 |
|---|---|
| `requested_code` 为空 | 201 + 服务端生成 6 位 |
| 长度 4–6 位大写字母数字 | 201 + 使用该号 |
| 长度非法 | 400 `length must be 4-6` |
| 含易混字符 0/O/1/I/l | 400 `contains confusing character` |
| **已被占用** | **409 `code collision after retries`** |

### 2.2 `rejected_join` 字段

```lua
on_join = function(c, p)
  if count >= c.max_players then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
end
```

服务端检测到 `rejected_join[device_id] = true` 后：
- HTTP 409
- `device_id` 不写入 Subs（即便 WS 升级也找不到该设备）
- envelope message: `join rejected by script`

服务端 **不强制** 任何业务规则（不检查 `max_players`、不写 `players`），完全交给 Lua 决定。

---

## 3. Lua 脚本标准写法

### 3.1 完整模板

```lua
on_init = function(c, p)
  c.host_id = p.device_id
  -- 房主/先手约定：第 1 个进入 = host = 黑方
  c.black_player_id = p.device_id
  c.players = {}
  c.players[p.device_id] = p.alias
  c.ready = {}
  c.history = {}
  -- ★关键：把 max_players 注入到 context（其它 Lua 函数需要它做校验）
  c.max_players = p.max_players or 2
  -- 动作权限表（房主专属 DEAL/RESET）
  c.action_permissions = {
    ACK    = "any",
    DEAL   = "host",
    MOVE   = "current_player",
    RESIGN = "any",
    WIN    = "non_current_player",
    RESET  = "host",
  }
  state = "lobby"
  return c
end

on_join = function(c, p)
  -- 幂等：host 通过 /join 第一次进；重复 join 不处理
  if c.players[p.device_id] ~= nil then
    return c
  end

  -- ★人数上限（Lua 业务责任，通过 rejected_join 让服务端返 409）
  local count = 0
  for _, _ in pairs(c.players) do count = count + 1 end
  if count >= c.max_players then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end

  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  c.ready[p.device_id] = nil
  return c
end

on_action_ACK = function(c, p)
  -- ...
  -- 用 c.max_players 而不是写死 2（更通用）
  if count >= c.max_players and aready >= count and state == "lobby" then
    state = "ready"
  end
  return c
end
```

### 3.2 三个易错点

| 易错 | 后果 | 正确做法 |
|---|---|---|
| 忘记 `c.max_players = p.max_players` | `on_join` 校验时 `c.max_players` 为 nil → 不限人数 | 必须在 `on_init` 注入 |
| 写死 `count >= 2` | 双人房 4 人局时也按 2 校验 | 用 `count >= c.max_players` |
| 直接 `return c` 不设置 `rejected_join` | 服务端无 409 提示，客户端拿 200 当成功 | `c.rejected_join[p.device_id] = true` |

---

## 4. 客户端模式（Flutter）

### 4.1 Transport 改造

`createRoom` 加可选 `requestedCode`：

```dart
Future<RoomHandle> createRoom({
  required String script,
  required Map<String, dynamic> initialParams,
  int maxPlayers = 8,
  String? requestedCode,   // ← 新增
}) async {
  final body = <String, dynamic>{
    'script': script,
    'initial_params': {...},
    'max_players': maxPlayers,
    if (requestedCode != null && requestedCode.isNotEmpty)
      'requested_code': requestedCode,
  };
  // POST ...
}
```

新增 `tryJoinOrCreate`（先 join，404 fallback create）：

```dart
Future<RoomHandle> tryJoinOrCreate({
  required String code,
  required String script,
  required Map<String, dynamic> initialParams,
  int maxPlayers = 8,
}) async {
  try {
    return await joinRoom(code: code);
  } on RelayV3Exception catch (e) {
    if (e.statusCode != 404) rethrow;
    return await createRoom(
      script: script,
      initialParams: initialParams,
      maxPlayers: maxPlayers,
      requestedCode: code,
    );
  }
}
```

### 4.2 区分两种 409（撞号 vs 满员）

服务端两种 409 message 关键词不同：

| 场景 | message 含 |
|---|---|
| 撞号（服务端） | `code collision` |
| 满员（rejected_join） | `join rejected` |

客户端按 message 关键词区分提示：

```dart
final body = e.body.toLowerCase();
final String msg;
if (e.statusCode == 409 && body.contains('code collision')) {
  msg = '房间号 $code 已被占用，请换一个';
} else if (e.statusCode == 409 && body.contains('join rejected')) {
  msg = '房间 $code 已满员，无法加入';
} else if (e.statusCode == 404) {
  msg = '房间号 $code 不存在且创建失败';
} else {
  msg = '进入失败（${e.statusCode}）';
}
```

### 4.3 UX 提示文案

- 顶部 hint：`与朋友约定同一房间号，谁先到谁是房主（黑方先手），后到者执白。`
- 顶部小提示让用户**预期**会变成房主，避免"为什么我是黑方？"的困惑。
- 撞号提示要引导用户**换号**（`换一个`），不是直接说失败。
- 满员提示要明确说明**房间已存在**+**满员**，让用户去找朋友要新号或等一等。

---

## 5. 端到端验证（项目 `.tool/relay-room-tester`）

```text
场景 1: 空号创建 → 201 + 6 位 room_code                  OK
场景 2: 指定号创建 → 201 + 指定号                        OK
场景 3: 撞号创建 → 409 code collision                    OK
场景 4: 加入空号 → 404                                   OK
场景 5: 加入已存在房间 → 200                             OK
场景 6: tryJoinOrCreate（404 → 201）                     OK
场景 7: 第 3 人进满员房间（Lua 责任）→ 409 join rejected OK
场景 8: 房间码长度非法 → 400                             OK
场景 9: leave 后再 join → 200/404/409                    OK
场景 10: GET snapshot → 200                              OK
场景 11: 用项目内 kGomokuScript 端到端满员拒绝 → 409     OK
```

复跑命令：

```bash
cd .tool/relay-room-tester && uv run python3 scripts/test_rooms.py
```

---

## 6. 何时**不**用这个模式

| 场景 | 替代方案 |
|---|---|
| 旁观者制（主播+观众） | 用 `[[team-card-lobby-pattern]]` 双区槽位 |
| 多人房间（>2）+ 身份分配 | `[[team-card-lobby-pattern]]` 私有身份分配 |
| 私密房间（邀请制/密码） | 服务端需新增 password 字段，超出 v3 现成机制 |
| 不想让玩家共享号码 | 仍走 `[[versus-game-room-template]]` 的 CreateRoom 流程 |

---

## 7. 易错速查

| # | 错误 | 后果 | 正确做法 |
|---|---|---|---|
| 1 | Lua `on_join` 没设置 `rejected_join` | 第 3 人进入 3 人局（服务端无校验） | `c.rejected_join[p.device_id] = true` |
| 2 | 客户端 409 都报"已被占用" | 满员时用户不知道是"号被占"还是"房间满" | 按 message 关键词区分 |
| 3 | `requested_code` 含 0/O/1/I/l | 服务端 400 | UI 层只允许大写字母数字（去除易混） |
| 4 | `count >= 2` 写死 | 多人房间（如 4 人）永远停在 2 | 用 `c.max_players` |
| 5 | 客户端自己判断角色（"我是第一个创建的人"） | 撞号/重连时角色错乱 | 服务端权威 `host_id` / `black_player_id` |
| 6 | `tryJoinOrCreate` 没 catch 404 就走 create | 撞号（409）会被误当作"创建成功" | 只对 404 fallback，其它错误 rethrow |