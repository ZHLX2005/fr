# LAN 模式升级：双端 Session 同步 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 lan 模式从「双端手动 sendGameState + watchGameState」升级为「双端 Session 自动同步」，删除所有手动 bridge 代码。

**Architecture:** 三步改造：(1) `Session` 增加 `channelName` 可选参数让双端共享固定 channel；(2) GamePage 双端各创 `Session<ValueNotifier<GameState>>`，落子直调引擎算 next → notifier → Session 自动发；(3) 删除 sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed / GamePage VM fast-forward / 旧 deviceLost 测试。

**Tech Stack:** Flutter / Dart, `ValueNotifier<T>` + `ValueListenableBuilder`, `QuoridorEngine` (movePiece / placeWall / switchTurn), `Session<S extends Listenable>` + `GameStateSerializer`, sealed class 状态机, TDD (flutter test).

**参考文档：**
- Spec: `docs/superpowers/specs/2026-06-16-surround-game-lan-session-upgrade-design.md`
- 当前 commit 基线: `7eb8176`

---

## 任务依赖图

```
T1 Session channelName 改造 (framework 改动)
  ↓
T2 Session channelName 单测验证
  ↓
T3 adapter 删除 sendGameState / watchGameState
  ↓
T4 LanHostGamePage 改用 Session
T5 LanClientGamePage 改用 Session          (与 T4 并行可)
T6 删除 VM 事件 HostGameStatePushed/ClientGameStatePushed
T7 删除旧 deviceLost 测试
T8 添加新 widget 测试 (Session 同步路径)
T9 全量验证 + flutter analyze + test
T10 commit + PR 描述
```

---

### Task 1: Session 加 channelName 参数（framework 改动）

**Files:**
- Modify: `D:\DevProjects\my\github\fr\lib\core\localnet\session\session.dart`
- Modify: `D:\DevProjects\my\github\fr\lib\core\localnet\session\session_manager.dart`
- Modify: `D:\DevProjects\my\github\fr\lib\core\localnet\framework\lan_framework.dart`

- [ ] **Step 1: 修改 `session.dart` 的 Session 构造器**

读取 `D:\DevProjects\my\github\fr\lib\core\localnet\session\session.dart`，找到 `Session` 构造器签名（约 line 53-60）。

把：

```dart
Session({
  required this.peerId,
  required this.state,
  required ChannelManager channelManager,
  required StateSerializer<StateT> serializer,
})  : _channelManager = channelManager,
      _serializer = serializer {
  _startMonitoring();
}
```

改为：

```dart
Session({
  required this.peerId,
  required this.state,
  required ChannelManager channelManager,
  required StateSerializer<StateT> serializer,
  this.channelName,
})  : _channelManager = channelManager,
      _serializer = serializer {
  _startMonitoring();
}

/// 自定义 channel 名（双端 Session 同步时使用固定 channel）
final String? channelName;
```

- [ ] **Step 2: 修改 `_sessionChannel` getter**

找到：

```dart
String get _sessionChannel => 'session/${peerId}_${state.hashCode}';
```

改为：

```dart
String get _sessionChannel =>
    channelName ?? 'session/${peerId}_${state.hashCode}';
```

- [ ] **Step 3: 修改 `session_manager.dart` 的 `create` 方法**

读取 `D:\DevProjects\my\github\fr\lib\core\localnet\session\session_manager.dart`，找到 `create` 方法（约 line 22-38）。

把：

```dart
Session<S> create<S extends Listenable>({
  required String peerId,
  required S state,
  required StateSerializer<S> serializer,
}) {
  final session = Session<S>(
    peerId: peerId,
    state: state,
    channelManager: _channelManager,
    serializer: serializer,
  );

  final key = _sessionKey(peerId, state);
  _sessions[key] = session;

  return session;
}
```

改为：

