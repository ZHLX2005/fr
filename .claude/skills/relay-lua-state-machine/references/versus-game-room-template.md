# versus-game-room-template — 双人对战房间端到端模板

> 从五子棋（gomoku_lua）的当前实现沉淀。**五子棋 = 本 skill 的标准案例**。
> 适用 2 人互联网对战：象棋、围棋、五子棋、围追堵截、井字棋、坦克对战……

> 本 ref 是**端到端落地模板**，综合调用前 4 个 ref：
> - [[server-authoritative-client-state]] — 角色/状态用服务端字段
> - [[action-permission-table]] — 按钮约束走权限表
> - [[role-aware-board-mirror]] — 棋盘对称镜像（如需）
> - [[team-card-lobby-pattern]] — 大厅/身份/就绪门（如需旁观者/身份）
> - [[social-room-code-pattern]] — **社交房间号 + 单表单入口**（本模板前置）

> **何时读**：从 0 实现一个"2 人轮流行动、有胜负"的互联网对战游戏时通读。

---

## 0. 什么算"双人对战房间"

同时满足 4 点用本模板：

1. **2 人**（先到者=房主/黑方，后到者=白方），无旁观者或旁观者只读
2. **轮流行动**（回合制），不是同时操作
3. **有胜负**（连五/将杀/到终点/认输），不是纯协作
4. **状态可从落子序列重建**（history 数组 → 完整局面）

不满足的看其他 ref：
- 纯聊天/白板 → 主 SKILL.md 模板
- 多人 + 身份 + 大厅 → [[team-card-lobby-pattern]]
- 协作无胜负 → 不需要本模板的胜负/回合机制

---

## 1. 六件套文件结构（五子棋标准案例）

放 `lib/lab/demos/<game>_lua/`：

```
lib/lab/demos/<game>_lua/
├── constants.dart        — AliasPrefs + relayUrl + 棋盘常量
├── <game>_script.dart    — Lua 脚本（状态机 + action_permissions + max_players）
├── engine.dart           — Room 封装 + 状态读取 + canPerform + 胜负判定
├── board.dart            — 棋盘 widget（可选，复杂棋盘单独文件）
└── widgets.dart          — LobbyEntryPage / OnlineGamePage
                           （不再有 SetupPage/JoinPage 二选一）

lib/lab/demos/<game>_lua_demo.dart  — DemoPage 入口 + 卡片化主页
lib/lab/lab_bootstrap.dart          — 加 registerXxxLuaDemo()
```

> 五子棋当前实现符合本结构，直接参照 `lib/lab/demos/gomoku_lua/` 抄。

---

## 2. Lua 设计模板

### 2.1 状态机（lobby → ready → playing → ended）

```
tryJoinOrCreate → lobby      404 时用相同 code 建房；先到=host=黑方
ACK × 2         → ready      双方都点了"准备好了"，卡片保持不动，仅按钮切换
DEAL (host)     → playing    房主点"开始游戏 ▸"，客方看到"等待房主开始…"
MOVE            → 不变       追加一步到 history
RESIGN          → ended      认输（对手赢）
WIN             → ended      胜利方声明（记录 winner）
RESET(host)     → lobby      房主"再来一局"
```

> 🟢 **`ready` 是同一张卡片的按钮状态，不是一张新页面**。
> 五子棋标准做法：`lobby` / `ready` 复用同一个 `_buildLobby`，仅底部按钮原地在「未 ACK / 已 ACK 等对手 / 双方已就绪」三态切换。**禁止**为 `ready` 另起一张卡片——那会让用户点完"准备好了"以后看到明显的页面切换/缩放，视觉抖动、体验断裂。见 §3.2、§9 反模式。

### 2.2 context 字段（服务端唯一真相）

```lua
c.host_id            -- 房主 device_id（= 第 1 个进入 = 黑方先手）
c.black_player_id    -- = host_id（客户端用它推"我是黑/白"）
c.players            -- {did: alias}
c.ready              -- {did: true}
c.history            -- ★落子序列（唯一棋盘状态，客户端重建）
c.winner             -- "black"|"white"|nil（终局）
c.max_players        -- ★人数上限（Lua 业务责任，需在 on_init 注入）
c.action_permissions -- ★权限表（见 §2.3）
```

### 2.3 action_permissions 表（按钮约束单点真相）

