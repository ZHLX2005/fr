---
name: Ca04-Lua房间契约检查表
description: FR Relay-v3 Lua 房间脚本与客户端调用的契约检查表——元函数必须项、state 全局变量、action 命名、device_id 注入、特殊返回值与「HTTP 200 但快照不变」排查。写/改任何 v3 Lua 房间业务前过本表。
---

# Ca04 — Lua 房间契约检查表

> C 序列索引：[[C00-RelayLua路由]]。写/改任何 v3 Lua 房间脚本前过 §2/§4；原则层（角色/状态不许客户端自查）见 [[Ca01-服务端权威状态]]；双人对战端到端模板见 [[Cb01-双人对战房间模板]]。
>
> 何时读：新建 v3 房间业务、改 Lua handler、写线下 e2e 探针、或遇到「请求成功但快照不变」时。

## 1. 模型 30 秒

**后端是通用 Lua 解释器 + 状态广播器**：上传 Lua → `gopher-lua` 编译缓存 → 客户端 `ApplyAction` 触发 `on_action_<X>` → Lua 改 `context`/`state` → 服务端全量推 snapshot → 客户端只渲染、零合并。改业务 = 加一个 `on_action_<X>` + 在 `definition.functions` 声明，Go 代码零改动。

| 类型 | 函数 | 触发 | 自定义 |
|---|---|---|---|
| 元函数（3 个，必须实现） | `on_init` / `on_join` / `on_leave` | CreateRoom / Join·重连 grace / Leave·断线·踢人·TTL | 只需保证初始化必要结构；不处理的留空函数即可 |
| 自定义（N 个） | `on_action_<TYPE>` | 客户端 `ApplyAction(type:"X")` | 完全自定义 |

## 2. 服务端脚本检查表（写脚本时逐行过）

- [ ] 元函数三件套齐全：`on_init` 必须 `c.players = {}` 等结构初始化（哪怕空表）、设 `state` 初值；不处理的 `on_join`/`on_leave` 留空函数即可
- [ ] **handler 先顶层全局定义，再在 `return {}` 表里引用**——匿名直接写进表 = compile 失败（CreateRoom 400 / no global function of that name）
- [ ] action 命名无前缀：客户端 `type:"CHAT"` → 服务端查 `on_action_CHAT`；发 `type:"action_CHAT"` = 查 `on_action_action_CHAT` → 422 unknown event
- [ ] **改阶段必须改全局 `state`**：只设 `c.started = true` 不写 `state = "playing"`，客户端永远收不到阶段变化（snapshot 顶层 `state` = Lua 全局变量，不是 `context.state`）
- [ ] 阶段读法约定：`snap.state` = 阶段码（lobby/playing/ended…）；业务数据在 `snap.context['x']`。快照唯一真相、零合并
- [ ] 特殊返回值拼写：踢人 `context.force_leave = {"device_id"}`（**数组**，写 map 静默失效）；拒绝加入 `context.rejected_join = {[id]=true}`（map）
- [ ] `max_players`：Go 后端 CreateRoom 必须把它注入 `initial_params`（漏注入 → Lua `p.max_players` 恒 nil → fallback 8）；满员校验由 Lua 在 `on_join` 做 `count >= c.max_players` + `rejected_join`（见上条）
- [ ] Dart 字符串嵌 Lua：注释避免 `--[=[ ]=]` 类长括号（parse error）

## 3. device_id 注入契约（2026-10-20 relay e2e 实测定案）

- 服务端**不注入**：action 的 `params` 原样透传，请求里的 `source_device_id` 不会自动合并进 `params`
- 客户端 `RoomHandle.applyAction` 先注入 `device_id` 再合并业务参数（`lib/core/net_engine/relay_v3/relay_v3_transport.dart`）；**当前合并顺序允许业务参数覆盖 `device_id`**，且该字段是客户端输入而非服务端身份证明——Lua 权限判断只应视作客户端自报身份；跨设备信任/防伪需服务端按已验证连接身份校验（待服务端来源）
- **线下探针（Python / curl）必须手动补 `params.device_id`**：

  ```python
  json={"type": "ACK",
        "params": {"device_id": device, **params},
        "source_device_id": device}
  ```

- 失败模式极其隐蔽：params 缺 `device_id` → `c.ready[p.device_id] = true` 因 `table index is nil` 抛错 → **HTTP 200 但快照原封不动**；`c.players[p.device_id]` 读 nil 更是直接静默跳过，准备门永远打不开

## 4. 客户端义务检查表

- [ ] CreateRoom 路径**必须先 join 自己**（后端 CreateRoom 自动 join；没注册就裸连 WS = 4400 `device not registered`）
- [ ] 状态还原只 `handle.snapshots.listen` **全量替换**；`subscribe(topic)` + 合并流会顺序错乱、晚加入丢消息
- [ ] JSON 数字用 `(v as num).toInt()` / `int.tryParse()` 兼容；`as int?` 直接 cast 遇 double 返回 null（静默丢字段）
- [ ] handle 释放权归入口页：lobby `dispose()` 不调 `handle.dispose()`，转移给 caller（提前关 = 后续页面 `Bad state`）
- [ ] 探针补 `params.device_id`（§3）

## 5. 验证出口

1. `flutter analyze` 0 error
2. 后端场景测试：`.tool/relay-room-tester/emoji_e2e.dart`；传输层 `test/core/net_engine/relay_v3_transport_test.dart`
3. 「HTTP 200 但快照不变」三步排查：① handler 是否漏 `return c`；② `params.device_id` 缺失/被覆盖（§3）；③ 服务端 Lua runtime 日志。此类失败 ≠ 422，需单独排查

## 6. Flutter 调用最小骨架

```dart
final transport = RelayV3Transport(
  relayUrl: 'http://47.110.80.47:8988',
  alias: 'Alice',
  deviceId: 'unique-device-id',
);
final handle = await transport.createRoom(
  script: kMyBizScript,                    // Lua 写在 Dart r'''...''' 字符串里，改业务=改脚本字符串
  initialParams: {'device_id': 'Alice', 'alias': 'Alice'},
  maxPlayers: 4,
);
handle.snapshots.listen((snap) {
  if (snap.state == 'playing') startBizUI(snap);   // 阶段码在顶层 state
});
await handle.applyAction(type: 'CHAT', params: {'text': 'Hello', 'alias': 'Alice'});
```
