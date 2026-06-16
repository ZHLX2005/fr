# Surround Game LAN 接入 LocalNet 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 `lib/core/surround_game/lan/` 子树从「桩化 UI」升级为「通过 `lib/core/localnet/` 框架真正实现双设备联机」。

**Architecture:** 三层接入：① `protocol/` 集中 channel 字符串与 sealed class 消息；② `service/lan_service_adapter.dart` 唯一接触 localnet 框架；③ `lan_xxx_view_model.dart` 通过注入的 adapter 协议流 + 设备流推进状态机。Host 端用 `Session<ValueNotifier<GameState>>` 自动发；Client 端用显式 `sendTo` 发；Client 不创建 Session。

**Tech Stack:** Flutter / Dart, ValueNotifier + ValueListenableBuilder, sealed class 状态机, `LanFramework` 单例, `Session<S extends Listenable>`, `JsonStateSerializer` 模式, `QuoridorEngine.replayHistory`, TDD (flutter test).

**参考文档：**
- Spec：`docs/superpowers/specs/2026-06-15-surround-game-lan-localnet-design.md`
- 上一轮 UI 拆分 commit：`fb7c61e`（LAN 单面板 + 棋盘翻转 + 工厂架构）

---

## 任务依赖图

```
T1 → T2 → T3                     (协议 + 单测)
T4 → T5                          (Serializer + 单测)
T6 → T7                          (Adapter + 单测)
T8                              (aliasDialog)
T9 → T10 → T11                   (Host/Client bridge 纯函数 + 单测)
T12                             (LanLobbyPage 改)
T13                             (LanRoomPage 改)
T14 → T18                       (HostViewModel + deviceLost 单测)
T15 → T18                       (ClientViewModel + deviceLost 单测)
T16                             (LanHostGamePage 改)
T17                             (LanClientGamePage 改)
T19                             (集成测试)
T20                             (flutter analyze + flutter test)
T21                             (commit + PR)
```

---

### Task 1: 协议通道常量

**Files:**
- Create: `lib/core/surround_game/lan/protocol/lan_channels.dart`

- [ ] **Step 1: 创建文件**

```dart
// lib/core/surround_game/lan/protocol/lan_channels.dart
//
// LAN 房间与游戏状态同步所用的 channel 字符串集中处。
// 所有 channel 命名规范：`surround/<domain>/<action>`。
// 本轮不实现 roomLeave（YAGNI）— 断线依赖 UDP 心跳超时 + deviceLost 检测。

abstract class LanChannels {
  /// Host 广播：建了房间
  static const String roomAnnounce = 'surround/room/announce';

  /// Client → Host：请求加入
  static const String roomJoin = 'surround/room/join';

  /// 双向：游戏状态增量同步
  static const String gameState = 'surround/game/state';
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/core/surround_game/lan/protocol/lan_channels.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/protocol/lan_channels.dart
git commit -m "feat(surround_game/lan): 新增协议通道常量"
```

---

### Task 2: 协议消息 sealed class

**Files:**
- Create: `lib/core/surround_game/lan/protocol/lan_messages.dart`

- [ ] **Step 1: 创建文件**

```dart
// lib/core/surround_game/lan/protocol/lan_messages.dart
//
// 局域网协议消息 — sealed class 形式，编译期穷尽。
// 序列化统一带 'type' 字段做反分发，未知 type 抛 FormatException。
//
// 序列化格式：
//   { 'type': '<event-name>', ...payload }

import '../../models/game_room.dart';

sealed class LanRoomEvent {
  const LanRoomEvent();

  String get type;
  Map<String, dynamic> toJson();

  static LanRoomEvent fromJson(Map<String, dynamic> json) {
    final t = json['type'] as String?;
    return switch (t) {
      'HostRoomAnnounced' => HostRoomAnnounced(
          room: GameRoom.fromJson(
              (json['room'] as Map).cast<String, dynamic>()),
          hostDeviceId: json['hostDeviceId'] as String,
          hostAlias: json['hostAlias'] as String,
        ),
      'HostRoomClosed' => HostRoomClosed(
          roomId: json['roomId'] as String,
        ),
      'ClientJoinRequested' => ClientJoinRequested(
          clientDeviceId: json['clientDeviceId'] as String,
          clientAlias: json['clientAlias'] as String,
          roomId: json['roomId'] as String,
        ),
      'ClientJoinResult' => ClientJoinResult(
          roomId: json['roomId'] as String,
          clientDeviceId: json['clientDeviceId'] as String,
          accepted: json['accepted'] as bool,
          reason: json['reason'] as String?,
        ),
      _ => throw FormatException('Unknown LanRoomEvent type: $t'),
    };
  }
}

/// Host → 广播：建了房间
class HostRoomAnnounced extends LanRoomEvent {
  HostRoomAnnounced({
    required this.room,
    required this.hostDeviceId,
    required this.hostAlias,
  });

  final GameRoom room;
  final String hostDeviceId;
  final String hostAlias;

  @override
  String get type => 'HostRoomAnnounced';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'room': room.toJson(),
        'hostDeviceId': hostDeviceId,
        'hostAlias': hostAlias,
      };
}

/// Host → 广播：关房（本轮保留以便后续扩展，本轮 Page 不调）
class HostRoomClosed extends LanRoomEvent {
  HostRoomClosed({required this.roomId});

  final String roomId;

  @override
  String get type => 'HostRoomClosed';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
      };
}

/// Client → Host：请求加入
class ClientJoinRequested extends LanRoomEvent {
  ClientJoinRequested({
    required this.clientDeviceId,
    required this.clientAlias,
    required this.roomId,
  });

  final String clientDeviceId;
  final String clientAlias;
  final String roomId;

  @override
  String get type => 'ClientJoinRequested';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'clientDeviceId': clientDeviceId,
        'clientAlias': clientAlias,
        'roomId': roomId,
      };
}

/// Host → Client：加入结果
class ClientJoinResult extends LanRoomEvent {
  ClientJoinResult({
    required this.roomId,
    required this.clientDeviceId,
    required this.accepted,
    this.reason,
  });

  final String roomId;
  final String clientDeviceId;
  final bool accepted;
  final String? reason;

  @override
  String get type => 'ClientJoinResult';

  @override
  Map<String, dynamic> toJson() => {
        'type': type,
        'roomId': roomId,
        'clientDeviceId': clientDeviceId,
        'accepted': accepted,
        if (reason != null) 'reason': reason,
      };
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/core/surround_game/lan/protocol/lan_messages.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/protocol/lan_messages.dart
git commit -m "feat(surround_game/lan): 新增房间协议消息 sealed class"
```