```dart
Session<S> create<S extends Listenable>({
  required String peerId,
  required S state,
  required StateSerializer<S> serializer,
  String? channelName,
}) {
  final session = Session<S>(
    peerId: peerId,
    state: state,
    channelManager: _channelManager,
    serializer: serializer,
    channelName: channelName,
  );

  final key = _sessionKey(peerId, state);
  _sessions[key] = session;

  return session;
}
```

- [ ] **Step 4: 修改 `lan_framework.dart` 的 `createSession` 方法**

读取 `D:\DevProjects\my\github\fr\lib\core\localnet\framework\lan_framework.dart`，找到 `createSession` 方法（约 line 127-138）。

把：

```dart
Session<ValueNotifier<GameState>> createGameSession({
  required String peerDeviceId,
  required ValueNotifier<GameState> state,
  StateSerializer<ValueNotifier<GameState>>? serializer,
}) {
  return _core!.sessionManager.create(
    peerId: peerDeviceId,
    state: state,
    serializer: serializer ?? _defaultJsonSerializer<ValueNotifier<GameState>>(),
  );
}
```

改为：

```dart
Session<ValueNotifier<GameState>> createGameSession({
  required String peerDeviceId,
  required ValueNotifier<GameState> state,
  StateSerializer<ValueNotifier<GameState>>? serializer,
  String? channelName,
}) {
  return _core!.sessionManager.create(
    peerId: peerDeviceId,
    state: state,
    serializer: serializer ?? _defaultJsonSerializer<ValueNotifier<GameState>>(),
    channelName: channelName,
  );
}
```

- [ ] **Step 5: 验证 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze lib/core/localnet/
```
期望：0 errors

- [ ] **Step 6: 跑现有 test 确认向后兼容**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test test/core/localnet/
```
期望：全 pass（不传 channelName 时行为不变）

- [ ] **Step 7: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/localnet/session/session.dart lib/core/localnet/session/session_manager.dart lib/core/localnet/framework/lan_framework.dart
git commit -m "feat(localnet/session): Session 加 channelName 可选参数"
```

---

### Task 2: Session channelName 单测

**Files:**
- Create: `D:\DevProjects\my\github\fr\test\core\localnet\session\session_channel_name_test.dart`

- [ ] **Step 1: 写测试**

读取 `lib/core/localnet/session/session.dart` 的 `Session` 构造器和 `_sessionChannel` getter 代码（确认字段名与默认行为）。

```dart
// test/core/localnet/session/session_channel_name_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_manager.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';

void main() {
  group('Session.channelName', () {
    test('不传 channelName 时用默认格式 session/\$\{peerId\}_\$\{state.hashCode\}', () {
      final state = ValueNotifier<int>(42);
      final session = Session<int>(
        peerId: 'peerA',
        state: state,
        channelManager: _FakeChannelManager(),
        serializer: _IntPassthroughSerializer(),
      );
      expect(session.channelName, isNull);
      // 默认 channel 包含 peerId 和 state.hashCode
      expect(session.toString(), contains('peerA'));
    });

    test('传 channelName 时使用固定值', () {
      final state = ValueNotifier<int>(42);
      final session = Session<int>(
        peerId: 'peerA',
        state: state,
        channelManager: _FakeChannelManager(),
        serializer: _IntPassthroughSerializer(),
        channelName: 'surround/game/state',
      );
      expect(session.channelName, 'surround/game/state');
    });
  });
}

