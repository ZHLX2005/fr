# versus-game-room-template — 双人对战房间端到端模板（Lua 设计 + UX 交互）

> 从 surround_game_lua（围追堵截）+ gomoku_lua（五子棋）两个实现沉淀。适用于 **2 人互联网对战房间**：国际象棋、围棋、五子棋、围追堵截、井字棋、坦克对战……

> 本 ref 是**端到端落地模板**，综合调用前 4 个 ref：
> - [[server-authoritative-client-state]] — 角色/状态用服务端字段
> - [[action-permission-table]] — 按钮约束走权限表
> - [[role-aware-board-mirror]] — 棋盘对称镜像（如需）
> - [[team-card-lobby-pattern]] — 大厅/身份/就绪门（如需旁观者/身份）

> **何时读**：从 0 实现一个"2 人轮流行动、有胜负"的互联网对战游戏时，通读本篇。

---

## 0. 什么算"双人对战房间"

同时满足 4 点的业务用本模板：

1. **2 人**（房主 + 客方），无旁观者或旁观者只读
2. **轮流行动**（回合制），不是同时操作
3. **有胜负**（连五/将杀/到终点/认输），不是纯协作
4. **状态可从落子序列重建**（history 数组 → 完整局面）

不满足的看其他 ref：
- 纯聊天/白板 → 主 SKILL.md 模板
- 多人 + 身份 + 大厅 → [[team-card-lobby-pattern]]
- 协作无胜负 → 不需要本模板的胜负/回合机制

---

## 1. 六件套文件结构（方案 A）

每个对战游戏一套，放 `lib/lab/demos/<game>_lua/`：

```
lib/lab/demos/<game>_lua/
├── constants.dart        — AliasPrefs + relayUrl + 棋盘常量
├── <game>_script.dart    — Lua 脚本（状态机 + action_permissions）
├── engine.dart           — Room 封装 + 状态读取 + canPerform + 胜负判定
├── board.dart            — 棋盘 widget（可选，复杂棋盘单独文件）
└── widgets.dart          — SetupPage / JoinPage / OnlineGamePage

lib/lab/demos/<game>_lua_demo.dart  — DemoPage 入口 + 注册
lib/lab/lab_bootstrap.dart          — 加 registerXxxLuaDemo()
```

> 行数红线（flutter-work-flow）：单文件 >400 行必须拆。widgets.dart 通常最大（lobby/ready/playing/finished 四阶段 + 交互），可考虑把棋盘交互拆到 board.dart。

---

## 2. Lua 设计模板

### 2.1 状态机（lobby → ready → playing → ended）

```
CreateRoom → lobby      房主等客方加入
ACK × 2    → ready      双方都点了"准备好了"
DEAL(host) → playing    游戏开始（房主 = 先手）
MOVE       → 不变       追加一步到 history
RESIGN     → ended      认输（对手赢）
WIN        → ended      胜利方声明（记录 winner）
RESET(host)→ lobby      再来一局
```

### 2.2 context 字段（服务端唯一真相）

```lua
c.host_id            -- 房主 device_id
c.<role>_player_id   -- ★角色字段：先手方的 device_id（见 §2.4 命名）
c.players            -- {did: alias}
c.ready              -- {did: true}
c.history            -- ★落子序列（唯一棋盘状态，客户端重建）
c.winner             -- "A"|"B"|nil（终局）
c.action_permissions -- ★权限表（见 §2.3）
```

### 2.3 action_permissions 表（按钮约束单点真相）

```lua
c.action_permissions = {
  ACK    = "any",                -- 大厅双方都能点
  DEAL   = "host",               -- 房主发牌
  MOVE   = "current_player",     -- 当前回合方
  RESIGN = "any",                -- 任一方都能认输
  WIN    = "non_current_player", -- ★刚下完那步的人（事后事件！）
  RESET  = "host",               -- 房主重新开始
}
```