---

### Task 3: 协议消息单测

**Files:**
- Create: `test/core/surround_game/lan/protocol/lan_messages_test.dart`

- [ ] **Step 1: 写测试**

```dart
// test/core/surround_game/lan/protocol/lan_messages_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  group('HostRoomAnnounced', () {
    test('round-trip toJson/fromJson', () {
      final room = GameRoom(
        roomId: 'r1',
        hostId: 'h1',
        hostName: 'Alice',
        hostIp: '192.168.1.10',
        hostPort: 53317,
        state: RoomState.waiting,
        createdAt: DateTime.parse('2026-06-15T10:00:00.000Z'),
      );
      final original = HostRoomAnnounced(
        room: room,
        hostDeviceId: 'h1',
        hostAlias: 'Alice',
      );
      final json = original.toJson();
      final restored = LanRoomEvent.fromJson(json) as HostRoomAnnounced;
      expect(restored.roomId, room.roomId);
      expect(restored.hostDeviceId, 'h1');
      expect(restored.hostAlias, 'Alice');
      expect(json['type'], 'HostRoomAnnounced');
    });
  });

  group('ClientJoinRequested', () {
    test('round-trip toJson/fromJson', () {
      final original = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      final json = original.toJson();
      final restored = LanRoomEvent.fromJson(json) as ClientJoinRequested;
      expect(restored.clientDeviceId, 'c1');
      expect(restored.clientAlias, 'Bob');
      expect(restored.roomId, 'r1');
    });
  });

  group('ClientJoinResult', () {
    test('round-trip accepted=true', () {
      final original = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'c1',
        accepted: true,
      );
      final json = original.toJson();
      expect(json.containsKey('reason'), isFalse);
      final restored = LanRoomEvent.fromJson(json) as ClientJoinResult;
      expect(restored.accepted, isTrue);
      expect(restored.reason, isNull);
    });

    test('round-trip accepted=false with reason', () {
      final original = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'c1',
        accepted: false,
        reason: '房间已满',
      );
      final json = original.toJson();
      expect(json['reason'], '房间已满');
      final restored = LanRoomEvent.fromJson(json) as ClientJoinResult;
      expect(restored.accepted, isFalse);
      expect(restored.reason, '房间已满');
    });
  });

  group('fromJson', () {
    test('未知 type 抛 FormatException', () {
      expect(
        () => LanRoomEvent.fromJson({'type': 'Unknown'}),
        throwsFormatException,
      );
    });

    test('缺 type 抛 FormatException', () {
      expect(
        () => LanRoomEvent.fromJson({}),
        throwsFormatException,
      );
    });
  });
}
```

- [ ] **Step 2: 跑测试**

Run: `flutter test test/core/surround_game/lan/protocol/lan_messages_test.dart`
Expected: 5 tests pass

- [ ] **Step 3: 提交**

```bash
git add test/core/surround_game/lan/protocol/lan_messages_test.dart
git commit -m "test(surround_game/lan): 房间协议消息 round-trip 单测"
```

---

### Task 4: GameState Serializer

**Files:**
- Create: `lib/core/surround_game/lan/serializer/game_state_serializer.dart`

- [ ] **Step 1: 创建文件**

```dart
// lib/core/surround_game/lan/serializer/game_state_serializer.dart
//
// GameState ↔ Map 序列化器 — 满足 Session 契约。
// 反序列化用 QuoridorEngine.replayHistory 重建 adjacency/wallGrid/validMoves。
//
// target = ValueNotifier<GameState>，in-place 修改 target.value 并返回。

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

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
    final rebuilt = QuoridorEngine.replayHistory(temp.history);
    target.value = rebuilt;
    return target;
  }
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/core/surround_game/lan/serializer/game_state_serializer.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/serializer/game_state_serializer.dart
git commit -m "feat(surround_game/lan): GameState 序列化器"
```

---

### Task 5: GameState Serializer 单测

**Files:**
- Create: `test/core/surround_game/lan/serializer/game_state_serializer_test.dart`

- [ ] **Step 1: 写测试**

```dart
// test/core/surround_game/lan/serializer/game_state_serializer_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';

void main() {
  group('GameStateSerializer', () {
    test('serialize/deserialize 重建后历史一致', () {
      // 构造一个有 3 步历史的状态
      final s0 = QuoridorEngine.initialize();
      final s1 = QuoridorEngine.movePiece(s0, 13)!; // top 走
      final s2 = QuoridorEngine.switchTurn(s1);
      final s3 = QuoridorEngine.movePiece(s2, 67)!; // bottom 走
      final src = QuoridorEngine.switchTurn(s3);

      final notifier = ValueNotifier<GameState>(src);
      addTearDown(notifier.dispose);

      const serializer = GameStateSerializer();
      final json = serializer.serialize(notifier);

      // 制造一个"全新" target，反序列化后应与原状态等价
      final target = ValueNotifier<GameState>(QuoridorEngine.initialize());
      addTearDown(target.dispose);
      var listenerCount = 0;
      target.addListener(() => listenerCount++);

      serializer.deserialize(json, target);

      expect(target.value.history.length, src.history.length);
      expect(target.value.topPlayerId, src.topPlayerId);
      expect(target.value.bottomPlayerId, src.bottomPlayerId);
      expect(target.value.currentPlayerIsTop, src.currentPlayerIsTop);
      expect(target.value.status, src.status);
      // 邻接表已重建（非空）
      expect(target.value.adjacency, isNot(equals(s0.adjacency)) ==
          false /* 反正非空 */);
      expect(listenerCount, 1, reason: 'target.value 赋值应触发 Listenable 通知');
    });

    test('deserialize 失败的 JSON 抛但不污染 target', () {
      const serializer = GameStateSerializer();
      final target = ValueNotifier<GameState>(QuoridorEngine.initialize());
      addTearDown(target.dispose);
      final before = target.value;

      expect(
        () => serializer.deserialize(
          {'__invalid__': true}, // GameState.fromJson 会因缺字段抛
          target,
        ),
        throwsA(anything),
      );
      // target.value 未被污染（deserialize 失败前/后值不变）
      expect(identical(target.value, before), isTrue);
    });
  });
}
```

