# server-authoritative-client-state — 客户端不能自查角色/状态，须用服务端权威字段

> 从 surround_game_lua（围追堵截互联网双人对战）反复出现的一类 bug 沉淀：
> 客户端"自查"角色或判定终局，导致双方客户端对同一事实判断不一致 → 看起来正常的 UI 实际有错。

> 适用于 **所有用 v3 Lua 状态机的互联网房间业务**（不限于游戏）——任何"我是什么""现在是什么状态"的事实判定。

---

## 0. 核心原则（一句话）

**"我是谁""我们到哪一步了""谁赢了""谁房主" 这类事实，客户端不能自查。**

要么用服务端存的权威字段（snapshot.context['xxx']），要么由**单方客户端推算 + 服务端校验 + 广播**。绝不能用客户端自我命名（deviceId 前缀、URL 参数、SharedPreferences 缓存等）做角色/状态判定。

---

## 1. 反模式速查

| ❌ 客户端自查 | ✅ 服务端权威 |
|-------------|--------------|
| `deviceId.startsWith('host-')` → "我是房主" | `_snap.context['host_id']` 比对我的 deviceId |
| `deviceId.startsWith('xxx-')` → "我是 top" | `_snap.context['top_player_id']` 比对我的 deviceId |
| client 算出 `gs.status == topWin` → 显示"我赢" | 客户端算 + 发 WIN 事件，服务端记 `winner` 字段 |
| client 用 SharedPreferences 缓存"上次我是 host" | 完全不缓存，靠 snapshot 的 host_id |
| 客户端把协商好的"我走白子对方走黑子"写进 URL | 服务端在 on_init 按 join 顺序分配角色 |

---

## 2. 三类典型的"自查 bug"案例（围追堵截真实踩坑）

### ① 角色字段：用 `isHost` 推 `imTop`

```dart
// ❌ client 自查
bool get _imTop => _room.isHost;   // 是 host 所以是 top

// ✅ client 查服务端权威字段
bool get _imTop {
  final topId = SgRoom.topPlayerId(_snap);
  return _room.deviceId == topId;
}
```

**坑过的现场**：host = top 的设计假设未来如果 host 旁观/换人就不成立。即便没人换，用前缀/字符串自查也是把"协议层事实"和"代码层命名"耦合了。

---

### ② 胜利判定：Lua 没有 engine，让客户端算但权威在上报后

```lua
-- ❌ Lua 自己判胜（搬 QuoridorEngine 进来太重）
on_action_MOVE = function(c, p)
  table.insert(c.history, move)
  -- 这里不知道怎么判断走到终点
end
```

```dart
// ✅ 客户端用本地 engine 判定，**上报**给服务端
void _onSnapshot(Snapshot s) {
  if (s.state == 'playing' && _gs.status != GameStatus.running) {
    final winner = _gs.status == GameStatus.topWin ? 'top' : 'bottom';
    _room.declareWin(winner);  // 服务端校验 sender 角色与 winner 一致后记 c.winner + state=ended
  }
}
```

```lua
-- 服务端不仅记 winner 还校验：只有 top 玩家能声明 winner=top，防作弊
on_action_WIN = function(c, p)
  if state ~= "playing" then return c end
  local winner = p.winner
  local topId = c.top_player_id
  local isFromTop = (p.device_id == topId)
  if winner == "top" and not isFromTop then return c end
  if winner == "bottom" and isFromTop then return c end
  c.winner = winner
  state = "ended"
  return c
end
```

**幂等性**：双方客户端都会从同一份 snapshot 算出 `gs.status != running` 并发 WIN。但服务端 `state ~= "playing"` guard 保证只第一次写入有效，第二次静默。无需去重。

---

### ③ `isHost` 判定：deviceId 前缀 ≠ 房主

```dart
// ❌ bug：建房/加入都用 'sg-' 前缀 → 两侧都返回 true
bool get isHost => deviceId.startsWith('sg-');
```

```dart
// ✅ 用 snapshot.host_id 判定（即便前缀混用也不误判）
bool get isHost {
  final myId = handle.transport.deviceId;
  final hostId = handle.latest?.context['host_id']?.toString();
  if (hostId != null) return myId == hostId;
  return myId.startsWith('sg-host-');  // 仅 handle.latest 未到位时 fallback
}
```

**坑过的现场**：客方在 ready 阶段错误显示"开始游戏"按钮，点了 Lua 服务端拒绝（host_id 校验）但客户端无错误反馈，看起来"按钮坏了"。

---

## 3. 原则的边界澄清

不是所有客户端状态都"禁忌自查"——以下是允许的：

