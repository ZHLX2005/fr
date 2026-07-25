# action-permission-table — "谁能做哪个 action"收敛到服务端单一表

> ⚠️ **这是成熟期优化，前期开发不推荐。** 当 action 少（≤3-4 个）、业务规则还在频繁变时，简单的 `if (isHost)` 特判更直接、迭代更快。表驱动是"约束散落导致 bug"的解药，不是开局就该上的基础设施。**何时引入见 §1。**

> 从 surround_game_lua（围追堵截）反复出现"客方显示无效按钮"UX bug 沉淀。适用于 **action 类型多、规则趋于稳定的成熟业务**：当你发现客户端按钮可点性靠散落特判（`if (isHost)` / `if (isMyTurn)`）维护、且开始出现"无效按钮"类 bug 时，就读这个 ref。

> 是 [[server-authoritative-client-state]] 的姊妹篇：那篇讲"**为什么**角色不能自查"，本篇讲"**怎么做**"——把 action 约束做成服务端表 + 客户端单点消费的完整落地模式。

---

## 0. 一句话

**"按钮谁能点"的真相在服务端 `c.action_permissions` 一张表里。客户端只读这张表 + 自己角色判定，零特判代码。**

---

## 1. ★ 何时引入 / 何时不该用（必读）

### ❌ 前期开发不要用

| 场景 | 为什么不该用 |
|------|-------------|
| action 类型 ≤3-4 个 | 一两处 `if (isHost)` 特判直接、易读，表驱动反而绕 |
| 业务规则每周都在变 | 改表 + 改 role_check + 改 canPerform 三处，比改一处特判慢 |
| 原型 / demo / hackathon | 速度优先，约束散落暂时无害 |
| 没有安全顾虑（内部工具） | 不需要"防绕过 UI"双保险 |

**过早抽象的代价**：写完权限表发现规则不对，又要拆掉重来；或业务方向变了，表里一堆废弃规则。YAGNI。

### ✅ 该引入的信号

当你**第二次**遇到以下任一情况，就该考虑引入：

1. **第二次写** `if (isHost) showButton() else showText()` —— 特判开始散落
2. **第一次出现**"客方显示无效按钮"UX bug —— 约束和服务端校验已经不一致
3. **action 类型 ≥5 个** —— 特判散落成本超过表驱动成本
4. **业务规则稳定 ≥2 周** —— 表不会频繁返工
5. **有黑客单独构造 HTTP 请求绕过 UI 的风险** —— 需要服务端权威校验

### 渐进式引入

不必一次到位：
- **第一阶段**：客户端继续特判，但**服务端 handler 加 `role_check`**（只防安全，不动 UX）
- **第二阶段**：UX bug 出现后，再把客户端特判换成 `canPerform`

---

## 2. 反模式：客户端按钮特判散落

```dart
// ❌ 每个按钮位置写一次特判
if (_room.isHost)
  ElevatedButton(onPressed: _deal, child: Text('开始游戏'))
else
  Text('等待房主开始…');

if (_room.isHost)
  ElevatedButton(onPressed: _reset, child: Text('再来一局'))
else
  Text('等待房主开始下一局…');

if (isRunning && _isMyTurn)
  TouchView(...);
```

**问题**：
- 约束散落客户端 N 处，加新按钮 = 加一处特判
- 服务端 handler 也有一份校验（`if c.host_id ~= p.device_id`），**两份真相**
- 改规则要改两处，容易漏 → "客方显示开始游戏但点了无响应" 这类 bug

---

## 3. 正模式：服务端表 + role_check + canPerform

### ① Lua on_init 写权限表（单点真相）

```lua
on_init = function(c, p)
  ...
  c.action_permissions = {
    ACK              = "any",                -- 任何人
    DEAL             = "host",               -- 房主
    MOVE             = "current_player",     -- 当前回合方
    RESIGN           = "any",
    WIN              = "current_player",
    RESET            = "host",
    UNDO_REQUEST     = "non_current_player", -- 刚下完一步的责任方
    UNDO_RESPONSE    = "non_requester",      -- 不是悔棋请求方
  }
  ...
end
```

### ② Lua role_check helper（handler 统一校验）

```lua
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    if #c.history == 0 then return p.device_id == c.top_player_id end
    local last = c.history[#c.history]
    local isTopTurn = not last.isTopPlayer
    return (isTopTurn and p.device_id == c.top_player_id)
        or (not isTopTurn and p.device_id ~= c.top_player_id)
  end
  if rule == "non_current_player" then
    if #c.history == 0 then return false end
    local last = c.history[#c.history]
    local wasTop = last.isTopPlayer
    return (wasTop and p.device_id == c.top_player_id)
        or (not wasTop and p.device_id ~= c.top_player_id)
  end
  if rule == "non_requester" then
    return c.undo_pending ~= nil and p.device_id ~= c.undo_pending.requester
  end
  return false
end

on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end   -- ★ 顶部一行
  if state ~= "ready" then return c end                -- 状态校验保留
  state = "playing"
  return c
end
```