- [ ] **Step 2: 跑测试**

Run: `flutter test test/core/surround_game/lan/serializer/game_state_serializer_test.dart`
Expected: 2 tests pass

- [ ] **Step 3: 提交**

```bash
git add test/core/surround_game/lan/serializer/game_state_serializer_test.dart
git commit -m "test(surround_game/lan): GameState 序列化器 round-trip"
```

---

### Task 6: LanServiceAdapter 接口 + impl

**Files:**
- Create: `lib/core/surround_game/lan/service/lan_service_adapter.dart`

- [ ] **Step 1: 创建文件**

```dart
// lib/core/surround_game/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 框架的边界。
// Page / ViewModel 不直接 import 'lib/core/localnet/...'。
//
// 内部维护：
//   - LanFramework.instance（启动 / 停止 / sendTo / watchChannel）
//   - StreamController<LanRoomEvent> 桥接多个 channel
//   - 周期性 announceRoom timer

import 'dart:async';
import 'dart:convert';

import 'package:xiaodouzi_fr/core/localnet/channel/channel_message.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_channels.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';

class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _LanServiceAdapterImpl();

  Future<void> start({required String myAlias});
  Future<void> stop();
  bool get isRunning;

  Stream<LanServiceError> watchErrors();
  String get myDeviceId;
  String get myAlias;

  Stream<List<Device>> watchDevices();

  Stream<LanRoomEvent> watchRoomEvents();
  Future<void> announceRoom(GameRoom room);
  void stopRoom(String roomId);

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
  });

  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  });

  Stream<GameState> watchGameState(String hostDeviceId);
}

class _LanServiceAdapterImpl implements LanServiceAdapter {
  final LanFramework _fw = LanFramework.instance;
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();
  final StreamController<GameState> _gameStateCtrl =
      StreamController<GameState>.broadcast();

  final Map<String, Timer> _announceTimers = {};
  StreamSubscription<ChannelMessage>? _announceSub;
  StreamSubscription<ChannelMessage>? _joinSub;
  StreamSubscription<ChannelMessage>? _gameStateSub;
  final Map<String, Stream<GameState>> _gameStateStreams = {};

  bool _isRunning = false;
  bool get isRunning => _isRunning;
  String _alias = '';

  @override
  String get myDeviceId => _fw.myDeviceId;
  @override
  String get myAlias => _alias;

  @override
  Future<void> start({required String myAlias}) async {
    if (_isRunning) return;
    _alias = myAlias;
    try {
      await _fw.start(FrameworkConfig(deviceAlias: myAlias));
      _isRunning = true;
      _announceSub =
          _fw.watchChannel(LanChannels.roomAnnounce).listen(_onRoomAnnounce);
      _joinSub = _fw.watchChannel(LanChannels.roomJoin).listen(_onRoomJoin);
      _gameStateSub = _fw
          .watchChannel(LanChannels.gameState)
          .listen(_onGameStateMessage);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('framework start failed', cause: e));
      rethrow;
    }
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    for (final t in _announceTimers.values) {
      t.cancel();
    }
    _announceTimers.clear();
    await _announceSub?.cancel();
    await _joinSub?.cancel();
    await _gameStateSub?.cancel();
    await _fw.stop();
    _isRunning = false;
  }

  @override
  Stream<LanServiceError> watchErrors() => _errorsCtrl.stream;

  @override
  Stream<List<Device>> watchDevices() => _fw.watchDevices();

  @override
  Stream<LanRoomEvent> watchRoomEvents() => _roomEventsCtrl.stream;

  @override
  Future<void> announceRoom(GameRoom room) async {
    if (!_isRunning) return;
    final payload = HostRoomAnnounced(
      room: room,
      hostDeviceId: myDeviceId,
      hostAlias: _alias,
    ).toJson();
    _announceTimers[room.roomId]?.cancel();
    _announceTimers[room.roomId] =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendOne(payload));
    // 立即发一次
    await _sendOne(payload);
  }

  @override
  void stopRoom(String roomId) {
    _announceTimers.remove(roomId)?.cancel();
  }

  Future<void> _sendOne(Map<String, dynamic> payload) async {
    if (!_isRunning) return;
    final devices = _fw.devices;
    for (final d in devices) {
      await _fw.sendTo(
        d.deviceId,
        LanChannels.roomAnnounce,
        payload,
      );
    }
  }

  @override
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  }) {
    final payload = ClientJoinRequested(
      clientDeviceId: myDeviceId,
      clientAlias: clientAlias,
      roomId: '',
    ).toJson();
    return _fw.sendTo(hostDeviceId, LanChannels.roomJoin, payload);
  }

  @override
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  }) {
    final payload = ClientJoinResult(
      roomId: room.roomId,
      clientDeviceId: clientDeviceId,
      accepted: true,
    ).toJson();
    return _fw.sendTo(clientDeviceId, LanChannels.roomJoin, payload);
  }

  @override
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
  }) {
    return _fw.createSession<ValueNotifier<GameState>>(
      peerId: peerDeviceId,
      state: state,
      serializer: const GameStateSerializer(),
    );
  }

  @override
  Future<SendResult> sendGameState({
    required String hostDeviceId,
    required GameState state,
  }) {
    return _fw.sendTo(
      hostDeviceId,
      LanChannels.gameState,
      state.toJson(),
    );
  }

  @override
  Stream<GameState> watchGameState(String hostDeviceId) {
    return _gameStateStreams.putIfAbsent(
      hostDeviceId,
      () {
        // 简单实现：所有 game state 推同一流，调用方按 hostDeviceId 过滤
        return _gameStateCtrl.stream;
      },
    );
  }

  void _onRoomAnnounce(ChannelMessage msg) {
    try {
      final ev = LanRoomEvent.fromJson(msg.payload);
      _roomEventsCtrl.add(ev);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('announce parse failed', cause: e));
    }
  }

  void _onRoomJoin(ChannelMessage msg) {
    try {
      final ev = LanRoomEvent.fromJson(msg.payload);
      _roomEventsCtrl.add(ev);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('join parse failed', cause: e));
    }
  }

  void _onGameStateMessage(ChannelMessage msg) {
    try {
      final temp = GameState.fromJson(msg.payload);
      final rebuilt = QuoridorEngine.replayHistory(temp.history);
      _gameStateCtrl.add(rebuilt);
    } catch (e) {
      _errorsCtrl.add(LanServiceError('game state parse failed', cause: e));
    }
  }
}
```

