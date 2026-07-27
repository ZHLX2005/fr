---
name: v3-lua-state-machine
description: v3 协议详细参考 — Lua 状态机后端，服务端内置 gopher-lua 解释器，客户端上传 Lua 脚本定义数据模型+事件函数，后端权威计算 snapshot。新业务/可编程后端/多租户状态机场景走这个。排查"业务逻辑前后端重复""客户端下线房间失效""多端竞态写"时优先读
---
# V3 Lua State Machine Protocol

Relay 协议 v3 = **可编程后端状态机**。客户端上传 Lua 脚本（数据模型 + 事件处理函数），后端编译并成为房间状态的**唯一计算来源**。

> 新业务 / 需要服务端权威业务逻辑 / 多场景不同状态机 → 走 v3。
> v2 已被 v3 完全取代（v2 代码已删除）；LAN 模式保留 v1。

**与 v2 的本质区别**：v2 的 `ApplyAction` 在 Go 里硬编码（只有 `chat` + `lastAction`）；v3 把"action 怎么改变 state"的逻辑**完全交给前端上传的 Lua 脚本**——后端退化成通用解释器 + 路由器。

---

## 1. 后端技术栈

| 技术                             | 版本   | 角色                                                        |
| -------------------------------- | ------ | ----------------------------------------------------------- |
| Go                               | 1.25   | 后端语言                                                    |
| GoFrame                          | v2.10  | HTTP 框架（DTO + 控制器 + 中间件 + OpenAPI 自动生成）       |
| `github.com/yuin/gopher-lua`   | v1.1.0 | **纯 Go 实现的 Lua 5.1 解释器**（无 cgo，跨平台编译） |
| `github.com/gorilla/websocket` | v1.5.3 | WS 升级 + 帧读写（与 v2 同一依赖）                          |
| `sync.Pool`                    | stdlib | Lua VM 池化（避免每次 action 重建 VM）                      |
| `sync.Mutex`                   | stdlib | per-room 串行化（零竞态保证）                               |
| `crypto/sha256`                | stdlib | 脚本内容哈希（去重 + 快照身份）                             |
| `encoding/json`                | stdlib | snapshot 序列化（Go ↔ Lua table 桥梁）                     |

**没有的**：Redis / PostgreSQL / SQLite（v3 纯内存，进程生命周期）、JWT/Token（v3 无鉴权，与 v2 一致）、任何外部状态存储。

### 1.1 为什么选 gopher-lua

| 候选                     | 为什么不选                                         |
| ------------------------ | -------------------------------------------------- |
| C LuaJIT                 | cgo 依赖，跨平台编译复杂；2C2G 部署不友好          |
| 前端传 JS 函数 + vm 沙箱 | API 表面大，安全风险高，多客户端版本兼容地狱       |
| WASM (wasmtime)          | 编译链复杂，单个函数体积大，调试困难               |
| **gopher-lua** ✅  | 纯 Go、热更新友好、沙箱成熟、游戏/规则引擎经典方案 |

### 1.2 性能特征（2 核 2G 实测预估）

| 指标                                   | 数值                              |
| -------------------------------------- | --------------------------------- |
| 单次 Lua VM 创建                       | ~5-20μs、~170KB 内存             |
| `CompileString`（CreateRoom 时一次） | ~19μs                            |
| `RunEvent`（每次 action）            | ~1.1μs（预编译 proto + 池化 VM） |
| 简单脚本 + HTTP + 内存存储 QPS         | 3000-8000                         |
| 常驻 WS 房间上限                       | 300-800                           |
| 总房间数（含冷快照，若有持久化）       | 几万                              |

**关键优化**：脚本在 CreateRoom 时 `CompileString` 一次 → proto 按 `sha256(src)` 缓存 → 后续 action 只 `Push(proto)` 执行，不重新编译。

---

## 2. 核心架构