| 状态 | 允许 client 缓存？ | 原因 |
|------|-------------------|------|
| "我是 host/top/bottom" 角色 | ❌ | 协议层事实，必须服务端权威 |
| 房间是否到 ended、winner 是谁 | ❌ | 同上 |
| ACK 状态 | ⚠️ 可乐观，**最终以服务端为准** | 见 §4 |
| 自己的 alias、deviceId | ✅ | 客户端自我事实 |
| UI 反馈（按下/抬起/拖动中） | ✅ | 不涉及协议 |

判断标准：**这个状态会改变"谁能做什么"的逻辑吗？** 会的话，必须服务端权威。

---

## 4. 乐观更新的合法用法：ACK / 状态提交

客户端**点击立即反馈 + 服务端回包后校正**，这模式允许且常见：

```dart
Future<void> _ack() async {
  if (_ackedLocally) return;
  setState(() => _ackedLocally = true);          // ✅ 立即视觉反馈
  try {
    await _room.ack();                            // 服务端存权威
  } catch (_) {
    if (mounted) setState(() => _ackedLocally = false);  // 失败回滚
  }
}
```

**关键差异**：
- 客户端按钮变 ✓ 是**自我事实**（我点了），不属于"协议层状态判定"
- 服务端 `c.ready` 仍是权威字段，两边最终一致
- 离开当前 phase 时清除本地标志（防止误用）

---

## 5. 何时把"客户端自查"改成"服务端权威"？

如果你正在写：

- 业务判定（"我是谁""谁赢了""回合轮到谁"）→ 服务端权威
- UI 反馈（按钮是否变 ✓、是否显示加载圈）→ 客户端自查即可
- 展示性映射（"我赢了 → 显示绿色胜利图标"）→ 客户端自查，但**输入来自服务端字段**

---

## 6. 配套约定

- **服务端必然**在 `on_init` 写入 `host_id`（创建者设备 id）
- **服务端必然**按业务约定分配角色字段（如 `top_player_id`）—— 客户端只看，不篡改
- **客户端必然**在 `handle.latest` 变更（`_onSnapshot`）时同步刷新 `imTop`/`isHost` 等派生标志
- **业务事件**（MOVE/WIN/ASSIGN_ROLE 等）由客户端发起，服务端校验合法性后写权威字段并广播

---

## 7. 反直觉的"客户端能算 final 吗？"

**能，但不是用"自查"**。流程：

1. 客户端 A 算出"我赢了"（基于权威 history 重建）
2. A 发业务事件（WIN）给服务端，**附带**自己的计算结果
3. 服务端校验：A 是否真有资格声明（角色一致、防作弊）、状态变化是否合法
4. 服务端写 `c.winner` + 改 state，广播 snapshot
5. 客户端从 snapshot 读 `c.winner`，用于所有后续 UI

**关键**：客户端**发的是"声明"**，不是"决定"。服务端有最终裁决权。

---

## 8. 围追堵截踩坑时间线（"权威字段"主题）

| 轮 | bug | 错在哪 | 修法 |
|----|-----|--------|------|
| ① | "认输两方显示同样结论" | 用 `_room.isHost` 推角色 | 加 `top_player_id` 服务端字段 + `_imTop` |
| ② | "走到底无法判定胜利" | Lua 无 engine 无法自查 | 客户端算 + 发 WIN，服务端校验后记 winner |
| ③ | "客方错误显示开始按钮" | `deviceId.startsWith('sg-')` 两侧都成立 | 改用 `snapshot.host_id` 判定 |

**共同根因**：3 个都是"客户端用自我命名 / 自我判定 / 自我算法替代服务端权威字段"。

---

## 9. 与 [[role-aware-board-mirror]] 的关系

[[role-aware-board-mirror]] 是"棋盘对称镜像"特化场景（含触摸坐标、ConfirmActions、Panel 翻转等）。本 ref 是更**上游的原则**——"任何状态判定都不自查"——适用于所有 v3 房间业务。

读 [[role-aware-board-mirror]] 时也**强烈建议先读本 ref**，理解为什么要用 `top_player_id` 字段。否则会重蹈"用 `isHost` 推 `imTop`"的覆辙。

---

## 10. 速记

> 🟡 **客户端能看到的所有"身份/状态/结果"字段，问自己一句话：**
> *这个字段是服务端写的，还是我自己写的？*
> 如果是**客户端自己写自己读的**（如 `setState(() => _ackedLocally = true)`），是合法乐观更新。
> 如果是**协议层事实**（我是 host、我是 top、我赢了），必须**服务端写、客户端读**。