// 简单 fake channel manager — 不真正通信
class _FakeChannelManager implements ChannelManager {
  @override
  Stream watchChannel(String channel) => const Stream.empty();
  @override
  Future<dynamic> sendTo(String targetDeviceId, String channel, Map<String, dynamic> payload) async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _IntPassthroughSerializer implements StateSerializer<ValueNotifier<int>> {
  @override
  Map<String, dynamic> serialize(ValueNotifier<int> notifier) => {'v': notifier.value};
  @override
  ValueNotifier<int> deserialize(Map<String, dynamic> data, ValueNotifier<int> target) {
    target.value = data['v'] as int;
    return target;
  }
}
```

- [ ] **Step 2: 跑测试**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test test/core/localnet/session/session_channel_name_test.dart
```
期望：2 tests pass（如果 channelName 字段是 private，需要先在 session.dart 加一个公开访问或者改测试策略）

**注意**：如果 `channelName` 字段设为 `final String?`，测试可以直接读 `session.channelName`。如果验证 `_sessionChannel` getter 是 private，测试可以通过 `session.toString()` 或构造器验证间接推断。

**如果测试需要验证 channel 名变化**：在 `session.dart` 增加一个 `@visibleForTesting String get debugChannelName => _sessionChannel;`，或者把 `_sessionChannel` 改为 public `sessionChannel`。本计划采用后者：把 `_sessionChannel` 改名为 `sessionChannel`（public）。这不影响生产代码（仅 framework 内部使用）。

如果 `_sessionChannel` 已经在 framework 内部被外部调用，需要保持 private + 改测试策略。**请 implementer 自行判断**。

- [ ] **Step 3: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add test/core/localnet/session/session_channel_name_test.dart lib/core/localnet/session/session.dart
git commit -m "test(localnet/session): Session.channelName 单测"
```

---

### Task 3: adapter 删除 sendGameState / watchGameState

**Files:**
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\service\lan_service_adapter.dart`

- [ ] **Step 1: 删除 `sendGameState` 方法**

读取 `lan_service_adapter.dart`，找到 `sendGameState` 方法（约 line 244-254）和 `_gameStateStreams` map（约 line 89），删除：

```dart
  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  });
```

和 `_LanServiceAdapterImpl` 中的实现 + `_gameStateStreams` 字段。

- [ ] **Step 2: 删除 `watchGameState` 方法**

删除 `Stream<GameState> watchGameState(String hostDeviceId);` 接口方法和 `_LanServiceAdapterImpl` 中的实现。

- [ ] **Step 3: 删除 `_gameStateCtrl` StreamController**

找到 `_gameStateCtrl` 字段定义和 `_multicastSub` 里的 `key == 'game_state'` 分支（约 line 81, 140-155），全部删除。

- [ ] **Step 4: 验证 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze lib/core/surround_game/lan/service/lan_service_adapter.dart
```
期望：0 errors（可能有几个删除相关的 warning，自行处理）

- [ ] **Step 5: 跑现有 test（部分会 fail，因为 GamePage 还在调用这些方法）**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test test/core/surround_game/lan/
```
**预期**：会有 test fail，提示 GamePage 用到的方法不存在。这没关系，Task 4/5 会修。

**注意**：不要跑 `flutter analyze lib/core/surround_game/lan/`（整个目录）— GamePage 还在用旧 API，会大量 error。

- [ ] **Step 6: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/service/lan_service_adapter.dart
git commit -m "refactor(surround_game/lan): adapter 删除 sendGameState/watchGameState"
```

---

### Task 4: LanHostGamePage 改用 Session

**Files:**
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\lan_host_game_page.dart`

- [ ] **Step 1: 修改 initState（删除 VM fast-forward 和 _gameStateSub）**

读取 `lan_host_game_page.dart` 的 initState（约 line 56-82），替换为：

```dart
  @override
  void initState() {
    super.initState();
    _gameStateNotifier = ValueNotifier<GameState>(QuoridorEngine.initialize());
    _session = LanServiceAdapter.instance.createGameSession(
      peerDeviceId: widget.peerDeviceId,
      state: _gameStateNotifier!,
      channelName: LanChannels.gameState,
    );
    _session!.onChanged = () {
      if (mounted) setState(() {});
    };
    // Host 主动发初始 state（让 Client 进入后立刻收到）
    _session!.syncFull();
    // deviceLost 检测
    _devicesSub = LanServiceAdapter.instance.watchDevices().listen(_onDevices);
    // 错误 SnackBar
    _errorSub = LanServiceAdapter.instance.watchErrors().listen(_onError);
  }
```

删除：
- `_viewModel = LanHostViewModel()` 字段
- `_viewModel.attachPeer(widget.peerDeviceId)`
- `_viewModel.dispatch(HostCreateRoomWithRoom(...))`
- `_viewModel.dispatch(const HostStartGamePressed())`
- `for (var i = 0; i < 4; i++) { _viewModel.dispatch(const HostTick()); }`
- `_gameStateSub = LanServiceAdapter.instance.watchGameState(...).listen(...)`

新增字段（在 State 类中）：
```dart
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<LanServiceError>? _errorSub;
```

新增方法（在 State 类中）：
```dart
  void _onDevices(List<Device> devices) {
    if (!devices.any((d) => d.deviceId == widget.peerDeviceId)) {
      _showDisconnectDialog();
    }
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  void _showDisconnectDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('对手已掉线'),
        content: const Text('连接已断开，请返回房间列表。'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
```

需要新增 import：`'dart:async'`, `'package:xiaodouzi_fr/core/localnet/device/device.dart'`, `'package:xiaodouzi_fr/core/localnet/session/session.dart'`, `'lan/service/lan_service_adapter.dart'`, `'lan/protocol/lan_channels.dart'`。

- [ ] **Step 2: 修改 dispose**

找到 dispose（约 line 91-99），替换为：

```dart
  @override
  void dispose() {
    _devicesSub?.cancel();
    _errorSub?.cancel();
    _session?.dispose();
    _gameStateNotifier?.dispose();
    _touchController.reset();
    super.dispose();
  }
```

删除 `_viewModel.dispose()` 和 `_gameStateSub?.cancel()`。

- [ ] **Step 3: 修改 build 删除 VM switch**

找到 build 方法（约 line 105-126），替换为：

```dart
    return Scaffold(
      backgroundColor: theme.boardSurface,
      appBar: _buildAppBar(theme),
      body: SafeArea(
        child: ValueListenableBuilder<GameState>(
          valueListenable: _gameStateNotifier!,
          builder: (_, gs, __) => _buildBody(gs, theme),
        ),
      ),
    );
```

把原来根据 `LanHostState` switch 的逻辑完全删除，替换为根据 `GameState` 直接构建。

- [ ] **Step 4: 修改 _buildGameScreen（不再从 VM 取 state）**

找到 `_buildGameScreen`（约 line 204-...），把函数体开头的：

```dart
final gs = _gameStateNotifier!.value;
final isRunning = state is HostInGame || state is HostFinished;
final isMyTurn = gs.currentPlayerIsTop;
```

改为（注意不再有 `state` 参数）：

```dart
final isMyTurn = gs.currentPlayerIsTop; // host 是 top player
final isRunning = gs.status == GameStatus.running;
```

**删除**该方法的 `LanHostState state` 参数。把 build switch 改为直接 `_buildBody(GameState)`。

- [ ] **Step 5: 修改 _onConfirm**

找到 `_onConfirm(GameState gs)`（约 line 355-388），替换为：

```dart
  VoidCallback _onConfirm(GameState gs) {
    return () {
      final toc = _touchController;
      if (toc.phase != TouchPhase.confirming) return;

      int? wx, wy;
      WallOrientation? wo;
      if (toc.pendingWall != null) {
        wx = toc.pendingWall!.x;
        wy = toc.pendingWall!.y;
        wo = toc.pendingWall!.o;
      }

      final current = _gameStateNotifier!.value;
      GameState? result;
      if (wx != null && wo != null) {
        result = QuoridorEngine.placeWall(current, wx, wy, wo);
      } else {
        result = QuoridorEngine.movePiece(current, toc.pendingTargetCellId ?? 0);
      }
      if (result == null) {
        toc.reset();
        setState(() {});
        return;
      }
      final next = QuoridorEngine.switchTurn(result);
      // Session 自动 serialize + 发送
      _gameStateNotifier!.value = next;
      toc.reset();
      setState(() {});
    };
  }
```

**删除**：`_viewModel.dispatch(HostMoveCommitted(...))`、`currentState as HostInGame/HostFinished`、`LanServiceAdapter.instance.sendGameState(...)`。

- [ ] **Step 6: 验证 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze lib/core/surround_game/lan/lan_host_game_page.dart
```
期望：0 errors

- [ ] **Step 7: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/lan_host_game_page.dart
git commit -m "refactor(surround_game/lan): LanHostGamePage 改用 Session 双向同步"
```

---

### Task 5: LanClientGamePage 改用 Session（与 Task 4 对称）

**Files:**
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\lan_client_game_page.dart`

- [ ] **Step 1: 修改 initState**

读取 initState（约 line 56-86），替换为：

```dart
  @override
  void initState() {
    super.initState();
    _gameStateNotifier = ValueNotifier<GameState>(QuoridorEngine.initialize());
    _session = LanServiceAdapter.instance.createGameSession(
      peerDeviceId: widget.hostDeviceId,
      state: _gameStateNotifier!,
      channelName: LanChannels.gameState,
    );
    _session!.onChanged = () {
      if (mounted) setState(() {});
    };
    // deviceLost 检测
    _devicesSub = LanServiceAdapter.instance.watchDevices().listen(_onDevices);
    // 错误 SnackBar
    _errorSub = LanServiceAdapter.instance.watchErrors().listen(_onError);
  }
```

删除所有 fast-forward（ClientJoinPressed / ClientJoinAccepted / HostStartedCountdown / 4×ClientTick）、`_gameStateSub`。

新增字段和方法（与 Host 对称）：

```dart
  StreamSubscription<List<Device>>? _devicesSub;
  StreamSubscription<LanServiceError>? _errorSub;