### ③ Dart canPerform 单点入口（客户端只消费）

```dart
// engine.dart
static bool canPerform(
  String action,
  Snapshot? snap, {
  required bool isHost,
  required bool isMyTurn,
  bool isUndoRequester = false,
  bool justMovedByMe = false,
}) {
  final rule = actionPermissions(snap)[action];
  if (rule == null || rule == 'any') return true;
  if (rule == 'host') return isHost;
  if (rule == 'current_player') return isMyTurn;
  if (rule == 'non_current_player') return justMovedByMe;
  if (rule == 'non_requester') return !isUndoRequester;
  return false;
}

// widgets.dart — 便捷包装
bool _canPerform(String action) => SgRoom.canPerform(
  action, _snap,
  isHost: _room.isHost,
  isMyTurn: _isMyTurn,
  isUndoRequester: _room.deviceId == SgRoom.undoRequester(_snap),
  justMovedByMe: !_isMyTurn && SgRoom.canRequestUndo(_snap, _gs, _room.deviceId),
);
```

### ④ 所有按钮走它

```dart
if (_canPerform('DEAL'))   ElevatedButton(onPressed: _deal, ...)
else                       Text('等待房主开始…');

if (_canPerform('RESET'))  ElevatedButton(onPressed: _reset, ...)
else                       Text('等待房主开始下一局…');

final canMountTouch = _snap?.state == 'playing' && _canPerform('MOVE');
```

---

## 4. 5 种角色规则速查

| 规则 | 含义 | 典型 action |
|------|------|------------|
| `any` | 任何在场玩家 | ACK / RESIGN / CHAT |
| `host` | 房主（`p == c.host_id`） | DEAL / RESET / 开始游戏 |
| `current_player` | 当前回合方（事前：轮到谁行动） | MOVE / 出牌 |
| `non_current_player` | 刚下完一步的人（**事后：已轮到对手**） | UNDO_REQUEST（悔棋请求）/ **WIN（胜利声明）** |
| `non_requester` | 不是某请求的发起方 | UNDO_RESPONSE（悔棋裁决） |
| `host` | 房主 | DEAL / RESET |

**新增规则**：在 `role_check` 加一个 `if rule == "xxx"` 分支 + Dart `canPerform` 对应分支。一次性，全局复用。

---

## 5. 关键洞察：为什么 `non_current_player` ≠ `current_player`

**核心规律：行动 = 事前，事件 = 事后。**

| 类型 | 时机 | 用谁？ |
|------|------|-------|
| **行动**（MOVE/出牌/落子） | 事前：轮到你要做 | `current_player`（当下轮到的人） |
| **事后事件**（UN/WIN/UNDO_REQUEST） | 事后：已轮到对手 | `non_current_player`（刚下完的人） |

这是**反直觉的**——刚下完的人**不是**当前回合方（已切到对手）。任何"事后事件"（悔棋、声明胜利、申诉等）都用 `non_current_player`，因为发起这些事件的人在事件触发时已经"不是当前回合方"。

```
示例（悔棋）：
host 走第一步 → 轮到 guest → host 是"刚下完" → host 能请求悔棋
                ↑ current_player=guest     ↑ non_current_player=host

示例（胜利声明）：
white 走第 5 步连五 → 轮到 black → white 是"刚下完" → white 能声明 WIN(white)
                       ↑ current_player=black    ↑ non_current_player=white
```

### ⚠️ 错用 `current_player` 的灾难

如果把 WIN/UNDO_REQUEST 用 `current_player`：
1. **服务端静默拒绝**（return c 不报错，客户端无感知）
2. 客户端继续触发 → 反复发 action → 反复被拒 → **setState 风暴 → 闪屏/卡死**
3. UI 看似走棋继续，但其实"胜利/悔棋从未生效"——直到**非预期方**（current_player）走到那步误打误撞触发才能补救

**这是真实踩过的坑**：五子棋白方连五后本应立即判定 WIN(white)，但因规则错用 `current_player`，服务端一直拒绝 → 客户端死循环重发 → 闪屏。围追堵截走到终点的同 bug 隐藏了（走到终点场景少触发）。

### 5.1 客户端防死循环（必须做）

服务端拒绝 `role_check` 失败时**仍是静默 return c**，客户端无错误反馈。因此客户端 `_maybeDeclareWin` / `_requestUndo` 这种"主动发 action"的方法**必须**加本地标志防重发：