```lua
c.action_permissions = {
  ACK    = "any",                -- 双方都能点
  DEAL   = "host",               -- 房主开始（可选阶段）
  MOVE   = "current_player",     -- 当前回合方
  RESIGN = "any",                -- 任一方都能认输
  WIN    = "non_current_player", -- ★刚下完那步的人（事后事件！）
  RESET  = "host",               -- 房主重新开始
}
```

> 🔴 **WIN 必须用 `non_current_player`**（不是 current_player）。这是第三次踩的坑——见 [[action-permission-table]] §5。错用会导致服务端静默拒绝 → 客户端死循环重发 → 闪屏。

### 2.4 max_players 校验（Lua 责任，服务端不管）

服务端 `Join` **完全没有 max_players 校验**——业务规则由 Lua 通过 `rejected_join` 字段兜底。见 [[social-room-code-pattern]]。

```lua
on_init = function(c, p)
  c.max_players = p.max_players or 2   -- ★注入到 context
  -- ... 其他初始化
end

on_join = function(c, p)
  if c.players[p.device_id] ~= nil then return c end  -- 幂等
  local count = 0
  for _ in pairs(c.players) do count = count + 1 end
  if count >= c.max_players then
    c.rejected_join = c.rejected_join or {}
    c.rejected_join[p.device_id] = true   -- 服务端返 409
    return c
  end
  c.players[p.device_id] = p.alias
  c.ready[p.device_id] = nil
  return c
end
```

### 2.5 角色字段命名（按游戏语义）

| 游戏 | 先手方字段 | 含义 |
|------|----------|------|
| 五子棋 | `black_player_id` | 黑先手（无镜像，纯颜色） |
| 围追堵截 | `top_player_id` | top = 视觉上方（涉及镜像） |
| 国际象棋 | `white_player_id` | 白先手 |

命名跟着游戏惯例走。客户端用它推 `imRole`（我是哪方）。

### 2.6 role_check helper

```lua
function role_check(c, p, action)
  local rule = c.action_permissions[action]
  if rule == nil or rule == "any" then return true end
  if not c.players[p.device_id] then return false end
  if rule == "host" then return p.device_id == c.host_id end
  if rule == "current_player" then
    -- 由 history 最后一步推导：空 → 先手；否则与最后一步反方
    ...
  end
  if rule == "non_current_player" then
    -- 刚下完最后一步的人（WIN/UNDO_REQUEST 用）
    ...
  end
  return false
end
```

完整实现照搬五子棋，只改 `black_player_id` 字段名。

---

## 3. UX 交互标准（五子棋案例）

### 3.1 入口（LobbyEntryPage — 单表单智能匹配）

**核心原则**：不再有"建房 vs 加入"二选一。用户输入昵称 + 房间号 + 一个按钮，服务端决定角色。

```
┌──────────────────────────────┐
│  ┌────────────────────────┐  │  ← 圆角 20px 卡片 + 微阴影
│  │       五子棋            │  │  ← Hero 大标题居中
│  │        ━━              │  │  ← 短分割线
│  │   [自动匹配对战]       │  │  ← chip 副标签
│  │                        │  │
│  │  昵称   [黑方       ]  │  │  ← 圆角浅底输入框
│  │  房间号 [4-6位大写  ]  │  │
│  │                        │  │
│  │  ◐ 输入同一号码即可对战│  │  ← 浅灰提示块
│  │                        │  │
│  │  [   进入对局   ]      │  │  ← 黑色实底主按钮
│  └────────────────────────┘  │
│                              │
│         开局学习              │  ← 卡片外次要入口
└──────────────────────────────┘
```

**Flutter 关键代码**：

```dart
// widgets.dart — LobbyEntryPage
Future<void> _go() async {
  final alias = _aliasCtrl.text.trim();
  final code = _codeCtrl.text.trim().toUpperCase();
  if (code.length < 4 || code.length > 6) {
    setState(() => _error = '房间码为 4–6 位大写字母数字');
    return;
  }
  final t = RelayV3Transport(
    relayUrl: kGomokuRelayUrl,
    alias: alias,
    deviceId: 'gm-${DateTime.now().microsecondsSinceEpoch}',
  );
  final h = await t.tryJoinOrCreate(
    code: code,
    script: kGomokuScript,
    initialParams: {'device_id': t.deviceId, 'alias': alias},
    maxPlayers: 2,
  );
  widget.onJoined(h);
}
```

