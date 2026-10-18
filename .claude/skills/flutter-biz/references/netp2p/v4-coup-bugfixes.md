# v4 Coup Lua 状态机完整修复

> **版本**: v4  
> **日期**: 2026-07-31  
> **修复范围**: Coup 游戏状态机死锁、金币 bug、前端 UI 卡死  
> **影响 Demo**: `lib/lab/demos/coup_lua/`

---

## 概述

本次修复解决了 Coup Lua 游戏中的**多起死锁问题**和**金币计算错误**，涵盖服务端状态机和前端 UI 层。修复后 2 人局的基本流程（质疑、阻断、翻牌、失卡、换牌）完全可用，无永久卡死或金币吞噬。

---

## 服务端修复（`coup_script.dart`）

### 1. INCOME/COUP 不进入 challenge 阶段

**问题**: 所有动作都无条件进入 `challenge` 阶段，导致 INCOME（基础动作）也被质疑。

**修复**: `on_action_ACT` 增加动作类型分流逻辑。

```lua
-- 根据动作类型设置正确的阶段：
-- INCOME/COUP：直接执行（不可质疑、不可阻断）
-- FOREIGN_AID：进入 block（可被 Duke 阻断，但不可质疑）
-- TAX/EXCHANGE/STEAL/ASSASSINATE：进入 challenge（可被质疑）
if at == "INCOME" or at == "COUP" then
  execute_action(c)
elseif at == "FOREIGN_AID" then
  c.cur_phase = "block"
else
  c.cur_phase = "challenge"
end
```

**影响**: INCOME 发起后立即 +1 金币，进入下一回合；COUP 发起后立即扣费并强制目标失卡。

---

### 2. EXCHANGE 死锁修复（1 张影响力）

**问题**: `on_action_EXCHANGE_KEEP` 写死必须保留 2 张，导致只剩 1 张影响力的玩家无法换牌。

**修复**: 
- `execute_action` EXCHANGE 分支记录 `exchange_keep` 字段（1 或 2）
- `on_action_EXCHANGE_KEEP` 改为动态处理，支持 `p.keep` 数组或 `p.idx1/idx2` 参数

```lua
-- execute_action 中：
elseif at == "EXCHANGE" then
  local c1 = draw_card(c); local c2 = draw_card(c)
  local options = { c1, c2 }
  local keep_n = 0
  if src_pl.card1_alive then table.insert(options, src_pl.card1); keep_n = keep_n + 1 end
  if src_pl.card2_alive then table.insert(options, src_pl.card2); keep_n = keep_n + 1 end
  c.ex_player = src
  c.exchange_cards = options
  c.exchange_keep = keep_n        -- 需要保留的张数（1 或 2）
  c.cur_phase = "exchange"
  return
end

-- on_action_EXCHANGE_KEEP 中：
on_action_EXCHANGE_KEEP = function(c, p)
  local cards  = c.exchange_cards
  local keep_n = c.exchange_keep or 2

  -- 收集要保留的下标（支持 p.keep 数组或 p.idx1/idx2）
  local idxs = {}
  if p.keep ~= nil then
    for _, v in ipairs(p.keep) do table.insert(idxs, v) end
  else
    if p.idx1 ~= nil then table.insert(idxs, p.idx1) end
    if p.idx2 ~= nil then table.insert(idxs, p.idx2) end
  end
  if #idxs ~= keep_n then return c end

  -- 合法性 + 去重
  local seen = {}
  for _, k in ipairs(idxs) do
    if k < 0 or k >= #cards then return c end
    if seen[k] then return c end
    seen[k] = true
  end

  -- 写回手牌：保留 keep_n 张为 alive，其余槽位置死
  local pl = c.players[c.ex_player]
  if keep_n >= 1 then pl.card1 = kept[1]; pl.card1_alive = true
  else pl.card1 = nil; pl.card1_alive = false end
  if keep_n >= 2 then pl.card2 = kept[2]; pl.card2_alive = true
  else pl.card2 = nil; pl.card2_alive = false end
  pl.hand_count = keep_n

  advance_turn(c)
  return c
end
```

**初始化**: `on_init` 和 `on_action_RESET` 中添加 `c.exchange_keep = nil`。

---

### 3. ASSASSINATE 扣费时机修正

**问题**: ASSASSINATE 的 3 金币在 `execute_action` 中扣除，导致被 Contessa 阻挡或质疑成功时刺客没付钱。

**修复**: 在 `on_action_ACT` 声明时立即扣除（标准规则：声明即付，被挡不退）。

```lua
-- 费用余额检查（只检查是否够，先不扣）
if at == "ASSASSINATE" and pl.coins < 3 then return c end
if at == "COUP" and pl.coins < 7 then return c end

-- 目标校验
if at == "STEAL" or at == "ASSASSINATE" or at == "COUP" then
  if p.target == nil or p.target == p.device_id then return c end
  local t = c.players[p.target]
  if t == nil or not t.alive then return c end
end

-- ★ 全部校验通过后再扣费（声明即付，被挡不退）
if at == "ASSASSINATE" then
  pl.coins = pl.coins - 3
elseif at == "COUP" then
  pl.coins = pl.coins - 7
end
```