```
┌──────────────────────────────────────────────────────────────────┐
│                    Flutter client (net_p2p/v3)                   │
│   RelayV3Transport                                                │
│     • createRoom(script, initial)  → POST /api/v3/relay/rooms    │
│     • joinRoom(code)                → POST .../join              │
│     • applyAction(type, params)     → POST .../actions           │
│     • snapshotStream(code)          → WS  /ws3/{code}            │
└──────────────────────────────────────────────────────────────────┘
                            │                       ▲
                            ▼ HTTP（actions）       │ WS（snapshot 推送）
┌──────────────────────────────────────────────────────────────────┐
│                  Go backend (internal/relay/v3/)                 │
│                                                                  │
│   Controller (HTTP)            Transport (WS)                    │
│     /api/v3/relay/...           /ws3/{code}                      │
│                                                                  │
│   Service (singleton via v3.Default())                          │
│     rooms:   map[code]*Room        ← 房间路由表                  │
│     scripts: map[hash]*FunctionProto ← 编译产物去重缓存          │
│     vmPool:  sync.Pool of *LState  ← VM 复用                     │
│                                                                  │
│   Lua runtime (lua.go)                                           │
│     CompileScript / NewSandbox / RunEvent                        │
│     Sandbox: base + table + string + math + wrapped os          │
└──────────────────────────────────────────────────────────────────┘
```

**核心不变量**：

- **服务端权威**：snapshot 是唯一真相，客户端零合并（与 v2 一致）
- **零竞态**：每个房间的 action 由 per-room `sync.Mutex` 串行化
- **晚加入者不丢**：WS 升级后服务端立即推当前 snapshot 作为第一帧
- **业务逻辑可编程**：state 如何变化由 Lua 脚本决定，Go 不硬编码业务规则

---

## 3. Lua 脚本在架构中的使用方式

### 3.1 脚本三类内容（一个 bundle）

客户端上传的不是"一个房间的实现"，而是"一份 self-contained 业务 bundle"：

| 角色                     | 在脚本里的位置              | 谁负责                        | 进 snapshot 吗          |
| ------------------------ | --------------------------- | ----------------------------- | ----------------------- |
| **静态业务数据**   | 顶层`local DATA = {...}`  | 客户端写死，运行时只读        | ❌ 已在`ScriptSrc` 里 |
| **房间运行时数据** | 全局`state` + `context` | 服务端注入；脚本读写；return  | ✅ 序列化进 JSON        |
| **事件处理函数**   | 顶层`on_<EVENT>`          | 客户端上传，CreateRoom 时编译 | ❌ 是代码不是数据       |

> **"给 code 即可获得一切"**：snapshot 携带 `ScriptSrc`，任何持有 snapshot 的进程能重建整个 bundle（静态数据 + handlers + 运行时 state）。

### 3.2 脚本格式（★ 关键：handlers 必须是顶层全局）

```lua
-- ============================================================
-- 静态业务数据：编译期固定，运行时只读。不进 snapshot。
-- ============================================================
local RULES = { starting_hp = 20, hand_size = 5 }
local CARD_LIBRARY = {
  {id = "fireball", cost = 3, dmg = 5},
  {id = "heal",     cost = 2, hp  = 4},
}

-- ============================================================
-- 事件处理函数：必须是顶层全局（不是 return table 里的字段！）
-- 服务端用 GetGlobal("on_<event>") 查找，table 字段查不到。
-- ============================================================
on_init = function(c, p)
  c.players = {}
  c.deck = {}
  c.turn = 1
  return c
end

on_join = function(c, p)
  local pid = p.device_id
  if not c.players[pid] then
    c.players[pid] = {alias = p.alias, hp = RULES.starting_hp, hand = {}}
  end
  return c
end

on_leave = function(c, p)
  c.players[p.device_id] = nil
  return c
end

on_action_DRAW_CARD = function(c, p)
  local player = c.players[p.source_device_id]
  if #player.hand < RULES.hand_size then
    table.insert(player.hand, table.remove(c.deck, math.random(#c.deck)))
  end
  return c
end

-- ============================================================
-- 返回表：声明哪些 on_* 存在 + 引用上面的全局
-- ============================================================
return {
  definition = {
    state_machine = { initial = "lobby", states = { ... } },  -- 文档性，服务端不校验
    schema        = { ... },                                   -- 文档性
    functions     = {
      "on_init", "on_join", "on_leave", "on_action_DRAW_CARD"
    }
  },
  on_init = on_init,
  on_join = on_join,
  on_leave = on_leave,
  on_action_DRAW_CARD = on_action_DRAW_CARD,
}
```

