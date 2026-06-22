# 斗兽棋 (Jungle Chess) LAN 实施补完 — 设计文档

## 概述

把 `jungle_chess` 模块中已写好的 LAN 协议骨架,补完为**可运行的完整实现**。
实施方案:**完全机械照搬 `lib/core/surround_game/` 的 LAN 实现模式**,使 jungle_chess 在
架构、文件、接口、生命周期上与 surround_game 保持一致。

> **不**重新设计 LAN。`surround_game` 是经过双机联调验证的参考实现,本次任务只是把
> jungle_chess 的占位/TODO 替换为同形态的真实代码。

## 背景

- jungle_chess 的本地模式已 100% 完成并合入 master(#71)
- LAN 模式只有协议骨架:`lan_messages` / `lan_match_state` / `lan_match_event` /
  `lan_host_view_model` / `lan_client_view_model` / 两个 `*_protocol_bridge` / `lan_channels`
- 关键空缺:
  - `lan_service_adapter.dart` 全是 TODO(没接 LanFramework)
  - `lan_lobby_page.dart` 极简 66 行,无房间发现/设备列表/客户端入口
  - `lan_client_game_page.dart` 是占位文字版
  - 缺 `LanRoomPage` 中转页
  - 缺 `device_id_service` / `player_profile_service` 持久化
  - `GameStateSerializer` 未实现 `StateSerializer` 接口
- 现有 spec `docs/superpowers/specs/2026-06-21-jungle-chess-design.md` 乐观描述了 LAN 完整实现
  但与实际代码不符

## 架构

### 整体分层(沿用 surround_game 三层架构)

```
Game Layer         lib/core/jungle_chess/lan/        (本模块)
Biz Adapter        JungleLanServiceAdapter            (本模块,单例桥接)
Framework Layer    lib/core/localnet/                 (项目基础设施)
```

### 文件清单与机械映射表

| surround_game 源文件 | jungle_chess 目标路径 | 操作 |
|--------------------|--------------------|------|
| `lan/persistence/device_id_service.dart` | `lan/persistence/device_id_service.dart` | 新增,1:1 复制 |
| `lan/persistence/player_profile_service.dart` | `lan/persistence/player_profile_service.dart` | 新增,1:1 复制 |
| `lan/serializer/game_state_serializer.dart` | `lan/serializer/game_state_serializer.dart` | 改写,加 `implements StateSerializer`,适配 GameState |
| `lan/service/lan_service_adapter.dart` | `lan/service/lan_service_adapter.dart` | 改写,把 TODO 替换为 `_LanServiceAdapterImpl` |
| `lan/lan_lobby_page.dart` | `lan/lan_lobby_page.dart` | 改写,从 66 行扩到 ~370 行 |
| `lan/lan_room_page.dart` | `lan/lan_room_page.dart` | 新增,1:1 复制,适配 Host/Client 双角色 |
| `lan/lan_host_game_page.dart` | `lan/lan_host_game_page.dart` | 改写,在 initState 创建 Session,dispose 销毁 |
| `lan/lan_client_game_page.dart` | `lan/lan_client_game_page.dart` | 改写,改为只读文字版 |
| `widgets/touch_controller.dart` 中的 `LanHostTouchController` | `widgets/jungle_host_touch_controller.dart` | 新增,Y 镜像实现 |

### 不改动的文件

以下文件已按 playbook 写好,**不改动**:

- `lan/protocol/lan_messages.dart`(8 种 LanRoomEvent sealed)
- `lan/protocol/lan_channels.dart`(3 个 channel 常量)
- `lan/lan_match_state.dart`(Host 6 态 + Client 7 态)
- `lan/lan_match_event.dart`(Host/Client event sealed)
- `lan/lan_host_view_model.dart`(ValueNotifier + reduce)
- `lan/lan_client_view_model.dart`(ValueNotifier + reduce)
- `lan/lan_host_protocol_bridge.dart`(纯函数 reduce)
- `lan/lan_client_protocol_bridge.dart`(纯函数 reduce)
- `lan/game_room.dart`(GameRoom 模型)

### spec 更新

`docs/superpowers/specs/2026-06-21-jungle-chess-design.md`:
- 新增"LAN 实施补完"section,引用本文档
- "页面导航"section 更新为 `LanLobbyPage → LanRoomPage → LanHost/ClientGamePage`
- 自检清单增加 12 项 LAN 相关条目

## 数据流

### Host 端完整链路(5 阶段)

```
Phase 1: 进入大厅
  Navigator.push(LanLobbyPage)
  → initState → addPostFrameCallback → _bootstrap()
  → PlayerProfileService.loadAlias() + LanServiceAdapter.instance.start()
  → 订阅 watchRoomEvents / watchDevices / watchErrors

Phase 2: 创建房间
  用户输入 alias → 失焦保存
  点"创建房间" → _onCreateRoom()
  → LanHostViewModel.dispatch(HostCreateRoomPressed()) → HostWaiting
  → Navigator.push(LanRoomPage(role:'host', roomId))
  → LanRoomPage.initState → LanServiceAdapter.announceRoom() (5s Timer + 立即发一次)

Phase 3: Client 加入 + 倒计时
  收到 ClientJoinRequested → reduce → sendJoinAccept
  → HostStartGame → HostCountdown(3)
  → Timer.periodic(1s) → HostCountdownTick → HostInGame(initialState)

Phase 4: 进游戏页(Session 创建 + 双向同步)
  Navigator.push(LanHostGamePage)
  → initState → 创建 gameStateNotifier + JungleHostTouchController
  → LanServiceAdapter.createGameSession(peerDeviceId: clientId, state: notifier)
  → _onMoveConfirmed → HostMoveCommitted → JungleEngine.movePiece
  → notifier.value = next → Session 自动推给 Client

Phase 5: 退出
  Navigator.pop → session.dispose / touchController.dispose / notifier.dispose
  → LanRoomPage.dispose → adapter.stopRoom(广播 HostRoomClosed)
  → LanLobbyPage.dispose → cancel subs + adapter.stop()
```

### Client 端完整链路(5 阶段)

```
Phase 1: 进入大厅(扫描房间)
  与 Host 共享 LanLobbyPage
  → 订阅 watchRoomEvents → 收 HostRoomAnnounced → 加入 _rooms 列表
  → 订阅 watchDevices → _devices 列表

Phase 2: 加入房间
  点列表房间 → Navigator.push(LanRoomPage(role:'client', initialRoom))
  → initState → LanClientViewModel + dispatch(ClientJoinRoom)
  → ClientJoining → LanServiceAdapter.sendJoinRequest
  → 订阅 watchRoomEvents 等待 ClientJoinResult

Phase 3: 倒计时
  收 ClientJoinResult(accepted:true) → ClientWaiting
  收倒计时事件 → ClientCountdown(3) → ClientInGame

Phase 4: 进游戏页(纯只读文字版)
  Navigator.push(LanClientGamePage)
  → initState → 创建 ValueNotifier<GameState>(initialState)
  → 订阅 watchRoomEvents → 收到 HostGameStatePushed → notifier.value = newState
  → build → switch(state) → 仅显示文字回合,不渲染 JungleBoard
  → 不创建 touchController,不响应触摸
  → finished: 显示胜方 + 退出按钮

Phase 5: 退出
  Navigator.pop → cancel subs + LanClientViewModel.dispose
```

### 跨设备状态同步机制

- **Phase 1-3**(房间/加入):UDP 多播,所有设备收到,通过 `toDeviceId` 字段过滤
- **Phase 4**(游戏状态):HTTP Session,只有 Host 和目标 Client 之间的双向连接
- Host 的 `ValueNotifier<GameState>` 是**权威单一来源**
- Client 端用 `ValueNotifier<GameState>` **只接收不写入**

## 关键文件契约

### 5.1 LanServiceAdapter 接口

```dart
abstract class LanServiceAdapter {
  static final instance = LanServiceAdapter._();

  Future<void> start({String? myAlias});
  Future<void> stop();
  bool get isRunning;

  String get myDeviceId;
  String get myAlias;
  void updateAlias(String newAlias);
  Stream<List<Device>> watchDevices();

  Stream<LanRoomEvent> watchRoomEvents();
  Stream<LanServiceError> watchErrors();
  Future<void> announceRoom(GameRoom room);
  Future<void> stopRoom(String roomId);

  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  });
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  });

  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  });
}
```

### 5.2 GameStateSerializer

```dart
class GameStateSerializer
    implements StateSerializer<ValueNotifier<GameState>> {
  const GameStateSerializer();

  @override
  Map<String, dynamic> serialize(ValueNotifier<GameState> notifier) {
    return notifier.value.toJson();
  }

  @override
  ValueNotifier<GameState> deserialize(
    Map<String, dynamic> data,
    ValueNotifier<GameState> target,
  ) {
    final temp = GameState.fromJson(data);
    // JungleChess 状态完整,不需要 replayHistory
    target.value = temp;
    return target;
  }
}
```

**与 surround_game 区别**:
1. 加上 `implements StateSerializer<ValueNotifier<GameState>>`(原 jungle_chess 没实现接口)
2. **不调 `replayHistory`**(JungleChess GameState 自带完整 pieces map)

### 5.3 LanLobbyPage

进入页自动:
- 加载持久化 alias
- start adapter
- 订阅 watchRoomEvents / watchDevices / watchErrors
- 显示房间列表(由 HostRoomAnnounced 填充)
- 显示设备列表(由 watchDevices 填充)
- 创建房间:dispatch HostCreateRoomPressed → push LanRoomPage(role:'host')
- 加入房间(点列表):push LanRoomPage(role:'client')
- 退出:取消订阅 + adapter.stop()

### 5.4 LanRoomPage(中转页,新增)

```dart
class LanRoomPage extends StatefulWidget {
  final String roomId;
  final String role;            // 'host' or 'client'
  final GameRoom initialRoom;
}

// Host 分支:创建 LanHostViewModel + announceRoom + 收 ClientJoinRequested + 倒计时 → push LanHostGamePage
// Client 分支:创建 LanClientViewModel + sendJoinRequest + 收 ClientJoinResult + 倒计时 → push LanClientGamePage
```

### 5.5 LanHostGamePage

```dart
// initState:
//   创建 JungleHostTouchController (Y 镜像版)
//   创建 ValueNotifier<GameState>(JungleEngine.createInitialState())
//   创建 Session:
//     final session = LanServiceAdapter.instance.createGameSession(
//       peerDeviceId: clientDeviceId,
//       state: gameStateNotifier,
//     )

// _onMoveConfirmed(from, to):
//   dispatch(HostMoveCommitted) → ViewModel 调 JungleEngine.movePiece
//   更新 gameStateNotifier.value → Session 自动推给 Client

// dispose: session.dispose / touchController.dispose / notifier.dispose
```

**单一 source of truth = `gameStateNotifier`**,ViewModel 只负责 start/countdown/finish 状态编排。
ViewModel 与 notifier 桥接方式(机械照搬 surround_game):

```dart
// LanHostGamePage.initState:
final gameStateNotifier = ValueNotifier<GameState>(JungleEngine.createInitialState());

// ViewModel.addListener → 同步 gameStateNotifier
widget.viewModel.addListener(() {
  final s = widget.viewModel.value;
  if (s is HostInGame) gameStateNotifier.value = s.gameState;
  if (s is HostFinished) gameStateNotifier.value = s.gameState;
});

// 反向:notifier → ViewModel(如需):
// 此处无,Host 走棋只走 ViewModel reducer,reducer 内部调 JungleEngine.movePiece 后
// 既更新 ViewModel.value,也把新 GameState 写入 gameStateNotifier
```

`onMoveConfirmed(from, to)` 内:
1. `widget.viewModel.dispatch(HostMoveCommitted(from, to))` → reducer 跑引擎
2. reducer 返回的 `next.gameState` 写入 `gameStateNotifier.value` → Session 自动序列化推送

### 5.6 LanClientGamePage(严格只读文字版)

```dart
// initState:
//   创建 ValueNotifier<GameState>(initialState)
//   订阅 LanServiceAdapter.watchRoomEvents → 收到 HostGameStatePushed → 更新 notifier

// build: switch(state) →
//   ClientInGame → "等待 Host 走子... 当前回合: 蓝方/红方"
//   ClientFinished → "游戏结束: XXX 获胜" + 退出按钮
//   ClientDisconnected → "断开: XXX"
```

**机械照搬决定**:不渲染 JungleBoard(完全照搬 surround_game 极简风格)。

### 5.7 JungleHostTouchController(Y 镜像,即使不需要)

```dart
class JungleHostTouchController extends JungleTouchController {
  final double boardSize;
  JungleHostTouchController({required this.boardSize});

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  @override
  void onDragStart(GameState state, int index, Offset fingerPos) {
    super.onDragStart(state, index, _mirror(fingerPos));
  }

  @override
  void onDragUpdate(GameState state, Offset fingerPos) {
    super.onDragUpdate(state, _mirror(fingerPos));
  }

  @override
  void onDragEnd(GameState state, Offset fingerPos) {
    super.onDragEnd(state, _mirror(fingerPos));
  }
}
```

**机械照搬决定**:虽然 JungleChess 棋盘对称不需要镜像,但保留 Y 镜像实现以保持模板一致性。

### 5.8 persistence services(1:1 复制)

```dart
// device_id_service.dart
class DeviceIdService {
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('device_id', id);
    }
    return id;
  }
}

// player_profile_service.dart
class PlayerProfileService {
  static const _kAliasKey = 'player_alias';
  static Future<String?> loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kAliasKey);
  }
  static Future<void> saveAlias(String alias) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAliasKey, alias);
  }
}
```

## 错误处理

| 错误类型 | 触发场景 | 处理方式 |
|---------|---------|---------|
| Adapter 启动失败 | LanFramework.start 抛异常 | SnackBar `'框架启动失败: $e'` |
| 协议解析失败 | UDP 多播消息 type 未知 / payload 缺字段 | `errorsCtrl.add(LanServiceError)`,不影响其他消息 |
| 房间 join 失败 | UDP sendMulticast 返回 SendResult.failure | SnackBar `'加入房间失败: $reason'` |
| Join 请求被拒 | Client 收到 ClientJoinResult(accepted:false) | reduce: ClientJoining → ClientIdle,显示拒绝页 + 返回按钮 |
| Host 掉线 | watchDevices 不再包含 hostId | 推 ClientDisconnected → "Host 失联"页 |
| Client 掉线 | watchDevices 不再包含 clientId | 推 HostClientLeft → HostError → 显示错误页 |
| 走子非法 | JungleEngine.movePiece 返回 null | reduce 内 `if (next == null) return state`,静默忽略 |
| Session 反序列化失败 | JSON 缺字段 / type 不匹配 | Session 内部 catch + 日志;UI 继续用旧 state |
| 重复创建房间 | Host 快速双击"创建" | ViewModel 在 initState 创建,UI 按钮 disable |
| deviceId 未持久化 | 第一次启动 | DeviceIdService.load 内部生成 + save 到 SharedPreferences |

## 测试策略

| 测试类型 | 方法 | 关键用例 |
|---------|------|---------|
| 规则引擎单测 | `flutter test test/core/jungle_chess/engine/` | 鼠吃象/象不吃鼠/陷阱降级/河跳/胜负/悔棋 |
| 协议消息序列化 | `flutter test test/core/jungle_chess/lan/protocol/` | 8 种 LanRoomEvent toJson/fromJson 往返一致 |
| 纯函数 reducer | `flutter test test/core/jungle_chess/lan/` | reduceHostProtocol / reduceClientProtocol 全分支 |
| 本地模式烟测 | flutter run → LocalGamePage | 一局完整下完 → 胜负弹窗 → 悔棋 |
| LAN 双机联调 | 两台 Android 真机 + 同一 WiFi | 建房 → Client 加入 → 倒计时 → 走子 → Client 收到 → 结束 |
| LAN 单机自测 | emulator + 真机 | 同上,验证跨设备发现 |
| 断线恢复 | 一台设备杀进程 → 另一台收 HostClientLeft | Host 端弹错误页 |

## 显式不包含的范围

- ❌ AI 对手
- ❌ 计时器 / 读秒
- ❌ 在线匹配(仅局域网)
- ❌ 游戏房间历史 / 棋谱存档
- ❌ 重播功能
- ❌ 观战模式
- ❌ 聊天/表情
- ❌ Client 棋盘渲染(严格只读文字版)
- ❌ 断线恢复重连
- ❌ 多局连战(一局结束必须返回 Lobby)
- ❌ 房间密码
- ❌ 跨平台支持(仅 Android 真机)

## 实施风险与缓解

| 风险 | 概率 | 影响 | 缓解 |
|------|------|------|------|
| localnet framework API 与 jungle_chess 已写代码不匹配 | 中 | 阻塞 | 机械照搬 surround_game 已验证 API 形态 |
| Session 大对象序列化慢 | 低 | 性能 | GameState.toJson 已实现;Session 在状态变更才推一次 |
| UDP 多播在家用路由器被过滤 | 高 | 两机互不可见 | 用 `239.255.255.255` ADMINSCOPE |
| Adapter 启动时序错乱 | 中 | 资源泄漏 | `stop()` 内 await cancel all subs |
| JungleHostTouchController Y 镜像导致 jungle_chess 触摸错位 | 高 | UX 差 | jungle_chess 棋盘对称实际不需要镜像,但保留——因为宿主棋盘不翻转,镜像等价于原坐标 |
| Client 接收到 state 但 gameStateNotifier 没更新 | 低 | 状态卡住 | Session 内部 `_suppressSync` + listener 在 HostGamePage 监听 device 事件 |
| 两个 persistence service 包依赖冲突 | 低 | 编译失败 | `shared_preferences` + `uuid` 是 surround_game 已用依赖 |

## 验收清单

- [ ] 9 个文件按映射表完成(4 新增 + 5 改写)
- [ ] `LanServiceAdapter` 14 个方法签名与 surround_game 一致
- [ ] `GameStateSerializer` 加上 `implements StateSerializer<ValueNotifier<GameState>>`
- [ ] `LanLobbyPage` 支持房间列表 + 设备列表 + 错误提示
- [ ] `LanRoomPage` 中转页存在,Host/Client 双角色
- [ ] `LanHostGamePage` 进游戏页自动创建 Session + 走棋自动同步
- [ ] `LanClientGamePage` 严格只读文字版,不渲染棋盘
- [ ] `JungleHostTouchController` Y 镜像实现存在
- [ ] 两个 persistence service 1:1 复制
- [ ] 文档 `docs/superpowers/specs/2026-06-21-jungle-chess-design.md` 增加"LAN 实施补完"section
- [ ] 双机联调:建房间 → Client 加入 → 倒计时 → Host 走棋 → Client 看到回合切换 → 一局完整下完
- [ ] `flutter analyze` 通过(无 error)

## 关键约束

1. 完全机械照搬 surround_game,**不**重新设计 LAN 协议或架构
2. 协议与状态机(8 个已有文件)**不改动**,只在缺失处补完
3. Host-Authoritative 模型:Host 唯一执行引擎,Client 只接收 state
4. 两段式 Session:房间 UDP 多播 + 游戏 HTTP Session
5. Client 严格只读,不渲染棋盘,不响应触摸
6. 单一 source of truth:`gameStateNotifier`,ViewModel 只做状态编排

## 关联文档

- 上游 spec:`docs/superpowers/specs/2026-06-21-jungle-chess-design.md`
- 实施 playbook:`.claude/skills/lan-local-playbook/SKILL.md`
- 参考实现:`lib/core/surround_game/`(机械照搬源)
- 框架:`lib/core/localnet/`(基础设施)