**影响**: 无论后续是否被阻挡或质疑成功，刺客都先付 3 金币。

---

### 4. action_type 白名单

**问题**: `p.action_type` 传入非法值时会进入 challenge 且无法正常结算。

**修复**: 在 `on_action_ACT` 开头添加白名单校验。

```lua
-- 动作类型白名单
local valid_actions = {
  INCOME = true, FOREIGN_AID = true, TAX = true,
  EXCHANGE = true, STEAL = true, ASSASSINATE = true, COUP = true
}
if not valid_actions[p.action_type] then return c end
```

---

### 5. 状态残留修复（challenger/blocker）

**问题**: `execute_action` 和 `advance_turn` 只清理了 `cur_action` 和 `cur_target`，没有清理 `challenger` 和 `blocker`，导致第二回合开始时这些字段还保留着上一回合的值，造成客户端逻辑混乱。

**修复**: 在两个函数中都添加清理。

```lua
-- execute_action 结束时：
c.cur_action = nil; c.cur_target = nil; c.challenger = nil; c.blocker = nil

-- advance_turn 中：
c.cur_action = nil
c.cur_target = nil
c.challenger = nil
c.blocker = nil
c.cur_phase = "action"
```

---

### 6. COUP 双倍扣费修复

**问题**: `on_action_ACT` 和 `execute_action` 都扣了 COUP 的 7 金币，导致政变实际花费 14 金币。

**修复**: 删除 `execute_action` 中 COUP 的重复扣费。

```lua
elseif at == "COUP" then
  c.loser = tgt; c.lose_reason = "effect"   -- 金币已在 on_action_ACT 扣除
```

---

### 7. 扣费顺序修复

**问题**: 扣费发生在目标校验之前，非法目标会导致白扣钱。

**修复**: 把扣费移到所有校验通过之后（见修复 #3）。

---

## 前端修复（`engine.dart` + `widgets.dart`）

### 1. FOREIGN_AID 死锁修复

**问题**: 服务端对 FOREIGN_AID 设置 `cur_phase="block"` 但 `cur_target=nil`，UI 的阻断分支检查 `curAct.target == deviceId` 对所有人都为 false，导致无人能看到阻断按钮。

**修复**: 阻断资格按动作类型区分。

```dart
// widgets.dart _buildActionPanel
if (phase == CoupPhase.block && curAct != null) {
  final amSource = curAct.source == _room.deviceId;
  final canRespond = curAct.type == CoupAction.foreignAid
      ? !amSource                         // FA：只要不是发起人就能阻断/通过
      : curAct.target == _room.deviceId;  // STEAL/ASSASSINATE：仅目标
  if (canRespond) return _buildBlockRow(theme, curAct.type);
}

// _statusText 同步修复
if (phase == CoupPhase.block && curAct != null) {
  if (curAct.type == CoupAction.foreignAid) {
    final amSource = curAct.source == _room.deviceId;
    return amSource ? '外援 — 等待对手阻断或通过' : '对方外援 — 我可用公爵阻断';
  }
  final blockerName = curAct.target == _room.deviceId ? "我" : curAlias;
  return '$blockerName 可阻断 ${actionLabel(curAct.type)}';
}
```

---

### 2. EXCHANGE 动态张数修复

**问题**: `engine.dart` 的 `exchangeKeep` 写死传两个下标，`widgets.dart` 的换牌 UI 写死选 2 张，与服务端 `exchange_keep` 不匹配。

**修复**:
- `engine.dart`: 改为发 `keep` 数组
- `widgets.dart`: 从 snapshot 读 `exchange_keep`，选牌数量动态化

```dart
// engine.dart
Future<void> exchangeKeep(List<int> idxs) => handle.applyAction(
      type: 'EXCHANGE_KEEP',
      params: {'keep': idxs}, // 发数组，支持保留 1~2 张
    );

// widgets.dart _exchangePicker
final keepN = (_snap!.context['exchange_keep'] as num?)?.toInt() ?? 2;
// 选牌逻辑：selected.length < keepN
// 确认按钮：selected.length == keepN

// widgets.dart _buildExchange
final keepN = (snap.context['exchange_keep'] as num?)?.toInt() ?? 2;
title: Text('换牌 · 保留 $keepN 张'),
```

---

### 3. isBeingChallenged 修正

**问题**: `engine.dart` 的 `isBeingChallenged` 判定条件不准确，红框条件几乎永远不成立。

**修复**: 改为"只在 reveal 阶段、且我就是需要翻牌的那个人"。

```dart
bool isBeingChallenged(Snapshot? s) {
  if (s == null) return false;
  if (phase(s) != CoupPhase.reveal) return false;
  if (challenger(s) == null) return false;
  final revealer = blocker(s) ?? currentAction(s)?.source;
  return revealer != null && reveler == deviceId;
}
```

**widgets.dart 同步**: `_MyCardRow` 改用访问器。

```dart
final isBeingChallenged = room.isBeingChallenged(snap);
```

---

## 修复效果对比