> 🔴 **WIN 必须用 `non_current_player`**（不是 current_player）。这是第三次踩的坑——见 [[action-permission-table]] §5。错用会导致服务端静默拒绝 → 客户端死循环重发 → 闪屏。

### 2.4 角色字段命名（按游戏语义）

| 游戏 | 先手方字段 | 含义 |
|------|----------|------|
| 围追堵截 | `top_player_id` | top = 视觉上方（涉及镜像） |
| 五子棋 | `black_player_id` | 黑先手（无镜像，纯颜色） |
| 国际象棋 | `white_player_id` | 白先手 |

命名跟着游戏惯例走。客户端用它推 `imRole`（我是哪方）。

### 2.5 role_check helper（4 种规则）

```lua
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    -- 由 history 最后一步推导：空 → 先手；否则与最后一步反方
    ...（见各 demo 实现）
  end
  if rule == "non_current_player" then
    -- 刚下完最后一步的人（WIN/UNDO_REQUEST 用）
    ...
  end
  return false
end
```

完整实现照搬围追堵截/五子棋，只改 `isBlack`/`isTopPlayer` 字段名。

---

## 3. UX 交互设计（四阶段）

### 3.1 lobby 阶段（等待 + 准备）

| 元素 | 交互 |
|------|------|
| 房间码 | 大号显示（6 位，letterSpacing 6） |
| 玩家列表 | 圆环头像 + ✓/person 图标 + trailing "已准备 ✓/未准备" |
| ACK 按钮 | **乐观更新**：点了立即变"已准备 ✓" + disabled，不等服务端回包（`_ackedLocally` 标志） |
| 离开 lobby | 清 `_ackedLocally`（防跨阶段残留） |

> 见 [[server-authoritative-client-state]] §4 乐观更新合法用法。

#### 双人对战的自动准备（推荐）

当房间已经出现第 2 位玩家时，双方客户端可以自动发送一次 `ACK`，直接进入
`ready`（服务端仍是唯一真相）。这样“加入房间”完成后即进入对战准备态，
不要求加入者再点击一次“准备好了”。UI 只保留状态反馈：

- 未满 2 人：显示“等待对手加入…”；
- 满 2 人且 ACK 请求中：显示“正在准备…”；
- 服务端进入 `ready`：房主显示“开始游戏”，客方显示“等待房主开始…”；
- ACK 网络失败：恢复手动“准备好了”按钮，并允许重试。

实现要点：

```dart
void maybeAutoAck(Snapshot s) {
  if (autoAckSent || autoAckFailed) return;
  if (s.state != 'lobby' || players(s).length < 2) return;
  if (readyMap(s)[myDeviceId] == true) {
    autoAckSent = true;
    return;
  }
  autoAckSent = true;
  ack().catchError((_) {
    autoAckSent = false;
    autoAckFailed = true;
    // UI 恢复手动 ACK
  });
}
```

> 自动准备是 UX 层优化，不绕过服务端权限；RESET 回到新 lobby 时必须清除
> `autoAckSent/autoAckFailed`，避免下一局无法自动准备。对五子棋、井字棋等
> 双人房间适用；需要玩家选择身份/阵营的业务不要默认套用。

### 3.2 ready 阶段（双方已准备）

- 房主：显示"开始游戏"按钮（`_canPerform('DEAL')`）
- 客方：显示"等待房主开始…"文字（**不显示 disabled 按钮**，避免"看着可点"误导）

### 3.3 playing 阶段（对战中）

**核心三件套**：

1. **回合状态条**（顶部）："轮到你（黑方）落子 / 等待白方落子…" + 我方颜色标识
2. **棋盘 + 落子交互**（见 §4 游戏特化）
3. **底部操作栏**：认输 / 重新开始（host）/ 退出，全走 `_canPerform(action)`

**落子必须确认**（两步）：
- 点击/拖动 → `_pending` 待确认状态（半透明预览）
- 确认按钮 → 发 MOVE；取消 → 清 pending
- **回合切换自动清 pending**（防跨回合残留）