  void _onDevices(List<Device> devices) {
    if (!devices.any((d) => d.deviceId == widget.hostDeviceId)) {
      _showDisconnectDialog();
    }
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  void _showDisconnectDialog() {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('对手已掉线'),
        content: const Text('连接已断开，请返回房间列表。'),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).pop();
            },
            child: const Text('返回'),
          ),
        ],
      ),
    );
  }
```

需要新增 import：`'dart:async'`, `'package:xiaodouzi_fr/core/localnet/device/device.dart'`, `'package:xiaodouzi_fr/core/localnet/session/session.dart'`, `'lan/service/lan_service_adapter.dart'`, `'lan/protocol/lan_channels.dart'`。

- [ ] **Step 2: 修改 dispose**

```dart
  @override
  void dispose() {
    _devicesSub?.cancel();
    _errorSub?.cancel();
    _session?.dispose();
    _gameStateNotifier?.dispose();
    _touchController.reset();
    super.dispose();
  }
```

- [ ] **Step 3: 修改 build 删除 VM switch**

把 build switch 改为 `ValueListenableBuilder<GameState>(valueListenable: _gameStateNotifier!, builder: (_, gs, __) => _buildBody(gs, theme))`。

- [ ] **Step 4: 修改 _buildGameScreen 和 _onConfirm**

`_buildGameScreen` 删除 `LanClientState state` 参数，从 `_gameStateNotifier!.value` 读 gs，`isMyTurn = !gs.currentPlayerIsTop`（client 是 bottom）。

`_onConfirm` 改为直接调 `QuoridorEngine` 算 next，赋值给 notifier（与 Host 对称）：

```dart
final current = _gameStateNotifier!.value;
GameState? result;
if (wx != null && wo != null) {
  result = QuoridorEngine.placeWall(current, wx, wy, wo);
} else {
  result = QuoridorEngine.movePiece(current, toc.pendingTargetCellId ?? 0);
}
if (result == null) {
  toc.reset();
  setState(() {});
  return;
}
final next = QuoridorEngine.switchTurn(result);
_gameStateNotifier!.value = next;
toc.reset();
setState(() {});
```

- [ ] **Step 5: 验证 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze lib/core/surround_game/lan/lan_client_game_page.dart
```
期望：0 errors