**错误提示区分**（两种 409）：

```dart
final body = e.body.toLowerCase();
if (e.statusCode == 409 && body.contains('code collision')) {
  msg = '房间号 $code 已被占用，请换一个';
} else if (e.statusCode == 409 && body.contains('join rejected')) {
  msg = '房间 $code 已满员，无法加入';
}
```

> 见 [[social-room-code-pattern]] 完整细节。

### 3.2 lobby / ready 阶段（同一张卡片，按钮三态原地切换）

> ★ **五子棋标准案例**：`lobby` 和 `ready` 复用同一个 `_buildLobby(theme)`，Scaffold / Container / padding / players 头像列表都不变。仅**标题文案**跟着 phase 变（`等待对手` → `双方已就绪`），**底部按钮区**原地在三态间切换。**不要**为 `ready` 起一张新页面。

**同一张卡片，phase 只驱动局部**：

```
lobby（未 ACK）           lobby（我已 ACK）         ready（双方 ACK）
┌────────────────┐        ┌────────────────┐        ┌────────────────┐
│    等待对手    │        │    等待对手    │        │  双方已就绪    │  ← 标题文案切换
│      ━━        │        │      ━━        │        │      ━━        │
│    ┌────┐      │        │    ┌────┐      │        │    ┌────┐      │
│    │GAME│      │        │    │GAME│      │        │    │GAME│      │  ← 房间号 chip 不动
│    └────┘      │        │    └────┘      │        │    └────┘      │
│                │        │                │        │                │
│ ⃝ 黑方(我)未准备│        │ ✓ 黑方(我)已准备│       │ ✓ 黑方(我)已准备│  ← 圆环头像状态映射 ACK
│ ⃝ 白方   未准备│        │ ⃝ 白方   未准备│        │ ✓ 白方    已准备│
│                │        │                │        │                │
│ ┌────────────┐│        │ ┌────────────┐│        │ ┌────────────┐│
│ │ 准备好了   ││   →    │ │  已准备 ✓  ││   →    │ │ 开始游戏 ▸ ││  ← 房主
│ └────────────┘│        │ └────────────┘│        │ └────────────┘│  或
│ 绿色 border    │        │ 灰实底 disabled│       │  等待房主开始…│  ← 客方（纯文本，同高度）
└────────────────┘        └────────────────┘        └────────────────┘
```

**按钮三态映射**（Dart 伪码）：

```dart
final bothReady = phase == 'ready';
final iAmReady = bothReady || _ackedLocally || (readyMap[myId] == true);
final canDeal = _canPerform('DEAL');   // 房主专属，服务端权威

// 按钮区高度固定 48px，避免出现/消失导致卡片 resize
child: bothReady
    ? (canDeal
        ? '开始游戏 ▸'     // 房主：黑色实底
        : '等待房主开始…') // 客方：浅灰文本占位（同高度）
    : (iAmReady
        ? '已准备 ✓'       // 我方已 ACK：灰实底 disabled
        : '准备好了');     // 未 ACK：绿色 border-emphasis
```

**核心元素**：

| 元素 | 视觉规则 |
|---|---|
| 卡片容器 | `lobby` / `ready` 共用，Container 圆角 20 + 1px 边框 + 微阴影，phase 变化时**位置/尺寸完全不动** |
| 标题文案 | `等待对手`（lobby）→ `双方已就绪`（ready），仅文字变，字号/字距/位置不变 |
| 房间号 chip | 胶囊样式（圆角 30），24px 粗体 + letterSpacing 8 + tabular figures |
| 圆环头像 | 未准备=空心 1.6px 灰描边+首字母；已准备=实心 2.4px 绿描边+打勾 |
| 状态徽章 | 胶囊样式，11px 字 + letter-spacing 1 |
| 底部按钮区 | **固定高度 48px**，三态原地切换，禁止 `if (...)` 让按钮消失撑动卡片 |
| ACK 按钮 | 未 ACK = 绿色 border-emphasis（浅绿底 + 绿描边 + 绿字）；已 ACK = 灰实底 disabled |
| DEAL 按钮 | 房主：`FilledButton` 黑实底 + `开始游戏 ▸`；客方：`Text('等待房主开始…')` 居中 |
| 乐观更新 | 点了立即变"已准备 ✓" + disabled（`_ackedLocally` 标志） |