> 五子棋曾因"点击直接落"被用户要求改回确认——落错不可逆，必须有确认。

### 3.4 ended 阶段（终局）

- 胜负消息**角色感知**："我方获胜！/ 对方获胜"（用 `imRole == winner` 推，不用"上方/下方"）
- 半透明遮罩 + 棋盘背景（保留终局棋面）
- 房主："再来一局"按钮；客方："等待房主开始下一局…"文字

---

## 4. 游戏特化部分（不可复用，每个游戏自己写）

| 部分 | 围追堵截 | 五子棋 |
|------|---------|--------|
| 棋盘 | 9x9 格子 + 墙 | 15x15 网格线 + 交点 |
| 落子 | 移动棋子 + 放墙（拖动 + 确认） | 交点落子（点击 + 确认） |
| 镜像 | host `Transform.flip`（top=视觉底） | **无镜像**（对称棋盘） |
| 胜负 | 走到对方底线（QuoridorEngine） | 连五（hasFiveInRow） |
| 角色 | top/bottom | 黑/白 |

**镜像判断标准**：棋盘有"终点方向"（如围追堵截 host 要走到对方底线）→ 需镜像；纯对称（五子棋/围棋）→ 不镜像。详见 [[role-aware-board-mirror]]。

---

## 5. 胜负判定模式（客户端算 + 服务端记）

Lua 没有游戏引擎，无法自行判胜。模式：

1. 客户端从权威 history 重建局面
2. 本地引擎判定（走到终点 / 连五 / 将杀）
3. 命中 → 发 `WIN(winner)`，服务端校验角色 + 记 `c.winner` + `state=ended`
4. **客户端 `_winDeclared` 防死循环**（发过一次不再重发，RESET 时重置）

```dart
void _maybeDeclareWin() {
  if (_winDeclared) return;              // ★防死循环
  if (_snap?.state != 'playing') return;
  if (!_engine.hasWin(_board)) return;
  _winDeclared = true;                    // ★发之前置 true
  _room.declareWin(winner);
}
```

> 双方客户端都检测，**幂等**（state 已 ended 时 Lua 忽略第二个 WIN）。

---

## 6. widget 抽象边界（未来抽组件指南）

当出现 **第 3 个**对战游戏时，可抽以下组件（共性 >90%）：

### ✅ 可抽

| 组件 | 职责 | 参数 |
|------|------|------|
| `RoomSetupPage` | 建房表单 | relayUrl, script, title, deviceIdPrefix, aliasPrefsKey, onCreated |
| `RoomJoinPage` | 加入表单 | 同上 + onJoined |
| `RoomLobbyView` | 房间码 + 玩家 + ACK | code, players, readyMap, myId, onAck |
| `RoomReadyWaitView` | 等待/开始游戏 | isHost, onDeal |
| `RoomFinishedOverlay` | 胜负 + 再来一局 | winner, imRole, isHost, onReset, boardChild |
| `RoomBottomActionBar` | 认输/重开/退出 | canResign, canReset, onResign, onReset, onLeave |

### ❌ 不抽（游戏特有）

- 棋盘 widget（格子 vs 交点 vs 六边形……）
- 落子交互（拖动 vs 点击 vs 选中+目标）
- 引擎（每个游戏规则不同）
- Lua 脚本

### 抽象形态：`VersusRoomShell`

```dart
VersusRoomShell(
  room: room,
  boardBuilder: (context) => MyGameBoard(...),  // 棋盘作为 child
  onLeave: onLeave,
)
```

外壳处理 lobby/ready/finished + 底部栏 + canPerform；棋盘 + 落子交互由各游戏实现。

> ⚠️ **现在（2026-07，2 个 demo）不抽**。YAGNI——等第 3 个游戏共性完全明确再抽，避免过早抽象耦合两个 demo 的演进。

---

## 7. 从 0 实现新对战游戏 checklist

