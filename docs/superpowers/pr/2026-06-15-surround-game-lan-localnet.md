# PR: Surround Game LAN 接入 LocalNet 框架

## 概要

把 `lib/core/surround_game/lan/` 子树从「桩化 UI」升级为「通过 `lib/core/localnet/` 框架真正实现双设备联机」。

- **21 个 TDD task**（含 1 个 plan 修订 + 3 个 fix），全部提交
- **21 / 21 unit test pass**（0 失败、0 跳过）
- `flutter analyze`：0 errors，340 个 pre-existing info 警告（与本 PR 无关，全部是 `withOpacity` deprecation）

## 架构分层

```
lib/core/surround_game/
├── lobby/                  ← 模式选择（不动）
├── local/                  ← 单机热座（不动）
├── lan/                    ← 本轮目标
│   ├── protocol/           ← 新增：通道常量 + sealed class 消息
│   ├── serializer/         ← 新增：GameState ↔ Map
│   ├── service/            ← 新增：LanServiceAdapter（业务层唯一接触 localnet）
│   ├── profile/            ← 新增：aliasDialog
│   ├── lan_host_protocol_bridge.dart  ← 新增：Host 端纯函数
│   ├── lan_client_protocol_bridge.dart ← 新增：Client 端纯函数
│   ├── lan_lobby_page.dart     ← 改：adapter 启动 + 房间列表
│   ├── lan_room_page.dart      ← 改：协议 join/accept 流
│   ├── lan_host_game_page.dart ← 改：创 Session 绑定 notifier
│   ├── lan_client_game_page.dart ← 改：显式 sendTo
│   ├── lan_host_view_model.dart  ← 改：注入 deviceLost + 协议流
│   ├── lan_client_view_model.dart ← 改：同上
│   └── widgets/            ← 不动
```

**核心决策**：
- **adapter 隔离**：业务层（Page / ViewModel / bridge）不直接 import `lib/core/localnet/`，全部走 `LanServiceAdapter.instance`
- **协议集中**：所有 channel 字符串与消息 sealed class 集中在 `protocol/`
- **不可变不变**：保持 `GameState` 不可变；外层 `ValueNotifier<GameState>` 提供 Listenable
- **Host 权威**：Host 端用 `Session<ValueNotifier<GameState>>` 自动发；Client 端用显式 `sendGameState` 发；Client 不创建 Session
- **TDD 节奏**：每个 task 先写测试 → 看到失败 → 写代码 → 通过 → commit

## 验证

- `flutter analyze`：**0 errors**
- `flutter test`：**21 / 21 pass**
- 跨进程手动 demo 文档：`docs/superpowers/demo/2026-06-15-surround-game-lan-e2e-manual.md`
- 集成测试：**降级为手动跨进程 demo**（见下方 Scope）

## Scope

### 本 PR 包含

- 24 个新增 / 修改 commit（`04902ef` ~ `39a080e`）
- 10 个新增文件 + 7 个修改文件
- 21 个 unit test + 1 个跨进程 demo 文档
- 全套 spec / plan / 4 个 spec 修订 commit

### 本 PR **不**包含

- ❌ **自动化集成测试**：因 `LanFramework` 是单例，2 框架实例需 framework 暴露多实例 API（属 framework owner 评估范围）。本轮降级为手动跨进程 demo。
- ❌ **deviceLost UI 提示**：LanHostGamePage 的 build switch 把 `HostError` 落到默认 `_buildIdleScreen`，没有"对手掉线"提示或重试按钮。VM 状态机迁移正确（已测试），UI 响应属后续 task。
- ❌ **重连逻辑**：掉线后只能退出重进 LanRoomPage。
- ❌ **未实现的协议命令**：`sendLeave`（spec 接口中明文但 plan 全文无引用，YAGNI）。
- ❌ **未实现的倒计时同步**：Host 端本地倒计时结束即跳 GamePage；Client 端收到 join accept 立即跳 — 双方可能错开数百毫秒（YAGNI）。