> `_ackedLocally` 见 [[server-authoritative-client-state]] §4 乐观更新合法用法。

**Flutter 落地关键点**：

```dart
@override
Widget build(BuildContext context) {
  final phase = _snap?.state;
  // ★ lobby / ready 共用同一 build 分支，避免 Scaffold 级切换动画
  if (phase == null || phase == 'lobby' || phase == 'ready') {
    return _buildLobby(theme);
  }
  if (phase == 'ended') return _buildFinished(theme);
  return _buildPlaying(theme);
}
```

参照 `lib/lab/demos/gomoku_lua/widgets.dart` 的 `_buildLobby`。

### 3.3 playing 阶段（对战中）

**核心三件套**（不变）：

1. **回合状态条**（顶部）：`轮到你（黑方）落子` / `等待白方落子…` + 我方颜色标识
2. **棋盘 + 落子交互**（见 §4 游戏特化）
3. **底部操作栏**：认输 / 重新开始（host）/ 退出，全走 `_canPerform(action)`

**落子必须确认**（两步）：
- 点击/拖动 → `_pending` 待确认状态（半透明预览）
- 确认按钮 → 发 MOVE；取消 → 清 pending
- **回合切换自动清 pending**（防跨回合残留）

> 五子棋曾因"点击直接落"被用户要求改回确认——落错不可逆，必须有确认。

### 3.4 ended 阶段（终局）

- 胜负消息**角色感知**：`我方获胜！` / `对方获胜`（用 `imRole == winner` 推，不用"上方/下方"）
- 半透明遮罩 + 棋盘背景（保留终局棋面）
- 房主：`再来一局` 按钮；客方：`等待房主开始下一局…` 文字

---

## 4. 游戏特化部分（不可复用，每个游戏自己写）

| 部分 | 五子棋 | 围追堵截 |
|------|-------|----------|
| 棋盘 | 15x15 网格线 + 交点 | 9x9 格子 + 墙 |
| 落子 | 交点点击 + 确认 | 移动棋子 + 放墙（拖动 + 确认） |
| 镜像 | **无镜像**（对称棋盘） | host `Transform.flip`（top=视觉底） |
| 胜负 | 连五（hasFiveInRow） | 走到对方底线（QuoridorEngine） |
| 角色 | 黑/白 | top/bottom |

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

## 6. UI 视觉标准（五子棋案例作为参考）

### 6.1 卡片容器（现代卡片化）

所有房间阶段（lobby / ready / ended）都用统一的圆角卡片容器：

```dart
Container(
  decoration: BoxDecoration(
    color: theme.panelBg,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: theme.panelBorder),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.06),
        blurRadius: 16,
        offset: const Offset(0, 4),
      ),
    ],
  ),
  padding: const EdgeInsets.fromLTRB(28, 28, 28, 28),
  child: /* ... */,
)
```

**约束**：`maxWidth: 440` 居中，配合 `SafeArea + SingleChildScrollView`。

### 6.2 主按钮：border-emphasis + 实底

- **未激活/未 ACK**：`OutlinedButton` 带 1.6px 主题描边 + 浅色底（**border-emphasis 风格**）
- **已激活/已完成**：`FilledButton` 灰色/主题实底 + disabled
- **主要动作**（进入对局 / 开始游戏 / 再来一局）：`FilledButton` 黑色实底 + 圆角 10px

配色决策见 [[server-authoritative-client-state]] §颜色决策；border-emphasis 规范见 styles-skill 的 `border-emphasis-style`。

### 6.3 状态徽章 + 圆环头像

- 用胶囊 chip（`BorderRadius.circular(20)`）承载状态文字
- 头像用 `Icon(Icons.check_rounded)` + 圆形容器切换 ready/未 ready

具体代码参考 `gomoku_lua/widgets.dart` 的 `_ReadyAvatar`（`_CheckCircle` 已废弃：新标准 `lobby` / `ready` 共用同一张卡片，无双勾中间页）。

---

## 7. widget 抽象边界（第 3 个游戏出现时再抽）

当出现 **第 3 个**对战游戏时，可抽以下组件（共性 >90%）：

### ✅ 可抽