> **易错点**：把 `on_X = function...end` 写在 return table **里面**（作为字段）是错的——`CompileScript` 会报 `definition.functions declares "on_init" but no global function of that name`。必须先定义全局，再在 return table 里引用。

### 3.3 生命周期回调（服务端硬编码的事件名）

| 函数                                  | 触发时机                              | params                   | 必须？                          |
| ------------------------------------- | ------------------------------------- | ------------------------ | ------------------------------- |
| `on_init(context, params)`          | CreateRoom                            | 请求的`initial_params` | ✅ 设置初始 state/context       |
| `on_join(context, params)`          | HTTP`/join` 成功                    | `{device_id, alias}`   | ✅ 维护`context.participants` |
| `on_leave(context, params)`         | `/leave` / WS 断开 / 脚本踢人 / TTL | `{device_id, reason}`  | ✅ 清理 participants            |
| `on_action_<TYPE>(context, params)` | HTTP`/actions`                      | 请求的`params`         | 按业务需要                      |

`reason` 取值：`"graceful"` / `"disconnect"` / `"kicked"` / `"room_evicted"`。

### 3.4 脚本能控制服务端的两个特殊返回值

| 字段                      | 形状                                | 服务端反应                                                                                          |
| ------------------------- | ----------------------------------- | --------------------------------------------------------------------------------------------------- |
| `context.force_leave`   | `[]string` 数组（device_id 列表） | 把对应 WS 用 4403 关闭，逐个再跑一次`on_leave(reason="kicked")`，写一条 `__force_leave` history |
| `context.rejected_join` | `map[string]bool`                 | 若含当前 join 的 device_id → HTTP 409，不写 Subs，关 WS 4403                                       |

```lua
on_join = function(c, p)
  if c.banned and c.banned[p.device_id] then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true
    return c
  end
  -- 正常加入...
end

on_action_KICK = function(c, p)
  if c.host == p.source_device_id then
    c.force_leave = { p.target_device_id }  -- 数组形式
  end
  return c
end
```

> **易错点**：`force_leave` 必须是**数组** `{"d2"}`，不是 map `{d2 = true}`。map 形式会静默不生效（类型断言失败）。

### 3.5 沙箱（NewSandbox）

| 库                                                           | 状态               | 说明                               |
| ------------------------------------------------------------ | ------------------ | ---------------------------------- |
| `base` / `table` / `string` / `math`                 | ✅ 开放            | 纯计算                             |
| `os.time` / `os.date` / `os.difftime`                  | ✅ 开放（wrapped） | 时间戳逻辑                         |
| `os.execute` / `os.remove` / `os.exit` / `os.getenv` | ❌ nil             | 安全                               |
| `io` / `debug` / `package` / `require`               | ❌ nil             | 不能读文件、不能 require、不能反射 |

脚本只能做纯计算 + 时间戳，不能读文件系统、不能执行命令、不能 require 外部模块。

---

## 4. 服务端关键代码（Go）

### 4.1 数据类型 — `internal/relay/v3/state.go`