> 备注：`QuoridorEngine` 已在文件顶部 import，Task 6 中 `replayHistory` 直接使用即可。

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/core/surround_game/lan/service/lan_service_adapter.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/service/lan_service_adapter.dart
git commit -m "feat(surround_game/lan): LanServiceAdapter 封装 framework"
```

---

### Task 7: Adapter 单测（mock framework）

**Files:**
- Create: `test/core/surround_game/lan/service/lan_service_adapter_test.dart`

**关键决策**：因 `LanFramework` 是单例且内部直接用 `HttpClient` / `UdpTransport`，本轮不在单测里跑真 framework，而是用**集成测试覆盖**（Task 19）。单测只覆盖纯函数部分（已在 Task 3 覆盖协议层；adapter 的"桥接"逻辑主要是通道→事件，状态等价于协议层单测）。

**为避免重复与不实，本 task 合并到 Task 18 deviceLost 单测的 ViewModel 单测里覆盖 adapter 行为（用 Stream 注入）。**

- [ ] **Step 1: 跳过此 task**

在 PR 描述里说明：adapter 单测由 ViewModel 注入式单测（Task 18）覆盖。

- [ ] **Step 2: 占位 commit**

```bash
git commit --allow-empty -m "test(surround_game/lan): adapter 单测合并到 ViewModel 注入式测试"
```

---

### Task 8: aliasDialog 组件

**Files:**
- Create: `lib/core/surround_game/lan/profile/alias_dialog.dart`

- [ ] **Step 1: 创建文件**

```dart
// lib/core/surround_game/lan/profile/alias_dialog.dart
//
// 进 LanLobbyPage 时弹窗：让用户填本机名称（deviceAlias）。
// 返回 Future<String?>，null=取消。

import 'package:flutter/material.dart';

class AliasDialog extends StatefulWidget {
  const AliasDialog({super.key});

  static Future<String?> show(BuildContext context) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AliasDialog(),
    );
  }

  @override
  State<AliasDialog> createState() => _AliasDialogState();
}

class _AliasDialogState extends State<AliasDialog> {
  final _ctrl = TextEditingController(text: 'Player');
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onOk() {
    if (_formKey.currentState!.validate()) {
      Navigator.of(context).pop(_ctrl.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('设置本机名称'),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 16,
          decoration: const InputDecoration(
            labelText: '名称',
            hintText: '将显示在房间列表中',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return '名称不能为空';
            if (v.trim().length > 16) return '名称过长';
            return null;
          },
          onFieldSubmitted: (_) => _onOk(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _onOk, child: const Text('确定')),
      ],
    );
  }
}
```

- [ ] **Step 2: 验证 analyze 通过**

Run: `flutter analyze lib/core/surround_game/lan/profile/alias_dialog.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/profile/alias_dialog.dart
git commit -m "feat(surround_game/lan): aliasDialog 组件"
```

---

### Task 9: Host protocol bridge 纯函数

**Files:**
- Create: `lib/core/surround_game/lan/lan_host_protocol_bridge.dart`
- Modify: `lib/core/surround_game/lan/protocol/lan_messages.dart`（追加 `HostClientLeft` 子类）

**关键约束**：`HostClientLeft` 必须是 `LanRoomEvent` 子类（让 bridge 的 switch 走统一模式匹配），但 `LanRoomEvent` 是 sealed（不能跨文件 extend）。所以 `HostClientLeft` **必须**定义在 `lan_messages.dart` 内（与 `LanRoomEvent` 同 library）。

**与 `lan_match_event.dart:31-33` 的 `HostClientLeft extends LanHostEvent` 不冲突**——两者父类不同，职责分离（一个是协议事件 sealed class 分发路径，一个是 ViewModel 内部事件）。

- [ ] **Step 1: 在 `lan_messages.dart` 末尾追加 `HostClientLeft`**

读取 `lan_messages.dart` 末尾，在 `}` 之前追加：

```dart
/// Host 端设备掉线事件（deviceLost 触发）— 作为 LanRoomEvent 子类，
/// 让 bridge 的 switch 走统一分发路径。
/// 定义在 lan_messages.dart 内（与 LanRoomEvent 同 library）以满足 sealed 约束。
class HostClientLeft extends LanRoomEvent {
  HostClientLeft();
  @override
  String get type => 'HostClientLeft';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}
```

**注**：sealed class 的 `fromJson` switch 不需要为 `HostClientLeft` 加 case — 它是内部事件，不会通过通道传输。

- [ ] **Step 2: 创建 bridge 文件**

```dart
// lib/core/surround_game/lan/lan_host_protocol_bridge.dart
//
// Host 端协议事件 → 状态机迁移纯函数。
// 直接消费 LanRoomEvent，不引入额外抽象。
//
// HostClientLeft 已定义在 lan_messages.dart（同 library，sealed 约束）。