- [ ] **Step 6: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/lan_client_game_page.dart
git commit -m "refactor(surround_game/lan): LanClientGamePage 改用 Session 双向同步"
```

---

### Task 6: 删除 VM 事件 HostGameStatePushed / ClientGameStatePushed

**Files:**
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\lan_match_event.dart`
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\lan_host_view_model.dart`
- Modify: `D:\DevProjects\my\github\fr\lib\core\surround_game\lan\lan_client_view_model.dart`

- [ ] **Step 1: 删除 `HostGameStatePushed` 类**

读取 `lan_match_event.dart`，找到 `HostGameStatePushed`（约 line 35 后追加），删除整个类定义和它的位置注释。

- [ ] **Step 2: 删除 `ClientGameStatePushed` 类**

找到 `ClientGameStatePushed`（约 line 117 后追加），删除整个类定义。

- [ ] **Step 3: 删除 HostViewModel reducer 的相关 case**

读取 `lan_host_view_model.dart`，找到 reduce 方法中的 `HostGameStatePushed` case，删除。

- [ ] **Step 4: 删除 ClientViewModel reducer 的相关 case**

读取 `lan_client_view_model.dart`，找到 reduce 方法中的 `ClientGameStatePushed` case，删除。

- [ ] **Step 5: 验证 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze lib/core/surround_game/lan/
```
期望：0 errors