```go
// Snapshot 是房间状态的唯一权威来源（携带 ScriptSrc 实现"给 code 即得一切"）
type Snapshot struct {
    Code       string         `json:"room_code"`
    ScriptHash string         `json:"script_hash"`
    ScriptSrc  string         `json:"script_src"`
    Context    map[string]any `json:"context"`     // Lua 全权拥有
    State      string         `json:"state"`       // Lua 全权拥有
    Version    int64          `json:"version"`     // 单调递增
    CreatedAt  time.Time      `json:"created_at"`
    UpdatedAt  time.Time      `json:"updated_at"`
    History    []HistoryEntry `json:"history"`     // 最多 50 条
}

// Room 是 Go 侧路由对象（不持有业务状态，业务状态全在 Snapshot.Context）
type Room struct {
    Code         string
    Snapshot     *Snapshot
    Script       *lua.FunctionProto      // CreateRoom 时编译一次
    ScriptHash   string
    Funcs        []string                // definition.functions 列表
    mu           sync.Mutex              // per-room 串行化
    Subs         map[string]*Subscriber  // deviceID → sub
    ConnToDev    map[string]string       // WS conn 指针 → deviceID
    LastActionAt time.Time               // TTL 30 分钟空闲清理
}
```

### 4.2 Lua 运行时 — `internal/relay/v3/lua.go`

```go
// NewSandbox 创建一个受限 LState：只开 base/table/string/math + wrapped os
func NewSandbox() *lua.LState {
    L := lua.NewState()
    L.OpenLibs()
    L.SetGlobal("io", lua.LNil)
    L.SetGlobal("debug", lua.LNil)
    L.SetGlobal("package", lua.LNil)
    L.SetGlobal("require", lua.LNil)
    // os 替换为只含 time/date/difftime 的新表
    safeOs := L.NewTable()
    L.SetField(safeOs, "time",    L.GetField(L.GetGlobal("os"), "time"))
    L.SetField(safeOs, "date",    L.GetField(L.GetGlobal("os"), "date"))
    L.SetField(safeOs, "difftime", L.GetField(L.GetGlobal("os"), "difftime"))
    L.SetGlobal("os", safeOs)
    return L
}

// CompileScript：解析 + 编译 + 结构校验
// 返回 proto（给 VM 执行）+ funcs（事件名列表）+ hash（sha256 去重键）
func CompileScript(src string) (*lua.FunctionProto, []string, string, error) {
    // 1. lua.Parse + lua.Compile → proto
    // 2. 在 sandbox VM 里执行 proto，拿到 return table
    // 3. 校验 definition.functions 是字符串数组
    // 4. 校验每个名字都是全局函数（GetGlobal(name).Type == LTFunction）
    // 5. hash = sha256(src)
}

// RunEvent：核心执行（每次 action 调一次）
func RunEvent(L, proto, funcs, eventName, state, context, params) (newState, newContext, error) {
    // 1. handler = GetGlobal("on_" + eventName)；没有则回退 handle_event
    // 2. 注入全局：state / context / params
    // 3. L.PCall(2, 1) 调 handler(context, params)
    // 4. 读回全局 state + 返回值 context
    // 5. json.Marshal 校验可序列化
    // 6. 清空 per-action 全局（state/context/params = nil），VM 还池
}
```

### 4.3 Service 热路径 — `internal/relay/v3/service.go`

```go
type Service struct {
    mu       sync.Mutex
    rooms    map[string]*Room                  // code → room
    scripts  map[string]*lua.FunctionProto     // hash → proto（去重）
    vmPool   sync.Pool                         // *LState 池
    historyCap int                             // 默认 50
    codeTTL  time.Duration                     // 30 分钟
}

// ApplyAction 是热路径：lock room → VM run → new snap → publish
func (s *Service) ApplyAction(code string, act Action) (*Snapshot, error) {
    r := s.getRoom(code)
    r.mu.Lock()
    defer r.mu.Unlock()

    // CAS 校验（可选）
    if act.ExpectVersion != nil && *act.ExpectVersion != r.Snapshot.Version {
        return r.Snapshot, ErrVersionMismatch
    }

    L := s.vmPool.Get().(*lua.LState)
    defer func() {
        L.SetGlobal("state", lua.LNil)
        L.SetGlobal("context", lua.LNil)
        L.SetGlobal("params", lua.LNil)
        s.vmPool.Put(L)
    }()

    // 热路径核心：3 步
    newState, newCtx, err := RunEvent(L, r.Script, r.Funcs, act.Type,
        r.Snapshot.State, r.Snapshot.Context, act.Params)
    if err != nil {
        return r.Snapshot, err  // snapshot 不变
    }

    // 全新 snapshot（不可变值语义——旧指针仍有效）
    r.Snapshot = &Snapshot{
        Code: r.Code, ScriptHash: r.ScriptHash, ScriptSrc: r.Snapshot.ScriptSrc,
        Context: newCtx, State: newState,
        Version: r.Snapshot.Version + 1,
        // ... append history (cap 50) ...
    }
    r.LastActionAt = time.Now()

    // 广播（在锁内拷贝 subs 引用，锁内调用 broadcastSubs——后者不再取锁）
    s.broadcastSubs(copySubs(r.Subs), r.Snapshot)
    return r.Snapshot, nil
}
```