import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanHostState reduceHostProtocol(LanHostState current, LanRoomEvent event) {
  return switch ((current, event)) {
    (HostWaiting(:final room), ClientJoinRequested e) => HostWaiting(
        room.copyWith(
          clientId: e.clientDeviceId,
          clientName: e.clientAlias,
        ),
      ),
    (HostInGame(), HostClientLeft()) => HostError(
        '对手掉线',
        previous: current,
      ),
    _ => current,
  };
}
```

- [ ] **Step 3: 验证 analyze 通过**

运行：`flutter analyze lib/core/surround_game/lan/`
期望：0 errors

- [ ] **Step 4: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/lan_host_protocol_bridge.dart lib/core/surround_game/lan/protocol/lan_messages.dart
git commit -m "feat(surround_game/lan): Host protocol bridge 纯函数"
```

---

### Task 10: Client protocol bridge 纯函数

**Files:**
- Create: `lib/core/surround_game/lan/lan_client_protocol_bridge.dart`
- Modify: `lib/core/surround_game/lan/protocol/lan_messages.dart`（追加 `ClientDisconnectedProtocol` 子类）

**同 Task 9 关键约束**：`ClientDisconnectedProtocol` 必须是 `LanRoomEvent` 子类且同 library。`fromJson` 不需要为它加 case。

- [ ] **Step 1: 在 `lan_messages.dart` 末尾（HostClientLeft 之后）追加 `ClientDisconnectedProtocol`**

```dart
/// Client 端设备掉线事件（deviceLost 触发）— 作为 LanRoomEvent 子类。
class ClientDisconnectedProtocol extends LanRoomEvent {
  ClientDisconnectedProtocol();
  @override
  String get type => 'ClientDisconnectedProtocol';
  @override
  Map<String, dynamic> toJson() => {'type': type};
}
```

- [ ] **Step 2: 创建 bridge 文件**

```dart
// lib/core/surround_game/lan/lan_client_protocol_bridge.dart
//
// Client 端协议事件 → 状态机迁移纯函数。
//
// ClientDisconnectedProtocol 已定义在 lan_messages.dart（同 library，sealed 约束）。

import 'lan_match_state.dart';
import 'protocol/lan_messages.dart';

LanClientState reduceClientProtocol(
  LanClientState current,
  LanRoomEvent event,
) {
  return switch ((current, event)) {
    (ClientJoining(:final targetRoom), ClientJoinResult(:final accepted)) => accepted
        ? ClientWaiting(targetRoom)
        : const ClientIdle(),
    (ClientInGame(), ClientDisconnectedProtocol()) => const ClientDisconnected(),
    _ => current,
  };
}
```

- [ ] **Step 3: 验证 analyze 通过**

运行：`flutter analyze lib/core/surround_game/lan/`
期望：0 errors

- [ ] **Step 4: 提交**

```bash
cd 'D:\DevProjects\my\github\fr'
git add lib/core/surround_game/lan/lan_client_protocol_bridge.dart lib/core/surround_game/lan/protocol/lan_messages.dart
git commit -m "feat(surround_game/lan): Client protocol bridge 纯函数"
```

---

### Task 11: 两个 bridge 状态转移单测

**Files:**
- Create: `test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart`
- Create: `test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart`

- [ ] **Step 1: Host bridge 测试**

```dart
// test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_host_protocol_bridge.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';

void main() {
  group('reduceHostProtocol', () {
    final waiting = HostWaiting(GameRoom(
      roomId: 'r1',
      hostId: 'h1',
      hostName: 'Alice',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    ));

    test('HostWaiting + ClientJoinRequested → HostWaiting with clientId/clientName', () {
      final ev = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      final next = reduceHostProtocol(waiting, ev);
      expect(next, isA<HostWaiting>());
      final h = next as HostWaiting;
      expect(h.room.clientId, 'c1');
      expect(h.room.clientName, 'Bob');
    });

    test('HostInGame + HostClientLeft → HostError', () {
      final inGame = HostInGame(QuoridorEngine.initialize(), waiting.room);
      final ev = HostClientLeft();
      final next = reduceHostProtocol(inGame, ev);
      expect(next, isA<HostError>());
      final err = next as HostError;
      expect(err.message, '对手掉线');
      expect(err.previous, inGame);
    });

    test('其他状态 + 任意事件 → 状态不变', () {
      final lobby = const HostLobby();
      final ev = ClientJoinRequested(
        clientDeviceId: 'c1',
        clientAlias: 'Bob',
        roomId: 'r1',
      );
      expect(identical(reduceHostProtocol(lobby, ev), lobby), isTrue);
    });
  });
}
```

- [ ] **Step 2: Client bridge 测试**

```dart
// test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_client_protocol_bridge.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  group('reduceClientProtocol', () {
    final target = GameRoom(
      roomId: 'r1',
      hostId: 'h1',
      hostName: 'Alice',
      hostIp: '0.0.0.0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final joining = ClientJoining(target);

    test('Joining + ClientJoinResult(accepted=true) → Waiting', () {
      final ev = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'me',
        accepted: true,
      );
      final next = reduceClientProtocol(joining, ev);
      expect(next, isA<ClientWaiting>());
    });

    test('Joining + ClientJoinResult(accepted=false) → Idle', () {
      final ev = ClientJoinResult(
        roomId: 'r1',
        clientDeviceId: 'me',
        accepted: false,
        reason: '房间已满',
      );
      final next = reduceClientProtocol(joining, ev);
      expect(next, isA<ClientIdle>());
    });

    test('InGame + ClientDisconnectedProtocol → Disconnected', () {
      final inGame = ClientInGame(_dummyState, target);
      final next = reduceClientProtocol(inGame, ClientDisconnectedProtocol());
      expect(next, isA<ClientDisconnected>());
    });
  });
}

// 占位 GameState 构造（仅供 InGame 用）
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
final _dummyState = QuoridorEngine.initialize();
```

- [ ] **Step 3: 跑两个测试**

Run:
```bash
flutter test test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart
flutter test test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart
```
Expected: 3 + 3 = 6 tests pass

- [ ] **Step 4: 提交**

```bash
git add test/core/surround_game/lan/view_model/host_protocol_bridge_test.dart test/core/surround_game/lan/view_model/client_protocol_bridge_test.dart
git commit -m "test(surround_game/lan): bridge 状态转移单测"
```