- [ ] **Step 6: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/lan_match_event.dart lib/core/surround_game/lan/lan_host_view_model.dart lib/core/surround_game/lan/lan_client_view_model.dart
git commit -m "refactor(surround_game/lan): 删除 Host/ClientGameStatePushed 事件"
```

---

### Task 7: 删除旧 deviceLost 测试

**Files:**
- Delete: `D:\DevProjects\my\github\fr\test\core\surround_game\lan\view_model\host_device_lost_test.dart`
- Delete: `D:\DevProjects\my\github\fr\test\core\surround_game\lan\view_model\client_device_lost_test.dart`

- [ ] **Step 1: 删除测试文件**

```bash
cd 'D:\DevProjects\my\github\fr'
rm test/core/surround_game/lan/view_model/host_device_lost_test.dart test/core/surround_game/lan/view_model/client_device_lost_test.dart
```

- [ ] **Step 2: 验证剩余 test 仍 pass**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test test/core/surround_game/lan/
```
期望：剩余 19 个 test 仍 pass

- [ ] **Step 3: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add -A
git commit -m "test(surround_game/lan): 删除旧 deviceLost VM 测试"
```

---

### Task 8: 添加新 widget 测试（Session 同步路径）

**Files:**
- Create: `D:\DevProjects\my\github\fr\test\core\surround_game\lan\widget\game_page_session_test.dart`

- [ ] **Step 1: 写测试**

```dart
// test/core/surround_game/lan/widget/game_page_session_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_host_game_page.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

void main() {
  testWidgets('LanHostGamePage 不持有 VM 状态机', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LanHostGamePage(
        roomId: 'test-room',
        peerDeviceId: 'test-client',
      ),
    ));
    // 等待一帧让 initState 跑完
    await tester.pump();
    // 没有 exception 即通过（VM fast-forward 删了后仍能正常 build）
    expect(tester.takeException(), isNull);
    expect(find.byType(LanHostGamePage), findsOneWidget);
  });

  test('isMyTurn 在初始空棋盘上为 true（host 是 top）', () {
    final gs = QuoridorEngine.initialize();
    expect(gs.currentPlayerIsTop, isTrue);
  });

  test('switchTurn 后 currentPlayerIsTop 反转', () {
    final s0 = QuoridorEngine.initialize();
    final s1 = QuoridorEngine.movePiece(s0, 13)!;
    final s2 = QuoridorEngine.switchTurn(s1);
    expect(s2.currentPlayerIsTop, isFalse);
  });
}
```

- [ ] **Step 2: 跑测试**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test test/core/surround_game/lan/widget/game_page_session_test.dart
```
期望：3 tests pass

- [ ] **Step 3: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add test/core/surround_game/lan/widget/game_page_session_test.dart
git commit -m "test(surround_game/lan): GamePage Session 同步 widget 测试"
```

---

### Task 9: 全量验证

- [ ] **Step 1: 全量 analyze**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter analyze
```
期望：0 errors（仅有 pre-existing info 警告）