### 4.4 锁与广播的避坑（关键设计）

`ApplyAction` 持有 `r.mu`，结尾要广播。**不能**让 `PublishSnapshot` 自己再 `getRoom + r.mu.Lock`——会自死锁。解法：

```go
// broadcastSubs 不取任何锁——调用方负责在锁内拷贝 subs 列表
func (s *Service) broadcastSubs(subs []*Subscriber, snap *Snapshot) {
    frame, _ := snapshotFrame(snap)  // {type:"snapshot", data:snap, ts:...}
    for _, sub := range subs {
        if sub.closed.Load() { continue }
        select {
        case sub.Send <- frame:            // 正常发
        default:                           // 慢消费者
            select { case <-sub.Send: default: }  // 丢最老
            select { case sub.dropSignal <- struct{}{}: default: }  // 通知 writer
            select { case sub.Send <- frame: default: }  // 重试一次
        }
    }
}

// 对外的 PublishSnapshot（外部调用，自己取锁拷贝 subs 再广播）
func (s *Service) PublishSnapshot(code string, snap *Snapshot) {
    r := s.getRoom(code)
    r.mu.Lock()
    subs := copySubs(r.Subs)
    r.mu.Unlock()
    s.broadcastSubs(subs, snap)
}
```

### 4.5 WS Transport — `internal/relay/v3/transport.go`

```go
func HandleWS(r *ghttp.Request) {
    code := r.GetRouter("code").String()
    deviceID := r.GetQuery("device_id").String()
    // 校验：device_id 必须已通过 /join 注册到 Subs，否则 4400

    room := Default.getRoom(code)
    sub := room.Subs[deviceID]

    // ★ 单连接每设备：若已有旧 conn，关闭旧的（4409 replaced）
    if sub.conn != nil { sub.conn.Close() }
    conn, _ := upgrader.Upgrade(...)
    sub.conn = conn

    // ★ 升级后立即推当前 snapshot（不是 Subs 里残留的旧帧）
    fresh, _ := SnapshotFrame(room.Snapshot)
    select { case sub.Send <- fresh: default: }

    // writer loop：drain sub.Send，ping 30s，dropSignal 累计 5 次后 4408
    // reader loop：仅检测关闭（v3 不接收客户端帧，action 走 HTTP）

    // 断开时：5 秒 grace window
    //   graceCancel 在锁内设置；reconnect 在锁内取消
    //   5 秒内同 device_id 重连 → 跳过 on_leave("disconnect")
    //   超时 → leaveInternal(code, deviceID, "disconnect")
}
```

### 4.6 HTTP 控制面 + 错误码映射 — `internal/controller/relay/v3/relay.go`

```go
// httpStatusFor 把 sentinel error 映射到 HTTP 状态码
//   ErrRoomNotFound/ErrRoomExpired → 404
//   ErrVersionMismatch/ErrJoinRejected → 409
//   ErrCodeCollision → 503
//   ErrUnknownEvent + lua runtime/parse/compile → 422 / 400
func (c *ControllerV3) ApplyAction(ctx, req) (*ActionRes, error) {
    snap, err := relayv3.Default.ApplyAction(req.Code, relayv3.Action{
        Type: "action_" + req.Type,  // ★ controller 加 action_ 前缀
        Params: req.Params, ExpectVersion: req.ExpectVersion,
        SourceDeviceID: req.SourceDeviceID,
    })
    if err != nil {
        if r := g.RequestFromCtx(ctx); r != nil {
            r.Response.Status = httpStatusFor(err)  // 设 HTTP 状态行
        }
        return nil, err  // gerror 仍包装；中间件写 body
    }
    return &ActionRes{Snapshot: snap}, nil
}
```