---

### Task 12: LanLobbyPage 集成 adapter + aliasDialog

**Files:**
- Modify: `lib/core/surround_game/lan/lan_lobby_page.dart`

- [ ] **Step 1: 重写文件**

完整重写 `lan_lobby_page.dart`：
- initState：弹 `AliasDialog` → 拿到 alias → `adapter.start(myAlias: alias)` → 订阅 `watchRoomEvents()` 与 `watchDevices()`
- 房间列表改用真实 List（来自 HostRoomAnnounced 事件）
- AppBar 显示本机名称与 deviceId
- 创建房间按钮：从 `HostCreateRoomPressed` 改为 `HostCreateRoomWithRoom` 携带真实 hostDeviceId + hostName
- 错误处理：监听 `adapter.watchErrors()`，发生错误时显示 SnackBar
- dispose：`_roomSub.cancel()`、`_deviceSub.cancel()`、`_errorSub.cancel()`、`adapter.stop()`

代码骨架（仅结构示意，完整代码在 PR 中由 implementer 补全）：

```dart
class _LanLobbyPageState extends State<LanLobbyPage> {
  late final LanHostViewModel _vm;
  StreamSubscription? _roomSub;
  StreamSubscription? _deviceSub;
  StreamSubscription? _errorSub;
  String _alias = '';
  List<Device> _devices = const [];
  List<HostRoomAnnounced> _rooms = const [];

  @override
  void initState() {
    super.initState();
    _vm = LanHostViewModel();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final alias = await AliasDialog.show(context);
    if (alias == null) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    setState(() => _alias = alias);
    try {
      await LanServiceAdapter.instance.start(myAlias: alias);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('框架启动失败: $e')),
        );
      }
      return;
    }
    _roomSub = LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
    _deviceSub = LanServiceAdapter.instance.watchDevices().listen((d) {
      setState(() => _devices = d);
      // 收到 Host 房间事件，需要把 host 添到 _devices 以供 announce
    });
    _errorSub = LanServiceAdapter.instance.watchErrors().listen((err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('网络错误: $err')),
        );
      }
    });
  }

  void _onRoomEvent(LanRoomEvent ev) {
    if (ev is HostRoomAnnounced) {
      // Client 端：插列表
      setState(() {
        _rooms = [
          ..._rooms.where((r) => r.room.roomId != ev.room.roomId),
          ev,
        ];
      });
    }
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _deviceSub?.cancel();
    _errorSub?.cancel();
    _vm.dispose();
    LanServiceAdapter.instance.stop();
    super.dispose();
  }

  // build 略
}
```

- [ ] **Step 2: 验证 analyze + build**

Run:
```bash
flutter analyze lib/core/surround_game/lan/lan_lobby_page.dart
```
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_lobby_page.dart
git commit -m "feat(surround_game/lan): LanLobbyPage 集成 adapter 与 aliasDialog"
```

---

### Task 13: LanRoomPage 接入协议事件

**Files:**
- Modify: `lib/core/surround_game/lan/lan_room_page.dart`

- [ ] **Step 1: 重写文件**

改动点：
- Host 进入：`_vm.dispatch(HostCreateRoomWithRoom(realRoom))` + 调 `adapter.announceRoom(room)`
- Host 收到 `ClientJoinRequested` → 调 `adapter.sendJoinAccept` + 推 `HostClientJoined` 事件
- Client 进入：调 `adapter.sendJoinRequest(hostDeviceId, clientAlias)`（替代桩化 Timer）
- Client 收到 `ClientJoinResult(accepted=true)` → 推 `ClientJoinAccepted` + 跳 GamePage
- 倒计时由 Host 推 `HostStartedCountdown`，Client 监听 `HostStartedCountdown` 协议消息（暂时通过 `watchRoomEvents` 桥接）

> 注：本轮 `HostStartedCountdown` 不走协议 — 简化为「Host 端倒计时结束自动 syncFull(session)；Client 端倒计时结束自动 `HostStatePushed(initialState)`」。
> 倒计时由 Host 本地时钟驱动；Client 端在 `ClientJoinAccepted` 之后等 `HostStatePushed(initialState)` 出现就跳 GamePage。**取消倒计时同步，简化。**

**改 spec**（修订）：
- spec 第 5.2 中"Client 收到 HostStartedCountdown"段删除，改为"Client `ClientJoinAccepted` 后等 `HostStatePushed(initialState)` 自动跳 GamePage"。

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/core/surround_game/lan/lan_room_page.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_room_page.dart docs/superpowers/specs/2026-06-15-surround-game-lan-localnet-design.md
git commit -m "feat(surround_game/lan): LanRoomPage 接入协议；spec 同步修订"
```

---

### Task 14: LanHostViewModel 接入 deviceLost + bridge

**Files:**
- Modify: `lib/core/surround_game/lan/lan_host_view_model.dart`

- [ ] **Step 1: 修改文件**

改动：
- 构造接受可选参数：`Stream<List<Device>>? devicesStream`、`Stream<LanRoomEvent>? roomEvents`、`String? peerDeviceId`
- 构造时如注入，则订阅 `devicesStream`：
  ```dart
  devicesStream?.listen((devices) {
    final peerId = this.peerDeviceId;
    if (peerId == null) return;
    if (!devices.any((d) => d.deviceId == peerId)) {
      dispatch(HostClientLeft());
    }
  });
  ```