| 组件 | 职责 | 参数 |
|------|------|------|
| `LobbyEntryPage` | 单表单智能匹配 | relayUrl, script, deviceIdPrefix, aliasPrefsKey, onJoined |
| `RoomLobbyView` | 房间号 chip + 圆环头像列表 + **三态按钮区（准备好了 / 已准备 / 开始游戏 / 等待房主）** | code, players, readyMap, myId, phase, isHost, canDeal, onAck, onDeal |
| `RoomFinishedOverlay` | 胜负 + 再来一局 | winner, imRole, isHost, onReset, boardChild |
| `RoomBottomActionBar` | 认输/重开/退出 | canResign, canReset, onResign, onReset, onLeave |
| `_ReadyAvatar` | ACK 圆环头像视觉小组件 | name, isReady, color |

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

> ⚠️ **五子棋 + 围追堵截共 2 个 demo 时不抽**。YAGNI——等第 3 个游戏共性完全明确再抽。

---

## 8. 从 0 实现新对战游戏 checklist

1. **constants.dart**：AliasPrefs + relayUrl + 棋盘常量（尺寸/获胜条件）
2. **<game>_script.dart**：复制五子棋 Lua，改：
   - 角色字段名（`black_player_id` → 你的）
   - MOVE 的 move 结构（落子坐标字段）
   - role_check 里的颜色字段名
   - **max_players 注入 + on_join 人数校验**（见 §2.4）
3. **engine.dart**：复制五子棋 engine，改：
   - 角色判定（imBlack → imRole）
   - 胜负判定函数（hasFiveInRow → 你的规则）
   - rebuildBoard（你的棋盘重建）
4. **board.dart**：写你的棋盘 widget（网格/格子/六边形）
5. **widgets.dart**：复制五子棋 widgets，改：
   - **保留 LobbyEntryPage 结构**（tryJoinOrCreate + 单表单）
   - **保留 lobby/ready 同一张卡片 + 底部按钮三态原地切换**（★ 见 §3.2）
   - **禁止**为 `ready` 起独立 build 分支或独立 Scaffold
   - 棋盘渲染调用
   - 落子交互（点击/拖动 + 确认）
   - 镜像（如需，见 [[role-aware-board-mirror]]）
   - 文案/颜色
6. **<game>_lua_demo.dart**：入口 + 卡片化主页（复制五子棋 `_EntryCard` 结构）
7. **lab_bootstrap.dart**：注册
8. **测试**：
   - `flutter analyze` 0 error
   - 手动联调：两端同时输入房间号 → 先到=房主 → ACK×2 → 对弈 → 胜负 → 再来
   - 后端场景测试：`.tool/relay-room-tester` 跑 `test_rooms.py`

---

## 9. 反模式速查

| ❌ 错误 | 后果 | ✅ 正确 |
|--------|------|---------|
| 保留"建房 / 加入"二选一 SegmentedButton | 增加决策成本，用户"我到底是建还是加"卡住 | 单表单 + tryJoinOrCreate，服务端决定角色 |
| Lua `on_join` 不设 `rejected_join` | 第 3 人进 3 人局（服务端无校验） | 在 Lua 里做 `count >= c.max_players` 校验 |
| 客户端 409 都提示"已被占用" | 用户不知道是号被占还是房间满 | 按 message 关键词区分（`code collision` vs `join rejected`） |
| 点击直接落子（无确认） | 落错不可逆 | 两步：pending + 确认按钮 |
| WIN 用 `current_player` | 服务端拒绝→闪屏/卡死 | `non_current_player` |
| lobby 一律用 disabled"开始"按钮 | "看着可点"误导 | 房主 = 实底按钮；客方 = 占位文字 |
| 终局消息用"上方/下方" | host 镜像后语义错 | 用 `imRole == winner` |
| 客户端自查角色（deviceId 前缀） | 前缀撞车误判 | 服务端 `<role>_player_id` |
| 第 2 个游戏就抽 widget 组件 | 过早抽象耦合演进 | 先沉淀 skill，第 3 个再抽 |
| `_maybeDeclareWin` 不防循环 | WIN 被拒→重发风暴 | `_winDeclared` 标志 |
| 棋盘存二维数组到服务端 | 冗余 + 不一致 | 只存 history，棋盘客户端重建 |
| `AliasPrefs.load()` 异步覆盖输入 | 用户改的昵称被旧值冲掉 | controller 默认空，load 仅在 `text.isEmpty` 时填 |
| `ready` 阶段用**独立 Scaffold / 独立 build 分支** | 用户点"准备好了"瞬间整页切换：卡片缩放、位置漂移、圆环头像/房间号闪一下——观感断裂 | `lobby` / `ready` 共用同一个 `_buildLobby`，phase 只驱动**标题文案 + 底部按钮**，卡片和头像列表位置完全不动 |
| ACK 按钮和 DEAL 按钮**高度不一致**或 `if (canDeal) SizedBox(...)` 让按钮消失 | 按钮区高度变化 → 撑动上方内容 → 卡片抖动、视觉重排 | 按钮区固定 48px 高度；非房主用同高度 `Text('等待房主开始…')` 占位，不用 `Visibility` 去掉 |
| lobby 页面纯白背景无卡片 | 页面空旷、"demo 形态" | 卡片化容器（圆角 20px + 1px 边框 + 微阴影） |
| ACK 按钮用 `Colors.green.shade400` 直接填充 | 视觉过重、色彩碰撞 | border-emphasis：浅绿底 + 绿描边 + 绿字 |
| 房间号显示 6 位数字不带 letterSpacing | 数字挤在一起难读 | letterSpacing 8 + tabular figures |