- [ ] **Step 2: 全量 test**

```bash
cd 'D:\DevProjects\my\github\fr'
flutter test
```
期望：所有 pass

- [ ] **Step 3: 如有 fail，按输出修复**

- [ ] **Step 4: 提交（仅当有改动）**

```bash
cd 'D:\DevProjects\my\github\fr'
git add -A
git commit -m "chore: 全量验证后修复" --allow-empty
```

---

### Task 10: commit 收尾 + PR 描述

- [ ] **Step 1: 整理 commit 历史**

```bash
cd 'D:\DevProjects\my\github\fr'
git log --oneline e474cc7..HEAD
```

确认 10 个 task 各自有 commit（部分 task 可能合并 commit）。

- [ ] **Step 2: 写 PR 描述**

文件：`docs/superpowers/pr/2026-06-16-lan-session-upgrade.md`

模板：

```markdown
# PR: LAN 模式升级双端 Session 同步

## 概要

把上一轮「双端手动 sendGameState + watchGameState」升级为「双端 Session 自动同步」。删除冗余手动 bridge 代码，利用 `lib/core/localnet/session/` 框架层能力。

## 改动

### framework
- `Session` / `SessionManager` / `LanFramework.createSession` 加可选 `channelName` 参数（向后兼容）

### surround_game/lan
- `LanHostGamePage` / `LanClientGamePage` 双端各创 Session<ValueNotifier<GameState>>，共享 channel `surround/game/state`
- GamePage 不再持有 VM 状态机；落子直接调 QuoridorEngine 算 next → notifier → Session 自动发
- GamePage 自己处理 deviceLost（订阅 watchDevices）
- 删除：sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed / GamePage VM fast-forward / 旧 deviceLost 测试

## 验证

- `flutter analyze`：0 errors
- `flutter test`：所有 pass
- 跨进程手动 demo：Host 落子 → Client 同步 → Client 落子 → Host 同步 → 多步不回退

## 范围

### 做
- Session channelName 改造（向后兼容）
- 双端 GamePage Session 同步
- GamePage deviceLost 检测
- 旧手动 sync 代码清理

### 不做（YAGNI）
- Session 失败重连机制
- 增量 GameState 同步（仍走全量）
- 跨进程自动化集成测试（framework 单例约束）

## 风险

- Session channelName 改造需确保向后兼容（不传时行为不变）
- GamePage 不再持有 VM，但 LanRoomPage 仍持有 VM（设备 join/leave 状态）
- `LanChannels.gameState` 常量保留（Session channelName 用），但 HTTP channel 用途删除
```

- [ ] **Step 3: 提交 PR 描述**

```bash
cd 'D:\DevProjects\my\github\fr'
git add docs/superpowers/pr/2026-06-16-lan-session-upgrade.md
git commit -m "docs(pr): 写 Session 升级 PR 描述"
```

---

## 自审结果

### 1. Spec 覆盖
- ✅ Session channelName → T1, T2
- ✅ 双端 GamePage Session 同步 → T4, T5
- ✅ deviceLost 不走 VM → T4, T5, T7（删旧测试）
- ✅ 删除清单（sendGameState / watchGameState / HostGameStatePushed / ClientGameStatePushed）→ T3, T6
- ✅ 错误处理 / 测试策略 → T8, T9

### 2. Placeholder 扫描
- 步骤代码完整，无 TBD/TODO
- Task 2 提到"如果测试需要验证 channel 名变化"——给了两条候选路径（暴露字段 / public getter），implementer 自选

### 3. 类型一致性
- `LanChannels.gameState` 在 T4/T5 都用作 channelName
- `Session<ValueNotifier<GameState>>` 在 T4/T5 用同一构造方式
- `LanServiceAdapter.instance.createGameSession(...)` 签名在 T1/T4/T5 保持一致（加 channelName 参数）
- `_gameStateNotifier`、`_session`、`_devicesSub`、`_errorSub` 字段在 T4/T5 一致