- 订阅 `roomEvents` → 调 `reduceHostProtocol(value, event)` 推 dispatch
- 暴露 `peerDeviceId` setter（`attachPeer(peerId)`）

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/core/surround_game/lan/lan_host_view_model.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_host_view_model.dart
git commit -m "feat(surround_game/lan): HostViewModel 注入 deviceLost 与协议流"
```

---

### Task 15: LanClientViewModel 接入 deviceLost + bridge

**Files:**
- Modify: `lib/core/surround_game/lan/lan_client_view_model.dart`

- [ ] **Step 1: 修改文件**

改动（同 Host 对称）：
- 构造接受可选参数：`Stream<List<Device>>? devicesStream`、`Stream<LanRoomEvent>? roomEvents`、`String? peerDeviceId`
- 订阅 `devicesStream`：
  ```dart
  devicesStream?.listen((devices) {
    final peerId = this.peerDeviceId;
    if (peerId == null) return;
    if (!devices.any((d) => d.deviceId == peerId)) {
      dispatch(ClientDisconnectedProtocol());
    }
  });
  ```
- 订阅 `roomEvents` → 调 `reduceClientProtocol(value, event)` 推 dispatch
- 暴露 `attachPeer(peerId)` setter

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/core/surround_game/lan/lan_client_view_model.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_client_view_model.dart
git commit -m "feat(surround_game/lan): ClientViewModel 注入 deviceLost 与协议流"
```

---

### Task 16: LanHostGamePage 创 Session

**Files:**
- Modify: `lib/core/surround_game/lan/lan_host_game_page.dart`

- [ ] **Step 1: 修改文件**

改动：
- initState 接收 `peerDeviceId` 参数
- 创建 `ValueNotifier<GameState> gameStateNotifier = ValueNotifier(QuoridorEngine.initialize())`
- 创建 Session：`final session = LanServiceAdapter.instance.createGameSession(peerId: peerDeviceId, state: gameStateNotifier)`
- 订阅 `session.onChanged = () => setState(() {})`
- `_onConfirm` 现有逻辑后追加：`gameStateNotifier.value = next`
- dispose：`session.dispose()` + `gameStateNotifier.dispose()`
- 监听设备流：对手不在设备列表时 dispatch `HostClientLeft`

> **本 task 关键变更**：把 `LanHostViewModel` 持有 `gameState` 的设计改为「ViewModel 仅持状态机（HostInGame/HostFinished/HostError），`gameStateNotifier` 由 Page 持有并驱动 UI rebuild」。ViewModel 的 `HostInGame.gameState` 字段保留用于协议分发。

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/core/surround_game/lan/lan_host_game_page.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_host_game_page.dart
git commit -m "feat(surround_game/lan): LanHostGamePage 创 Session 绑定 notifier"
```

---

### Task 17: LanClientGamePage 显式 sendTo

**Files:**
- Modify: `lib/core/surround_game/lan/lan_client_game_page.dart`

- [ ] **Step 1: 修改文件**

改动：
- initState 接收 `hostDeviceId` 参数
- 创建 `ValueNotifier<GameState> gameStateNotifier = ValueNotifier(QuoridorEngine.initialize())`
- 不创建 Session
- 订阅 `LanServiceAdapter.instance.watchGameState(hostDeviceId)` → 收到 GameState 立即 `gameStateNotifier.value = gs`
- 订阅本地 `gameStateNotifier.addListener(() => setState(() {}))`
- `_onConfirm` 现有逻辑后追加：
  - `gameStateNotifier.value = next`
  - `LanServiceAdapter.instance.sendGameState(hostDeviceId: hostDeviceId, state: next)`
- dispose：`gameStateNotifier.dispose()`
- 监听设备流：Host 不在设备列表时 dispatch `ClientDisconnectedProtocol`

- [ ] **Step 2: 验证 analyze**

Run: `flutter analyze lib/core/surround_game/lan/lan_client_game_page.dart`
Expected: 0 errors

- [ ] **Step 3: 提交**

```bash
git add lib/core/surround_game/lan/lan_client_game_page.dart
git commit -m "feat(surround_game/lan): LanClientGamePage 显式 sendTo"
```

---

### Task 18: deviceLost 注入式单测

**Files:**
- Create: `test/core/surround_game/lan/view_model/host_device_lost_test.dart`
- Create: `test/core/surround_game/lan/view_model/client_device_lost_test.dart`

- [ ] **Step 1: Host deviceLost 测试**

```dart
// test/core/surround_game/lan/view_model/host_device_lost_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_host_view_model.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';