1. **constants.dart**：AliasPrefs + relayUrl + 棋盘常量（尺寸/获胜条件）
2. **<game>_script.dart**：复制五子棋 Lua，改：
   - 角色字段名（`black_player_id` → 你的）
   - MOVE 的 move 结构（落子坐标字段）
   - role_check 里的颜色字段名
3. **engine.dart**：复制五子棋 engine，改：
   - 角色判定（imBlack → imRole）
   - 胜负判定函数（hasFiveInRow → 你的规则）
   - rebuildBoard（你的棋盘重建）
4. **board.dart**：写你的棋盘 widget（网格/格子/六边形）
5. **widgets.dart**：复制五子棋 widgets，改：
   - 棋盘渲染调用
   - 落子交互（点击/拖动 + 确认）
   - 镜像（如需，见 [[role-aware-board-mirror]]）
   - 文案/颜色
6. **<game>_lua_demo.dart**：入口 + SegmentedButton
7. **lab_bootstrap.dart**：注册
8. **测试**：flutter analyze 0 error + 手动联调（建房→加入→ACK→开始→对弈→胜负→再来）

---

## 8. 反模式速查

| ❌ 错误 | 后果 | ✅ 正确 |
|--------|------|---------|
| 点击直接落子（无确认） | 落错不可逆 | 两步：pending + 确认按钮 |
| WIN 用 `current_player` | 服务端拒绝→闪屏/卡死 | `non_current_player` |
| 客方显示 disabled"开始"按钮 | "看着可点"误导 | 改占位文字 |
| 终局消息用"上方/下方" | host 镜像后语义错 | 用 `imRole == winner` |
| 客户端自查角色（deviceId 前缀） | 前缀撞车误判 | 服务端 `<role>_player_id` |
| 第 2 个游戏就抽 widget 组件 | 过早抽象耦合演进 | 先沉淀 skill，第 3 个再抽 |
| `_maybeDeclareWin` 不防循环 | WIN 被拒→重发风暴 | `_winDeclared` 标志 |
| 棋盘存二维数组到服务端 | 冗余 + 不一致 | 只存 history，棋盘客户端重建 |
| `AliasPrefs.load()` 异步覆盖输入 | 用户改的昵称被旧值冲掉，"名字没生效" | controller 默认空，load 仅在 `text.isEmpty` 时填 |

### SetupPage 别名加载 race（所有房间表单通用）

**症状**：建房/加入表单输入昵称 → 进入房间后显示的是上次的旧昵称，"名字没生效"。

**根因**：`AliasPrefs.load()` 是异步的（SharedPreferences），常见写法在 `initState`
里 `.then((v) => setState(() => _aliasCtrl.text = v))`。用户在 load 返回前已手动输入，
回调一到就把用户输入覆盖回历史保存值（默认值也会被 `save(t.alias)` 存进去，下次 load
就是这个旧值）。

**修法**（gomoku/tetris 的 SetupPage/JoinPage 通用）：
```dart
final _aliasCtrl = TextEditingController();            // 默认空，配 hintText
TetrisAliasPrefs.load().then((v) {
  // 只在用户还没输入时填历史值，杜绝覆盖
  if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
    setState(() => _aliasCtrl.text = v);
  }
});
```
排查捷径：alias 是否进 `c.players` 用 `.tool/relay-v3-simulator` 的 Python 脚本
（`create(device, alias)` 后看 `snapshot.context.players`）一验便知——后端正常就是这场 race。

---

## 9. 与其他 ref 的协作（读这篇前/后读什么）

| 阶段 | 先读 |
|------|------|
| 任何 v3 房间（必读） | [[server-authoritative-client-state]] |
| 设计按钮约束 | [[action-permission-table]]（★ WIN 用 non_current_player） |
| 棋盘有方向/需镜像 | [[role-aware-board-mirror]] |
| 要旁观者/身份/双区 | [[team-card-lobby-pattern]] |
| **端到端落地** | **本 ref**（综合调用以上） |