> **前缀双重叠加**：客户端发 `type:"CHAT"` → controller 加 `action_` → `action_CHAT` → RunEvent 加 `on_` → 查找全局 `on_action_CHAT`。客户端不要自己加 `action_` 前缀（会变成 `on_action_action_CHAT` → 422）。

### 4.7 路由注册 — `internal/cmd/cmd.go`

```go
// v3 HTTP 控制面（DTO 的 g.Meta path 是 /relay/rooms，group 前缀拼 /api/v3）
group.Group("/api/v3", func(api *ghttp.RouterGroup) {
    api.Middleware(ghttp.MiddlewareHandlerResponse)
    api.Bind(relayv3controller.New())
})
// v3 WS（raw handler，不经过 api.Bind 因为要 upgrade）
group.GET("/ws3/{code}", relayv3.HandleWS)
```

---

## 5. 数据流

### 5.1 CreateRoom（上传脚本 + 编译 + on_init）

```
client                       controller              Service             Lua runtime
  │ POST /api/v3/relay/rooms   │                        │                    │
  │ {script, initial_params,   │                        │                    │
  │  alias, device_id}         │                        │                    │
  ├───────────────────────────>│ CreateRoom             │                    │
  │                            ├───────────────────────>│ CompileScript      │
  │                            │                        ├───────────────────>│
  │                            │                        │ <- proto, funcs, hash
  │                            │                        │ scripts[hash] = proto (去重)
  │                            │                        │                    │
  │                            │                        │ vmPool.Get()       │
  │                            │                        │ RunEvent("init",   │
  │                            │                        │   initial_params)  │
  │                            │                        ├───────────────────>│
  │                            │                        │ <- newState, newCtx│
  │                            │                        │ vmPool.Put()       │
  │                            │                        │                    │
  │                            │                        │ allocCode (6位, 碰撞重试5次)
  │                            │                        │ rooms[code] = room │
  │                            │ <- snapshot            │                    │
  │ <- 201 {room_code, ws_url, snapshot}                │                    │
```

### 5.2 Action（HTTP POST → Lua → 广播）

```
client          controller       Service          Lua runtime       subscribers
  │ POST /actions  │                │                 │                 │
  │ {type, params,  │                │                 │                 │
  │  expect_version}│                │                 │                 │
  ├────────────────>│ ApplyAction   │                 │                 │
  │                 ├──────────────>│ r.mu.Lock()     │                 │
  │                 │               │ CAS check       │                 │
  │                 │               │ vmPool.Get()    │                 │
  │                 │               │ RunEvent(act.Type, ...)           │
  │                 │               ├────────────────>│ run on_<TYPE>   │
  │                 │               │ <- newCtx       │                 │
  │                 │               │ vmPool.Put()    │                 │
  │                 │               │ new Snapshot (v+1)                │
  │                 │               │ broadcastSubs ─────────────────────>│
  │                 │ <- newSnap    │                 │                 │
  │ <- 200 + newSnap│               │                 │                 │
```

### 5.3 WS 订阅（晚加入者第一帧就是当前 snapshot）

```
client                          transport              Service
  │ GET /ws3/{code}?device_id=X  │                       │
  ├─────────────────────────────>│ getRoom               │
  │                              │ sub = Subs[device_id] │ (必须先 /join 注册)
  │                              │ close old conn (4409) │
  │ 101 Switching Protocols       │ upgrade               │
  │ <─────────────────────────────│                       │
  │                              │ push fresh snapshot   │
  │ {type:"snapshot", data:{...}}│                       │
  │ <─────────────────────────────│                       │
  │                              │                       │
  │ ... 后续 ApplyAction 触发 ... │                       │
  │ {type:"snapshot", data:{新}}  │ PublishSnapshot       │
  │ <─────────────────────────────│                       │
```