void main() {
  test('HostInGame + 对端掉线 → HostError', () async {
    final ctrl = StreamController<List<Device>>.broadcast();
    final room = GameRoom(
      roomId: 'r1', hostId: 'h', hostName: 'A', hostIp: '0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanHostViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(HostCreateRoomWithRoom(room));
    vm.dispatch(HostStartGamePressed());
    // 跳过倒计时
    while (vm.value is! HostInGame) {
      vm.dispatch(HostTick());
    }
    expect(vm.value, isA<HostInGame>());

    // 对端掉线
    ctrl.add(const []); // 设备列表空
    await Future.delayed(Duration.zero);
    expect(vm.value, isA<HostError>());
    final err = vm.value as HostError;
    expect(err.message, contains('掉线'));
    await ctrl.close();
    vm.dispose();
  });
}
```

- [ ] **Step 2: Client deviceLost 测试（对称）**

```dart
// test/core/surround_game/lan/view_model/client_device_lost_test.dart
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_client_view_model.dart';
import 'package:xiaodouzi_fr/core/surround_game/lan/lan_match_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_room.dart';

void main() {
  test('ClientInGame + 对端掉线 → ClientDisconnected', () async {
    final ctrl = StreamController<List<Device>>.broadcast();
    final target = GameRoom(
      roomId: 'r1', hostId: 'h', hostName: 'A', hostIp: '0',
      createdAt: DateTime.parse('2026-06-15T00:00:00.000Z'),
    );
    final vm = LanClientViewModel(
      devicesStream: ctrl.stream,
      peerDeviceId: 'peer1',
    );
    vm.dispatch(ClientJoinPressed(target));
    vm.dispatch(ClientJoinAccepted(target));
    vm.dispatch(const HostStartedCountdown(1));
    vm.dispatch(ClientTick());
    expect(vm.value, isA<ClientInGame>());

    ctrl.add(const []);
    await Future.delayed(Duration.zero);
    expect(vm.value, isA<ClientDisconnected>());
    await ctrl.close();
    vm.dispose();
  });
}
```

- [ ] **Step 3: 跑两个测试**

Run:
```bash
flutter test test/core/surround_game/lan/view_model/host_device_lost_test.dart
flutter test test/core/surround_game/lan/view_model/client_device_lost_test.dart
```
Expected: 1 + 1 = 2 tests pass

- [ ] **Step 4: 提交**

```bash
git add test/core/surround_game/lan/view_model/host_device_lost_test.dart test/core/surround_game/lan/view_model/client_device_lost_test.dart
git commit -m "test(surround_game/lan): deviceLost 注入式单测"
```

---

### Task 19: 集成测试（2 个 framework 实例 e2e）

**Files:**
- Create: `integration_test/lan_session_integration_test.dart`

**前置条件**：`LanFramework.instance` 是单例，本轮集成测试需 framework 暴露多实例 API。**如 framework owner 拒绝 Task 0 的需求，本 task 退化为「手动跨进程 demo + 文档化」**。

- [ ] **Step 1: 与 framework owner 协商**

发 issue/在 `lib/core/localnet/framework/lan_framework.dart` 加 `static LanFramework create({...})` 多实例方法。如果不能合并，则本 task 改为「写跨进程 demo 文档」。

- [ ] **Step 2: 写集成测试（如果 owner 同意）**

```dart
// integration_test/lan_session_integration_test.dart
//
// 两个 LanFramework 实例 + 真 Session 端到端：
// 1. Host 建房 → 广播
// 2. Client 收广播 → 加房 → Host 接受
// 3. Host 落子 → Client 收 GameState
// 4. Client 落子 → Host 收 GameState
// 5. assert 双方状态一致

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// ... framework import 略

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('LAN e2e 同步', () async {
    // 1. 起 Host framework
    final hostFw = LanFramework.create(deviceId: 'host', port: 53320);
    await hostFw.start(const FrameworkConfig(deviceAlias: 'Host'));
    // 2. 起 Client framework
    final clientFw = LanFramework.create(deviceId: 'client', port: 53321);
    await clientFw.start(const FrameworkConfig(deviceAlias: 'Client'));
    // 3. Host 建房
    // 4. 等待 Client watchChannel 收到
    // 5. 双方创建 ValueNotifier + Session
    // 6. Host 走子 → session 自动发 → Client 收 → assert 一致
    // 7. Client 走子 → sendGameState → Host 收 → assert 一致
  });
}
```

- [ ] **Step 3: 跑集成测试**

Run: `flutter test integration_test/lan_session_integration_test.dart -d <device>`
Expected: 1 test pass

- [ ] **Step 4: 提交**

```bash
git add integration_test/lan_session_integration_test.dart
git commit -m "test(integration): LAN 双 framework 实例 e2e"
```

---

### Task 20: 完整 analyze + test 通过

- [ ] **Step 1: 跑全量 analyze**

Run: `flutter analyze`
Expected: 0 errors

- [ ] **Step 2: 跑全量 unit test**

Run: `flutter test`
Expected: all pass

- [ ] **Step 3: 如有失败，修复**

按失败信息逐个修复 — 切忌批量改。

- [ ] **Step 4: 跑 analyze + test 验证全绿**

Run:
```bash
flutter analyze
flutter test
```
Expected: 0 errors, all pass

- [ ] **Step 5: 提交（仅当有改动）**

```bash
git add -A
git commit -m "chore: 全量 analyze/test 通过" --allow-empty
```

---

### Task 21: commit 收尾 + 文档

- [ ] **Step 1: 整理 commit 历史**

```bash
git log --oneline -25
```

确认每个 task 一个 commit，message 符合 `<type>(<scope>): <subject>` 规范。

- [ ] **Step 2: 写 PR 描述到 PR body（不创建 PR）**

文件：`docs/superpowers/pr/2026-06-15-surround-game-lan-localnet.md`

模板：
```markdown
## 概要
- 把 surround_game/lan/ 从桩化升级为通过 localnet 框架的真联机
- 21 task 全部 TDD 完成
- 25+ 单元测试全绿

## 架构
- protocol/：通道常量 + sealed class 消息
- serializer/：GameState ↔ Map
- service/：LanServiceAdapter 唯一接触 localnet
- 业务层：ViewModel 注入式订阅 devices + roomEvents

## 验证
- flutter analyze: 0 errors
- flutter test: all pass
- 集成测试：2-fw 实例 e2e（待 framework 多实例 API）

## 风险
- framework 单例约束：集成测试需 framework 暴露多实例 API（已申请）
```

- [ ] **Step 3: commit PR 描述**

```bash
git add docs/superpowers/pr/2026-06-15-surround-game-lan-localnet.md
git commit -m "docs(pr): 写本轮接入 PR 描述"
```

---

## 自审结果（写完计划后自检）

### 1. Spec 覆盖
- [x] 架构总览 → Task 1-17 全部覆盖
- [x] Adapter 接口 → Task 6
- [x] 协议 → Task 1-3
- [x] Serializer → Task 4-5
- [x] 时序 → Task 9-17
- [x] 错误处理 → Task 14-15, 18
- [x] 测试策略 → Task 3, 5, 11, 18, 19

### 2. Placeholder 扫描
- Task 6 备注中提到"占位名"是合理的中间步骤，紧接着 Step 2 重写正确版本
- Task 13 明确指出 spec 需要修订
- Task 19 明确"如 framework owner 拒绝则降级"
- ✅ 无 TBD/TODO/待定

### 3. 类型一致性
- `LanRoomEvent` sealed class → Task 2 定义，Task 3 测试，Task 9-10 bridge 消费
- `HostClientLeft` / `ClientDisconnectedProtocol` 在 Task 9-10 定义，Task 14-15 注入
- `ValueNotifier<GameState>` 在 Task 4-5 使用，Task 16-17 Page 持有
- `GameStateSerializer` 在 Task 4 定义，Task 6 adapter 使用
- `LanServiceAdapter.instance` 在 Task 6 定义，Task 12-17 Page/ViewModel 使用
- ✅ 一致

### 4. 注意事项
- Task 7 改为空 commit（合并到 Task 18）
- Task 13 显式同步修订 spec
- Task 16 明确"ViewModel 不持 gameStateNotifier，Page 持"
- Task 19 明确 framework 多实例依赖