### SetupPage 别名加载 race（历史问题，新方案已解决）

**症状**：五子棋 v1 用两个页面（SetupPage / JoinPage）分别加载 `AliasPrefs`，用户输入的昵称被 load 回来的旧值覆盖。

**根因**：`AliasPrefs.load()` 是异步的（SharedPreferences），旧写法在 `initState` 里 `.then((v) => setState(() => _aliasCtrl.text = v))`。

**新方案（LobbyEntryPage 已修）**：controller 默认空 + `text.isEmpty` 时才填。

```dart
final _aliasCtrl = TextEditingController();  // 默认空
GomokuAliasPrefs.load().then((v) {
  if (mounted && v.isNotEmpty && _aliasCtrl.text.isEmpty) {
    setState(() => _aliasCtrl.text = v);
  }
});
```

---

## 10. 与其他 ref 的协作

| 阶段 | 先读 |
|------|------|
| 任何 v3 房间（必读） | [[server-authoritative-client-state]] |
| 设计按钮约束 | [[action-permission-table]]（★ WIN 用 non_current_player） |
| 棋盘有方向/需镜像 | [[role-aware-board-mirror]] |
| 要旁观者/身份/双区 | [[team-card-lobby-pattern]] |
| 单表单 + tryJoinOrCreate + 409 撞号提示 | [[social-room-code-pattern]] |
| **端到端落地** | **本 ref**（综合调用以上） |

---

## 11. 参照实现

**五子棋 = 本模板标准案例**。所有新对战游戏都应从这里抄，不要从围追堵截或其他历史实现抄。

- 文件：`lib/lab/demos/gomoku_lua/`
- Demo 入口：`lib/lab/demos/gomoku_lua_demo.dart`
- Lua 脚本：`lib/lab/demos/gomoku_lua/gomoku_script.dart`
- 端到端测试：`.tool/relay-room-tester/scripts/test_rooms.py`

---

### [2026-07-26] key_board_3 操作教训

| 错误操作 | 实际后果 | 正确做法 |
|---------|---------|---------|
| 初版把"lobby → ready"设计成两张独立 Scaffold（`_buildLobby` / `_buildReadyWait`） | 用户点完"准备好了"→ Scaffold 整页切换 → 卡片肉眼可见地缩放/漂移、圆环头像和房间号闪一下 | 一张 `_buildLobby` 卡片承担 lobby + ready 两个 phase，phase 只驱动**标题文案 + 底部按钮**，容器/头像列表位置完全不动 |
| 底部按钮用 `if (canDeal) SizedBox(...) else Text(...)` 让按钮消失 | 按钮区高度变化 → 上方内容被撑动 → 卡片抖动 | 按钮区固定 48px 高度；非房主用同高度 `Text('等待房主开始…')` 占位 |
| 前一版反模式表写"ready 阶段留一个额外的开始游戏按钮 = 错误" | 让新读者以为 ready 阶段必须删掉，但真正的问题是"另起页面"而不是"多一步" | 反模式改为"`ready` 阶段用独立 Scaffold / 独立 build 分支"；ready 保留，但同页三态 |