### 本 PR 修复的静默 bug

1. **HostGamePage peerDeviceId 取值为 null**（commit `2fd0e86`）：`widget.initialRoom.clientId` 在构造时为 null，改为从 VM 当前状态取。
2. **HostGamePage 收不到 Client 状态**（commit `495e884`）：Host 端 Session 监听 `session/${peerId}_${state.hashCode}` 通道，与 Client `sendGameState` 用的 `surround/game/state` 通道不重叠。补订阅 `watchGameState` 流。
3. **Host VM deviceLost 路径死路径**（commit `6597fbd`）：`dispatch(HostClientLeft())` 走 `LanHostEvent` 通道，但 `reduce` 无 case 匹配，导致 deviceLost 监听完全失效。改为走 `_onRoomEvent(HostClientLeft())` 协议路径。

## Follow-up（建议下一轮）

1. **HostError UI**：补 `LanHostGamePage` 的 HostError 状态 UI（"对手掉线"提示 + Retry 按钮）
2. **framework 多实例 API**：与 framework owner 协商暴露 `LanFramework.create({...})` 多实例方法
3. **watchGameState 过滤**：adapter `watchGameState(hostDeviceId)` 当前共享一个流，未按 hostDeviceId 过滤；多 host 场景下需修
4. **deviceLost UX 缺**：仅做了状态机迁移，UI 未提供"重连"按钮
5. **倒计时同步**：双方各跳各的，无协调

## 风险

- `LanServiceAdapter` 是单例：第二次 `start()` 在 `_isRunning=false` 时会重新订阅；如果 stop 未正确置 `_isRunning=false`，房间列表会一直空。当前 stop 路径正确。
- 跨进程 demo 需两台真机/模拟器（同一局域网），本 PR 不强制 e2e 自动化
- `withOpacity` 弃用警告（pre-existing 340 个）本轮未修，超出 PR 范围

## 文件清单

**新增（10）**：
- `lib/core/surround_game/lan/protocol/lan_channels.dart`
- `lib/core/surround_game/lan/protocol/lan_messages.dart`（追加 2 个内部事件子类）
- `lib/core/surround_game/lan/serializer/game_state_serializer.dart`
- `lib/core/surround_game/lan/service/lan_service_adapter.dart`
- `lib/core/surround_game/lan/profile/alias_dialog.dart`
- `lib/core/surround_game/lan/lan_host_protocol_bridge.dart`
- `lib/core/surround_game/lan/lan_client_protocol_bridge.dart`
- `test/core/surround_game/lan/protocol/lan_messages_test.dart`
- `test/core/surround_game/lan/serializer/game_state_serializer_test.dart`
- `test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart`
- `test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart`
- `test/core/surround_game/lan/view_model/host_device_lost_test.dart`
- `test/core/surround_game/lan/view_model/client_device_lost_test.dart`
- `docs/superpowers/demo/2026-06-15-surround-game-lan-e2e-manual.md`

**修改（7）**：
- `lib/core/surround_game/lan/lan_lobby_page.dart`
- `lib/core/surround_game/lan/lan_room_page.dart`
- `lib/core/surround_game/lan/lan_host_view_model.dart`
- `lib/core/surround_game/lan/lan_client_view_model.dart`
- `lib/core/surround_game/lan/lan_host_game_page.dart`
- `lib/core/surround_game/lan/lan_client_game_page.dart`
- `docs/superpowers/specs/2026-06-15-surround-game-lan-localnet-design.md`（自审修订）
- `docs/superpowers/plans/2026-06-15-surround-game-lan-localnet-plan.md`（sealed 约束修订）

## 参考

- Spec：`docs/superpowers/specs/2026-06-15-surround-game-lan-localnet-design.md`
- Plan：`docs/superpowers/plans/2026-06-15-surround-game-lan-localnet-plan.md`
- 上一轮：UI 拆分（commit `fb7c61e`）
- 跨进程 demo：`docs/superpowers/demo/2026-06-15-surround-game-lan-e2e-manual.md`