```dart
bool _winDeclared = false;  // 配套 _winRequested 等

void _maybeDeclareWin() {
  if (_winDeclared) return;  // ★ 已声明过，不重发
  if (_snap?.state != 'playing') return;
  ...
  _winDeclared = true;  // ★ 发之前置 true
  _room.declareWin(winner);
}
```

并在 RESET/新局时重置。

---

## 7. 服务端 handler 还要不要保留状态校验？

**要**。`role_check` 只校验"角色权限"，不校验"状态合法性"：

```lua
on_action_DEAL = function(c, p)
  if not role_check(c, p, "DEAL") then return c end  -- 角色权限
  if state ~= "ready" then return c end               -- 状态合法性（保留）
  state = "playing"
  return c
end
```

两层校验各司其职：
- `role_check` — **谁**能发这个 action（防越权）
- 状态校验 — **什么时候**能发（防时序错乱，如 playing 中再 DEAL）

---

## 8. 客户端 canPerform 与服务端 role_check 的关系

**镜像同一张表，但用途不同**：

| 层 | 用途 | 失败时 |
|----|------|--------|
| 客户端 `canPerform` | 决定**按钮是否显示/可点**（UX） | 按钮不显示，用户根本发不出去 |
| 服务端 `role_check` | 决定**action 是否被接受**（安全） | 静默 `return c`（防绕过 UI 直发请求） |

两者**都必须有**：
- 只有客户端 → 黑客绕过 UI 直发 HTTP，服务端无防护
- 只有服务端 → 用户看到"无效按钮"点了没反应（UX 灾难）

---

## 9. 测试策略（verify_lua_drivers.py）

每个权限规则至少一个测试 case：

```python
def test_action_permissions():
    # 客方 DEAL 在 ready 状态 → role_check 拒绝 → state 不变
    snap = c.action("DEAL", "guest")
    assert snap["state"] == "ready"   # 没变成 playing

    # 非当前回合方 MOVE → 拒绝 → history 不增长
    snap = c.action("MOVE", "host", {...})
    assert len(snap["context"]["history"]) == 1   # 没加

    # 客方 RESET → 拒绝
    snap = c.action("RESET", "guest")
    assert snap["state"] == "playing"
```

**注意**：测试流程要符合状态机时序。如"接受悔棋后 history 空 → 轮回先手"，后续 MOVE 必须由先手发，否则 test 自己的逻辑是错的（实施时踩过）。

---

## 10. 迁移步骤（从特判重构到表驱动）

1. **Lua**：`on_init` 加 `c.action_permissions` 表，列出所有 action 的规则
2. **Lua**：加 `role_check(c, p, action)` helper，覆盖所有规则
3. **Lua**：每个 `on_action_*` 顶部加 `if not role_check(...) then return c end`
4. **Dart**：`SgRoom.actionPermissions(snap)` + `SgRoom.canPerform(action, snap, ...)`
5. **Dart**：widgets 加 `_canPerform(action)` 便捷包装
6. **Dart**：所有按钮 `if (_canPerform('X'))` 替换原特判
7. **测试**：每个规则一个拒绝 case + 一个接受 case

---

## 11. 反模式速查

| ❌ 错误 | 后果 | ✅ 正确 |
|--------|------|---------|
| 客户端 `if (isHost)` 散落各处 | 加按钮 = 加特判，易漏 | `_canPerform('X')` 走服务端表 |
| 服务端 handler 不校验角色 | 黑客绕过 UI 直发 | 顶部 `role_check` |
| 只客户端校验，服务端不校验 | 无安全防护 | 两层都要 |
| `UNDO_REQUEST` 用 `current_player` | 该等对方的人能悔棋 | `non_current_player` |
| `role_check` 替代状态校验 | playing 中能再 DEAL | 两者各司其职都保留 |
| 权限规则写死在 Dart 代码 | 改规则要发版 | Lua 表里改，snapshot 推给客户端 |

---

## 12. 收益清单

- ✅ **加新 action 零客户端改动**：Lua 加一行权限规则 + handler 校验，客户端 `canPerform('NEW')` 自动生效
- ✅ **"无效按钮"UX bug 从根上消除**：按钮可点性真相在服务端 snapshot
- ✅ **安全 + UX 双保险**：服务端防绕过，客户端防误导
- ✅ **权限规则可视化**：一张表看清谁能做什么，新人 onboarding 快

---

## 13. 与其他 ref 的协作

| 场景 | 先读 |
|------|------|
| 任何 v3 房间业务（必读） | [[server-authoritative-client-state]] — 为什么角色不能自查 |
| 有按钮/操作约束 | **本 ref** — 怎么把约束做成表 |
| 对称对战棋盘 | [[role-aware-board-mirror]] — 视觉翻转（按钮 isTopTurn 等） |
| 大厅/身份/就绪门 | [[team-card-lobby-pattern]] — ACK/SIT 等也是 action，同样适用本表 |