---

## 6. 前端契约（Dart）

### 6.1 RelayV3Transport — `lib/core/net_engine/relay_v3/relay_v3_transport.dart`

```dart
class RelayV3Transport {
  final String relayUrl, alias, deviceId;

  Future<RoomHandle> createRoom({script, initialParams, maxPlayers = 8});
  Future<RoomHandle> joinRoom({code});
  Future<Snapshot>   fetchSnapshot(code);
}

class RoomHandle {
  final RelayV3Transport transport;
  final String code, wsUrl;
  Snapshot? latest;
  Stream<Snapshot> snapshots;   // connect() 后开始推送

  Future<void>   connect();     // WS + 指数退避重连（500ms→30s 上限）
  Future<Snapshot> applyAction({type, params, expectVersion?, sourceDeviceId?});
  Future<void>   leave();       // POST /leave + dispose
  Future<void>   dispose();     // idempotent（_disposed 守卫）
}
```

### 6.2 默认聊天脚本（生产用）— `net_p2p_discovery_host.dart`

```dart
const _defaultChatScript = '''
on_init = function(c, p) c.messages = {}; return c end
on_join = function(c, p) return c end
on_leave = function(c, p) return c end
on_action_CHAT = function(c, p) table.insert(c.messages, p); return c end
return {
  definition = { functions = { "on_init", "on_join", "on_leave", "on_action_CHAT" } },
  on_init = on_init, on_join = on_join, on_leave = on_leave, on_action_CHAT = on_action_CHAT,
}
''';
```

---

## 7. v3 核心保证

| 保证                     | 实现机制                                                         |
| ------------------------ | ---------------------------------------------------------------- |
| **离线不掉**       | 客户端下线不影响房间运转；只要后端在跑，snapshot 持续演进        |
| **零竞态**         | per-room`sync.Mutex` 串行化所有 action；跨房间互不阻塞         |
| **晚加入者不丢**   | WS 升级后立即推当前 snapshot（不是 Subs 残留旧帧）               |
| **业务逻辑可编程** | state 如何变化由 Lua 决定，Go 不硬编码（区别于 v2 只有`chat`） |
| **沙箱安全**       | io/debug/package/require 全 nil；os 只剩 time/date/difftime      |
| **进程内生命周期** | 纯内存，重启即清空（v3 不做持久化，留待 v4）                     |
| **单连接每设备**   | 同 device_id 重连关闭旧 conn（4409 replaced），避免帧分裂        |
| **慢消费者保护**   | Send 满 64 丢最老 + dropSignal；累计 5 次关 WS 4408              |

---

## 8. 常见错误案例

| #  | 错误                                          | 后果                                                          | 正确做法                                                                     |
| -- | --------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| 1  | handlers 写在 return table 里（不是顶层全局） | CreateRoom 400：`declares "on_init" but no global function` | 先定义顶层全局`on_X = function...end`，再在 return 里 `on_X = on_X` 引用 |
| 2  | `force_leave` 用 map 形式 `{d2 = true}`   | 静默不生效（类型断言失败），没人被踢                          | 用数组`{ "d2" }`，`table.insert(c.force_leave, "d2")`                    |
| 3  | 客户端`type:"action_CHAT"`（自带前缀）      | 服务端找`on_action_action_CHAT` → 422                      | 客户端发裸类型`type:"CHAT"`，让 controller 加 `action_`                  |
| 4  | WS 没先调`/join` 就直接连                   | 4400（device 未注册）                                         | 先`POST /join` 拿 ws_url，再 WS connect                                    |
| 5  | 脚本用`require("socket")` 或 `io.open`    | 运行时 nil 调用错误 → 422                                    | 沙箱禁了；改用纯 Lua + table/string/math                                     |
| 6  | 期待空 table 序列化成`[]`                   | 实际是`{}`（Lua 空 table 走 map 分支）                      | 业务层容错：读`(snap.context['messages'] as List?) ?? []`                  |
| 7  | Lua 里`c.foo.bar` 没 nil 检查               | 运行时 nil index → 422，snapshot 不变                        | `c.foo = c.foo or {}; c.foo.bar = ...`                                     |
| 8  | 期待`RoomHandle.connect()` 多次调用安全     | 早期版本会开多个 WS（已修）                                   | v3 的 RoomHandle 已加`_connected` 守卫；但调用方仍应只调一次               |
| 9  | 持有旧 snapshot 指针期待它不变                | v3 每次 ApplyAction 分配全新`*Snapshot`（不可变值语义）     | 这是对的——旧指针确实不变；新 snapshot 是新指针                             |
| 10 | 在脚本里用`os.exit()` 退出                  | nil 调用 → 422                                               | 沙箱禁了；脚本无法退出进程                                                   |