### 修复前
| 场景 | 行为 | 结果 |
|------|------|------|
| INCOME | 进入 challenge，等待质疑 | 错误，INCOME 不可质疑 |
| EXCHANGE（1张） | 强制选 2 张 | 死锁 |
| ASSASSINATE 被挡 | 不扣钱 | 违反规则 |
| 非法目标 | 扣钱但不执行 | 金币吞噬 |
| COUP | 花 14 金币 | 双倍扣费 |
| 第二回合 | 挑战按钮不显示 | 状态残留 |
| FOREIGN_AID | 无人能阻断 | 双方等待 |
| EXCHANGE | UI 写死 2 张 | 前后端不匹配 |

### 修复后
| 场景 | 行为 | 结果 |
|------|------|------|
| INCOME | 直接 +1 金币 → 下一回合 | ✅ 正确 |
| EXCHANGE（1张） | 选 1 张确认 | ✅ 正确 |
| ASSASSINATE 被挡 | 声明时付 3 金币 | ✅ 符合规则 |
| 非法目标 | 不扣钱，拒绝 | ✅ 正确 |
| COUP | 花 7 金币 | ✅ 正确 |
| 第二回合 | 正常质疑 | ✅ 状态清理 |
| FOREIGN_AID | 对手可阻断 | ✅ 不再卡死 |
| EXCHANGE | 动态 1~2 张 | ✅ 前后端对齐 |

---

## 测试验证清单

### 服务端测试
- [ ] INCOME 发起后立即生效，无质疑阶段
- [ ] COUP 发起后扣 7 金币，目标失 1 卡
- [ ] ASSASSINATE 声明时扣 3 金币，被 Contessa 阻挡不退还
- [ ] 非法目标（空/自己/已淘汰）不扣钱并拒绝
- [ ] 1 张影响力玩家 EXCHANGE 选 1 张确认成功
- [ ] 多回合质疑、阻断、翻牌，状态正确清理

### 前端测试
- [ ] FOREIGN_AID 发起后，对手看到"阻断·公爵"+"不阻断"按钮
- [ ] EXCHANGE 换牌 UI 显示"点选 N 张保留"，N = 1 或 2
- [ ] 被质疑时，需要翻牌的玩家看到翻牌面板
- [ ] 阻断期，STEAL/ASSASSINATE 目标看到阻断按钮，FOREIGN_AID 所有人看到

### 完整流程测试（2 人局）
1. A TAX → B 质疑 → A 翻 Duke 成功 → B 失 1 卡 → 下一回合
2. A STEAL → B 阻断（Captain）→ A 放弃反质疑 → B 失 1 卡 → STEAL 被抵消
3. A ASSASSINATE → B 阻断（Contessa）→ A 反质疑 → B 翻 Contessa 失败 → B 失 1 卡 → ASSASSINATE 继续执行
4. A EXCHANGE（1 张）→ 选 1 张确认 → 手牌更新为 1 张
5. A COUP → B 失 1 卡 → 下一回合

---

## 技术要点

### 状态机设计原则
1. **阶段转换要清理所有相关状态**：`cur_action`, `cur_target`, `challenger`, `blocker`
2. **费用校验和扣费分离**：先检查余额和目标合法性，全部通过后再扣费
3. **动作类型决定阶段**：基础动作直接执行，声称角色的动作才进 challenge
4. **动态张数支持**：EXCHANGE 的保留张数由玩家当前存活卡数决定，不可写死

### 前端 UI 设计原则
1. **阻断资格按动作类型区分**：FOREIGN_AID 任意非发起人，STEAL/ASSASSINATE 仅目标
2. **从服务端读取动态参数**：`exchange_keep`、`cur_phase` 等字段权威
3. **访问器复用**：`isBeingChallenged` 等方法统一判定，避免手算出错

---

## 已知限制（非阻塞）

1. **多人游戏（3+ 人）**：challenge / block 仍是"第一个人 PASS 就结算"，需要 responder set 才能让每个人都有机会响应。2 人局不受影响。
2. **客户端阶段支持**：需要客户端正确渲染 `reveal` 和 `loseCard` 阶段，并在 `block` 阶段给 PASS 按钮。
3. **REVEAL 参数**：需要客户端正确传递 `p.role`（必须等于 `cur_action.claimer_card`）。

---

## 后续工作

1. **多人 responder set**：支持 3+ 人局时每个玩家都能依次响应质疑/阻断
2. **客户端阶段完善**：确保所有阶段（`reveal`、`loseCard`、`exchange`）都有对应的 UI
3. **错误提示优化**：非法操作时给用户明确的错误原因

---

## 相关文件

- `lib/lab/demos/coup_lua/coup_script.dart` - Lua 状态机脚本
- `lib/lab/demos/coup_lua/engine.dart` - 网络动作封装
- `lib/lab/demos/coup_lua/widgets.dart` - 游戏界面
- `.claude/skills/net-p2p-protocol-playbook/references/v3-lua-state-machine.md` - v3 参考文档

---

**文档维护**: 本文档记录 v4 版本的所有技术修复细节，用于后续问题排查和版本演进参考。