---

## 9. 关键文件索引

| 文件                                                                           | 内容                                                                                             |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------ |
| 后端`internal/relay/v3/state.go`                                             | Snapshot/Room/Subscriber/Action 类型 + sentinel errors                                           |
| 后端`internal/relay/v3/lua.go`                                               | NewSandbox + CompileScript + RunEvent + goToLua/luaToGo                                          |
| 后端`internal/relay/v3/service.go`                                           | Service 单例 + CreateRoom/ApplyAction/Join/Leave + broadcastSubs + ProcessForceLeave + evictIdle |
| 后端`internal/relay/v3/transport.go`                                         | HandleWS + writer/reader loop + 5s grace + 单连接 + 慢消费者 4408                                |
| 后端`internal/controller/relay/v3/relay.go`                                  | 4 个 HTTP handler + httpStatusFor 错误码映射                                                     |
| 后端`api/relay/v3/relay.go`                                                  | DTO（CreateRoomReq/Res, ActionReq/Res 等）+ api 包镜像 Snapshot 类型                             |
| 后端`internal/cmd/cmd.go`                                                    | `/api/v3` group + `/ws3/{code}` 路由注册                                                     |
| 后端`docs/relay-v3-script-format.md`                                         | Lua 脚本完整格式规范（多个示例）                                                                 |
| 后端`docs/relay-v3-api.md`                                                   | HTTP/WS 接口参考                                                                                 |
| 后端`docs/superpowers/specs/2026-07-25-relay-v3-lua-state-machine-design.md` | 设计 spec（决策锚点 + 架构总览）                                                                 |
| 前端`lib/core/net_engine/relay_v3/relay_v3_transport.dart`                   | RelayV3Transport + RoomHandle + Snapshot/HistoryEntry                                            |
| 前端`lib/core/net_engine/relay_v3/relay_v3_widget.dart`                      | RelayV3Widget lobby（建房表单）                                                                  |
| 前端`lib/core/net_p2p/pages/net_p2p_snapshot_chat.dart`                      | v3 快照聊天页（RoomHandle 驱动）                                                                 |
| 前端`lib/core/net_p2p/net_p2p_discovery_host.dart`                           | LAN/Relay 入口 +`_defaultChatScript` 内联                                                      |

---

## 10. v3 vs v2 vs v1 对照

| 维度           | v1 (action 流) | v2 (snapshot)                   | v3 (Lua 状态机)               |
| -------------- | -------------- | ------------------------------- | ----------------------------- |
| 服务端业务逻辑 | 无（透传）     | 硬编码`chat` + `lastAction` | **客户端上传 Lua 定义** |
| 状态所有权     | 客户端各自维护 | 服务端 snapshot                 | 服务端 snapshot（Lua 计算）   |
| 晚加入者       | 丢事件         | 第一帧 snapshot                 | 第一帧 snapshot               |
| 扩展新业务     | 改前端         | **改后端 Go 代码**        | **只改 Lua 脚本**       |
| 多租户         | ❌             | ❌                              | ✅（每房间独立脚本）          |
| 适用           | LAN 局域网     | 单一固定业务（聊天）            | 多场景、可编程、需服务端权威  |
| 当前状态       | LAN 保留       | **已删除**（被 v3 取代）  | 推荐                          |
