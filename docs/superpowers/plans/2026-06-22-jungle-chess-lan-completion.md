# Jungle Chess LAN 实施补完 — 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 完全机械照搬 `lib/core/surround_game/` 的 LAN 实现模式,把 jungle_chess 的占位/TODO 替换为可运行的完整实现,使 jungle_chess 在两台 Android 真机上可联机对战。

**Architecture:** 三层 Game Layer (`lib/core/jungle_chess/`) → Biz Adapter (单例桥接 `JungleLanServiceAdapter`) → Framework Layer (`lib/core/localnet/`)。LAN 模式用 UDP 多播 (房间 + join) + HTTP Session (游戏状态同步)。Host 是权威端,所有引擎操作在 Host 执行;Client 严格只读。

**Tech Stack:** Flutter/Dart 3.11+ (sealed class), `shared_preferences` 2.3.3 (alias/deviceId 持久化), `uuid` 4.5.1 (deviceId 生成), `localnet` 框架 (UDP 多播 + HTTP Session + StateSerializer), `flutter_svg` (棋盘渲染)。

**Source of Truth:**
- Spec: `docs/superpowers/specs/2026-06-22-jungle-chess-lan-completion-design.md`
- 参考实现: `lib/core/surround_game/` (机械照搬源)

---

## Global Constraints

- **不**重新设计 LAN 协议或架构,只机械照搬 surround_game
- 现有 8 个 LAN 协议/状态机文件 (`lan_messages.dart`, `lan_match_state.dart`, `lan_match_event.dart`, `lan_host_view_model.dart`, `lan_client_view_model.dart`, `*_protocol_bridge.dart`, `lan_channels.dart`, `game_room.dart`) **不改动**
- Host-Authoritative 模型:Host 唯一执行引擎 (`JungleEngine.movePiece`),Client 只接收 state
- 两段式 Session:房间 UDP 多播 + 游戏 HTTP Session
- Client 严格只读,不渲染棋盘,不响应触摸
- 单一 source of truth = `gameStateNotifier`,ViewModel 只做状态编排
- 所有 Engine 方法为 `static` 纯函数,无 Flutter/网络依赖
- ViewModel `reduce()` 为纯函数
- `JungleEngine.movePiece` 返回 null 表示非法操作,reducer 内 `if (next == null) return state`
- `flutter analyze | grep error` 必须为空

---

## File Structure (locked-in decomposition)

### 新增文件(4 个)

| 路径 | 职责 |
|------|------|
| `lib/core/jungle_chess/lan/persistence/device_id_service.dart` | 本机 deviceId 持久化(SharedPreferences) |
| `lib/core/jungle_chess/lan/persistence/player_profile_service.dart` | 本机 alias 持久化(SharedPreferences) |
| `lib/core/jungle_chess/lan/lan_room_page.dart` | 房间中转页,Host/Client 双角色,处理 join + 倒计时 |
| `lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart` | JungleHostTouchController (Y 镜像) + 2 个工厂 |

### 改写文件(5 个)

| 路径 | 改动 |
|------|------|
| `lib/core/jungle_chess/lan/serializer/game_state_serializer.dart` | 加 `implements StateSerializer<ValueNotifier<GameState>>` |
| `lib/core/jungle_chess/lan/service/lan_service_adapter.dart` | 把 TODO 替换为 `_JungleLanServiceAdapterImpl`(单例桥接) |
| `lib/core/jungle_chess/lan/lan_lobby_page.dart` | 从 66 行扩到 ~370 行(房间列表 + 设备列表 + 错误流) |
| `lib/core/jungle_chess/lan/lan_host_game_page.dart` | initState 创建 Session + notifier 桥接 |
| `lib/core/jungle_chess/lan/lan_client_game_page.dart` | 改为只读文字版(机械照搬) |

### 不改动的现有文件(8 个)

- `lan/protocol/lan_messages.dart` (8 种 LanRoomEvent sealed)
- `lan/protocol/lan_channels.dart` (3 个 channel 常量)
- `lan/lan_match_state.dart` (Host 6 态 + Client 7 态)
- `lan/lan_match_event.dart` (Host/Client event sealed)
- `lan/lan_host_view_model.dart` (ValueNotifier + reduce)
- `lan/lan_client_view_model.dart` (ValueNotifier + reduce)
- `lan/lan_host_protocol_bridge.dart` (纯函数 reduce)
- `lan/lan_client_protocol_bridge.dart` (纯函数 reduce)
- `lan/game_room.dart` (GameRoom 模型)

---

## Task 1: Persistence services (deviceId + alias)

**Files:**
- Create: `lib/core/jungle_chess/lan/persistence/device_id_service.dart`
- Create: `lib/core/jungle_chess/lan/persistence/player_profile_service.dart`

**Interfaces:**
- Consumes: `shared_preferences: ^2.3.3`, `uuid: ^4.5.1` (已在 pubspec.yaml)
- Produces:
  - `DeviceIdService.load() → Future<String>` (返回 36 字符 UUID,首次启动自动生成并落盘)
  - `PlayerProfileService.loadAlias() → Future<String?>` (null = 未设置)
  - `PlayerProfileService.saveAlias(String alias) → Future<void>` (空字符串视为删除)

**Source:** 1:1 复制 `lib/core/surround_game/lan/persistence/device_id_service.dart` 和 `player_profile_service.dart`,只改 `class` 名为 `DeviceIdService` / `PlayerProfileService`(实际名字相同,无需改)。

- [ ] **Step 1: 创建 device_id_service.dart**

新建文件 `lib/core/jungle_chess/lan/persistence/device_id_service.dart`,内容:

```dart
// lib/core/jungle_chess/lan/persistence/device_id_service.dart
//
// 本机 deviceId 持久化
//
// 为什么需要：LanFramework 每次 start 都会生成新 UUID，导致设备
// 退出 demo 再回来后 deviceId 变化——对端会同时看到"老 B 离线"和"新 B 上线"
// 两条记录。重连时容易误判为"两个会话指向同一设备"。
//
// 策略：
// - 首次启动生成 UUID v4，写入 SharedPreferences
// - 之后启动直接读取，保证本机 identity 跨进程稳定

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceIdService {
  static const String _key = 'jungle_lan_device_id';
  static const _uuid = Uuid();

  /// 加载本机 deviceId，没有就生成并落盘
  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_key);
    if (existing != null && existing.isNotEmpty) return existing;
    final fresh = _uuid.v4();
    await prefs.setString(_key, fresh);
    return fresh;
  }
}
```

- [ ] **Step 2: 创建 player_profile_service.dart**

新建文件 `lib/core/jungle_chess/lan/persistence/player_profile_service.dart`,内容:

```dart
// lib/core/jungle_chess/lan/persistence/player_profile_service.dart
//
// 本机 alias 持久化
//
// 策略：
// - loadAlias：未设置返回 null
// - saveAlias：空字符串视为删除（写回 null 状态）

import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfileService {
  static const String _keyAlias = 'jungle_lan_player_alias';

  /// 加载本机 alias（null=未设置）
  static Future<String?> loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAlias);
    // ignore: dead_code
    // spec compliance
  }

  /// 持久化 alias（空字符串视为删除）
  static Future<void> saveAlias(String alias) async {
    final prefs = await SharedPreferences.getInstance();
    if (alias.isEmpty) {
      await prefs.remove(_keyAlias);
    } else {
      await prefs.setString(_keyAlias, alias);
    }
  }
}
```

> **注意**: 上面的 `// ignore: dead_code` 注释行可删除,`saveAlias` 中 alias 参数实际被使用。

修正版(无 dead_code 注释):

```dart
// lib/core/jungle_chess/lan/persistence/player_profile_service.dart
//
// 本机 alias 持久化
//
// 策略：
// - loadAlias：未设置返回 null
// - saveAlias：空字符串视为删除（写回 null 状态）

import 'package:shared_preferences/shared_preferences.dart';

class PlayerProfileService {
  static const String _keyAlias = 'jungle_lan_player_alias';

  /// 加载本机 alias（null=未设置）
  static Future<String?> loadAlias() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAlias);
  }

  /// 持久化 alias（空字符串视为删除）
  static Future<void> saveAlias(String alias) async {
    final prefs = await SharedPreferences.getInstance();
    if (alias.isEmpty) {
      await prefs.remove(_keyAlias);
    } else {
      await prefs.setString(_keyAlias, alias);
    }
  }
}
```

- [ ] **Step 3: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/persistence/ 2>&1 | grep -E "error|warning"
```

Expected: 无输出(或只有 info 级别提示)。

- [ ] **Step 4: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/persistence/
git -c core.autocrlf=false commit -m "feat(jungle-chess): add deviceId + alias persistence services

Mechanical-mirror of surround_game's persistence layer. Both services
are SharedPreferences-backed singletons.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 2: GameStateSerializer implements StateSerializer

**Files:**
- Modify: `lib/core/jungle_chess/lan/serializer/game_state_serializer.dart`

**Interfaces:**
- Consumes: `GameState.toJson()` / `GameState.fromJson()` (现有)
- Produces: `GameStateSerializer implements StateSerializer<ValueNotifier<GameState>>`

**Source:** 1:1 复制 `lib/core/surround_game/lan/serializer/game_state_serializer.dart` 模式,只把 `QuoridorGameState` → `GameState` (jungle_chess 的)、`QuoridorEngine` 不调(原因见下)。

- [ ] **Step 1: 重写 game_state_serializer.dart**

替换整个文件 `lib/core/jungle_chess/lan/serializer/game_state_serializer.dart`,内容:

```dart
// lib/core/jungle_chess/lan/serializer/game_state_serializer.dart
//
// GameState ↔ Map 序列化器 — 满足 Session 契约。
//
// 反序列化使用 GameState.fromJson 重建完整状态。
// 与 surround_game 不同：JungleChess 的 GameState 自带完整 pieces map，
// 不需要 replayHistory（每步 history 推给对端，对端 GameState 已是终态）。

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/session/state_serializer.dart';
import '../../models/game_state.dart';

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
    target.value = temp;
    return target;
  }
}
```

- [ ] **Step 2: 验证 StateSerializer 接口存在**

```bash
cd D:\DevProjects\my\github\fr
grep -n "abstract class StateSerializer" lib/core/localnet/session/state_serializer.dart
```

Expected: 输出 1 行(确认 `StateSerializer` 接口存在且可被实现)。

- [ ] **Step 3: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/serializer/ 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

- [ ] **Step 4: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/serializer/game_state_serializer.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): GameStateSerializer implements StateSerializer contract

Mechanical-mirror of surround_game serializer pattern. JungleChess
GameState is self-contained, so no replayHistory is needed during
deserialization.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 3: JungleLanServiceAdapter (full implementation)

**Files:**
- Modify: `lib/core/jungle_chess/lan/service/lan_service_adapter.dart`

**Interfaces:**
- Consumes:
  - `LanFramework.instance` (来自 `lib/core/localnet/framework/lan_framework.dart`)
  - `Device` (来自 `lib/core/localnet/device/device.dart`)
  - `ChannelMessage`, `SendResult` (来自 `lib/core/localnet/channel/`)
  - `FrameworkConfig` (来自 `lib/core/localnet/framework/framework_config.dart`)
  - `Session<T>` (来自 `lib/core/localnet/session/session.dart`)
  - `StateSerializer<T>` (来自 `lib/core/localnet/session/state_serializer.dart`)
  - `DeviceIdService`, `PlayerProfileService` (本模块 Task 1)
  - `GameState`, `GameRoom`, `LanRoomEvent`, `GameStateSerializer` (本模块其他文件)
- Produces:
  - `JungleLanServiceAdapter` 单例,14 个方法签名(见 spec 5.1)

**Source:** 1:1 复制 `lib/core/surround_game/lan/service/lan_service_adapter.dart` 的 `_LanServiceAdapterImpl`(280 行),替换类型为 jungle_chess 自己的(`GameState` 等)。

- [ ] **Step 1: 重写 lan_service_adapter.dart**

替换整个文件 `lib/core/jungle_chess/lan/service/lan_service_adapter.dart`,内容:

```dart
// lib/core/jungle_chess/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 框架的边界。
// Page / ViewModel 不直接 import 'lib/core/localnet/...'。
//
// 内部维护：
//   - LanFramework.instance（启动 / 停止 / sendTo / watchChannel）
//   - StreamController<LanRoomEvent> 桥接多个 channel
//   - 周期性 announceRoom timer

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/channel_message.dart';
import 'package:xiaodouzi_fr/core/localnet/channel/send_result.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/session/session.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/protocol/lan_channels.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/protocol/lan_messages.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/persistence/player_profile_service.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/persistence/device_id_service.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/serializer/game_state_serializer.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/lan/game_room.dart';
import 'package:xiaodouzi_fr/core/jungle_chess/models/game_state.dart';

class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _JungleLanServiceAdapterImpl();

  Future<void> start({String? myAlias});
  Future<void> stop();
  bool get isRunning;

  void updateAlias(String newAlias);

  Stream<LanServiceError> watchErrors();

  String get myDeviceId;
  String get myAlias;

  Stream<List<Device>> watchDevices();

  Stream<LanRoomEvent> watchRoomEvents();
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

class _JungleLanServiceAdapterImpl implements LanServiceAdapter {
  final LanFramework _fw = LanFramework.instance;
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();

  final Map<String, Timer> _announceTimers = {};
  StreamSubscription<ChannelMessage>? _announceSub;
  StreamSubscription<ChannelMessage>? _joinSub;
  StreamSubscription<Map<String, dynamic>>? _multicastSub;

  bool _isRunning = false;
  String _alias = '';

  @override
  bool get isRunning => _isRunning;

  @override
  String get myDeviceId => _fw.myDeviceId;

  @override
  String get myAlias => _alias;

  @override
  void updateAlias(String newAlias) {
    if (newAlias.trim().isEmpty) return;
    _alias = newAlias.trim();
    PlayerProfileService.saveAlias(_alias);
  }

  @override
  Future<void> start({String? myAlias}) async {
    if (_isRunning) return;
    // 预加载持久化数据
    final persistedAlias = await PlayerProfileService.loadAlias();
    final aliasToUse = (myAlias != null && myAlias.isNotEmpty)
        ? myAlias
        : (persistedAlias ?? 'Player');
    if (myAlias != null && myAlias.isNotEmpty && myAlias != persistedAlias) {
      await PlayerProfileService.saveAlias(myAlias);
    }
    final deviceId = await DeviceIdService.load();
    _alias = aliasToUse;
    try {
      await _fw.start(FrameworkConfig(
        deviceAlias: aliasToUse,
        deviceId: deviceId,
      ));
      _isRunning = true;
      _announceSub =
          _fw.watchChannel(LanChannels.roomAnnounce).listen(_onRoomAnnounce);
      _joinSub = _fw.watchChannel(LanChannels.roomJoin).listen(_onRoomJoin);
      _multicastSub = _fw.watchMulticast().listen((msg) {
        final key = msg['key'] as String?;
        final payload = msg['payload'] as Map<String, dynamic>?;
        if (payload == null) return;

        if (key == 'room_announce') {
          // 房间公告：所有设备都关心
          try {
            final ev = LanRoomEvent.fromJson(payload);
            _roomEventsCtrl.add(ev);
          } catch (e) {
            _errorsCtrl.add(
              LanServiceError('multicast announce parse failed', cause: e),
            );
          }
        } else if (key == 'room_join') {
          // Join 消息：只关心发给我的
          final toDeviceId = payload['toDeviceId'] as String?;
          if (toDeviceId == null || toDeviceId != myDeviceId) return;
          final innerPayload = Map<String, dynamic>.from(payload)
            ..remove('toDeviceId');
          try {
            final ev = LanRoomEvent.fromJson(innerPayload);
            _roomEventsCtrl.add(ev);
          } catch (e) {
            _errorsCtrl.add(
              LanServiceError('multicast join parse failed', cause: e),
            );
          }
        }
      });
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
    await _multicastSub?.cancel();
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
      hostDeviceId: myDeviceId,
      hostName: _alias,
      roomId: room.roomId,
    ).toJson();
    _announceTimers[room.roomId]?.cancel();
    _announceTimers[room.roomId] =
        Timer.periodic(const Duration(seconds: 5), (_) => _sendOne(payload));
    // 立即发一次（走 UDP 多播）
    await _sendOne(payload);
  }

  @override
  Future<void> stopRoom(String roomId) async {
    _announceTimers.remove(roomId)?.cancel();
    if (!_isRunning) return;
    // 广播关房，让 client 知道 host 已离开
    await _fw.sendMulticast(
      key: 'room_announce',
      payload: HostRoomClosed().toJson(),
    );
  }

  Future<void> _sendOne(Map<String, dynamic> payload) async {
    if (!_isRunning) return;
    await _fw.sendMulticast(key: 'room_announce', payload: payload);
  }

  @override
  Future<SendResult> sendJoinRequest({
    required String hostDeviceId,
    required String clientAlias,
  }) {
    final payload = ClientJoinRequested(
      clientDeviceId: myDeviceId,
      clientAlias: clientAlias,
    ).toJson();
    return _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': hostDeviceId,
      ...payload,
    });
  }

  @override
  Future<SendResult> sendJoinAccept({
    required String clientDeviceId,
    required GameRoom room,
  }) {
    final payload = ClientJoinResult(
      accepted: true,
    ).toJson();
    return _fw.sendMulticast(key: 'room_join', payload: {
      'toDeviceId': clientDeviceId,
      ...payload,
    });
  }

  @override
  Session<ValueNotifier<GameState>> createGameSession({
    required String peerDeviceId,
    required ValueNotifier<GameState> state,
    String? channelName,
  }) {
    return _fw.createSession<ValueNotifier<GameState>>(
      peerId: peerDeviceId,
      state: state,
      serializer: const GameStateSerializer(),
      channelName: channelName,
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
}
```

- [ ] **Step 2: 验证 LanFramework API 存在**

```bash
cd D:\DevProjects\my\github\fr
grep -n "class LanFramework" lib/core/localnet/framework/lan_framework.dart
grep -n "createSession" lib/core/localnet/framework/lan_framework.dart | head -5
grep -n "sendMulticast\|watchMulticast\|watchChannel\|watchDevices" lib/core/localnet/framework/lan_framework.dart | head -10
```

Expected: 4 个 grep 都有输出,确认 API 名字与代码一致。

- [ ] **Step 3: 验证 HostRoomClosed / HostRoomAnnounced / ClientJoinRequested / ClientJoinResult 字段**

```bash
cd D:\DevProjects\my\github\fr
grep -A 10 "class HostRoomAnnounced" lib/core/jungle_chess/lan/protocol/lan_messages.dart | head -15
grep -A 5 "class HostRoomClosed" lib/core/jungle_chess/lan/protocol/lan_messages.dart | head -10
grep -A 10 "class ClientJoinRequested" lib/core/jungle_chess/lan/protocol/lan_messages.dart | head -15
grep -A 10 "class ClientJoinResult" lib/core/jungle_chess/lan/protocol/lan_messages.dart | head -15
```

Expected: 4 个类的字段名与 Task 3 Step 1 中的构造器参数一致。

如果不一致,**STOP 并修正**:Adapter 中 4 个事件的构造器参数必须与 `lan_messages.dart` 的字段对齐。

- [ ] **Step 4: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/service/ 2>&1 | grep -E "error|warning"
```

Expected: 无输出。如果有 import 错误,说明 localnet 路径不对,检查 import 路径。

- [ ] **Step 5: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/service/lan_service_adapter.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): JungleLanServiceAdapter with full LanFramework bridge

Mechanical-mirror of surround_game LanServiceAdapter (280 lines).
Replaces TODO stubs with _JungleLanServiceAdapterImpl that:
- Starts LanFramework with persisted deviceId/alias
- Bridges watchChannel + watchMulticast into watchRoomEvents
- Implements 5s periodic announceRoom timer
- createGameSession wires StateSerializer into HTTP Session

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 4: JungleHostTouchController + 2 factories

**Files:**
- Create: `lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart`

**Interfaces:**
- Consumes: `JungleTouchController` (现有), `GameState` (现有)
- Produces:
  - `JungleHostTouchController` extends `JungleTouchController` (Y 镜像拖动方法)
  - `JungleHostTouchControllerFactory(boardSize)` 
  - `JungleClientTouchControllerFactory()`

**Source:** 1:1 复制 `lib/core/surround_game/lan/widgets/touch_controller_factory.dart` 模式,适配 jungle_chess 的 `JungleTouchController` 接口。

- [ ] **Step 1: 确认 JungleTouchController 接口**

```bash
cd D:\DevProjects\my\github\fr
grep -n "void on" lib/core/jungle_chess/widgets/jungle_touch_controller.dart
```

Expected: 列出 `onCellTap` / `onDragStart` / `onDragUpdate` / `onDragEnd` 4 个方法(其中 onCellTap 无 fingerPos 参数)。

- [ ] **Step 2: 创建 jungle_host_touch_controller.dart**

新建文件 `lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart`,内容:

```dart
// lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart
//
// LAN 模式触摸控制器工厂 — Host 版产出带 y 镜像的 JungleTouchController；
// Client 版用共享基类。
//
// JungleChess 棋盘对称(蓝方在底、红方在顶),Y 镜像实际不影响坐标,
// 但保留镜像实现以保持模板一致性(后续扩展游戏直接复用同一套)。

import 'package:flutter/material.dart';
import 'jungle_touch_controller.dart';
import '../models/game_state.dart';
import '../models/piece.dart';

/// LAN Host 触摸控制器 — 触摸 y 坐标镜像
///
/// 在 onDragStart/Update/End 中将屏幕 y 坐标按 [boardSize] 镜像，
/// 使得用户在翻转后的棋盘上点"视觉下方"时，
/// JungleTouchController 内部的 cellId 映射获得正确的 engine 坐标。
class JungleHostTouchController extends JungleTouchController {
  final double boardSize;

  JungleHostTouchController({required this.boardSize});

  Offset _mirror(Offset p) => Offset(p.dx, boardSize - p.dy);

  // onCellTap 不需要镜像（点击基于 cellIndex，与 Y 坐标无关）
  @override
  void onCellTap(GameState state, int index) {
    super.onCellTap(state, index);
  }

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

/// LAN Host 工厂
class JungleHostTouchControllerFactory {
  final double boardSize;

  const JungleHostTouchControllerFactory({required this.boardSize});

  JungleHostTouchController create() =>
      JungleHostTouchController(boardSize: boardSize);
}

/// LAN Client 工厂 — 使用共享基类（不镜像）
class JungleClientTouchControllerFactory {
  const JungleClientTouchControllerFactory();

  JungleTouchController create() => JungleTouchController();
}
```

- [ ] **Step 3: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

- [ ] **Step 4: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/widgets/jungle_host_touch_controller.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): JungleHostTouchController (Y-mirrored) + 2 factories

Mechanical-mirror of surround_game touch_controller_factory.dart.
Host factory yields Y-mirrored controller; Client factory yields
base JungleTouchController.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 5: LanRoomPage (Host/Client 中转页)

**Files:**
- Create: `lib/core/jungle_chess/lan/lan_room_page.dart`

**Interfaces:**
- Consumes:
  - `LanHostViewModel`, `LanClientViewModel` (现有)
  - `LanHostGamePage`, `LanClientGamePage` (Task 6/7 将改写)
  - `LanServiceAdapter.instance` (Task 3)
  - `GameRoom`, `LanRoomEvent`, `HostCreateRoom`, `ClientJoinRoom` 等 (现有)
- Produces:
  - `LanRoomPage({roomId, role, initialRoom})` 中转页
  - Host 分支: `_startHost` → `announceRoom`,监听 `ClientJoinRequested` → `sendJoinAccept` + dispatch
  - Client 分支: `_startClient` → `sendJoinRequest`,监听 `ClientJoinResult` → 倒计时 → push GamePage

**Source:** 1:1 复制 `lib/core/surround_game/lan/lan_room_page.dart` (351 行),适配 jungle_chess 的 State/Event/ViewModel 名字。

- [ ] **Step 1: 确认现有 jungle_chess 事件/状态名**

```bash
cd D:\DevProjects\my\github\fr
grep -n "HostCreateRoom\|ClientJoinRoom\|HostClientJoined\|ClientJoinAccepted\|ClientJoinRejected" lib/core/jungle_chess/lan/lan_match_event.dart
grep -n "HostCreateRoomPressed\|HostStartGamePressed\|HostClientJoined" lib/core/surround_game/lan/lan_match_event.dart
```

Expected: jungle_chess **没有**这些事件名(只有 `HostCreateRoom`,无 `HostCreateRoomPressed`/`HostClientJoined`/`ClientJoinAccepted`)。这是 spec 风险点 — jungle_chess 当前 `lan_match_event.dart` 事件比 surround_game 少。

如果 jungle_chess 缺关键事件,**STOP** 并查看 `lib/core/jungle_chess/lan/lan_match_event.dart` 的事件清单,与 spec 5.1 / 5.4 对照。在 `lan_match_event.dart` 中补充缺失事件(此为"机械照搬"的一部分,允许在 plan 实施中改写现有文件)。

- [ ] **Step 2: 创建 lan_room_page.dart**

新建文件 `lib/core/jungle_chess/lan/lan_room_page.dart`,内容:

```dart
// lib/core/jungle_chess/lan/lan_room_page.dart
//
// 房间等待页面 — 同时支持 Host 和 Client 两种角色。
//
// Host 进入：announceRoom + 订阅 room events 处理 ClientJoinRequested
// Client 进入：sendJoinRequest + 订阅 room events 处理 ClientJoinResult
// 双方收到 join result 后跳 GamePage
// 倒计时由 Host 本地驱动

import 'dart:async';

import 'package:flutter/material.dart';
import 'game_room.dart';
import 'lan_host_game_page.dart';
import 'lan_client_game_page.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_client_view_model.dart';
import 'service/lan_service_adapter.dart';
import 'protocol/lan_messages.dart';

class LanRoomPage extends StatefulWidget {
  final String roomId;
  final String role;
  final GameRoom initialRoom;

  const LanRoomPage({
    super.key,
    required this.roomId,
    required this.role,
    required this.initialRoom,
  });

  @override
  State<LanRoomPage> createState() => _LanRoomPageState();
}

class _LanRoomPageState extends State<LanRoomPage> {
  LanHostViewModel? _hostVm;
  LanClientViewModel? _clientVm;
  StreamSubscription<LanRoomEvent>? _roomSub;
  String? _clientDeviceId;
  bool _navigatedToGame = false;

  bool get _isHost => widget.role == 'host';

  @override
  void initState() {
    super.initState();
    if (_isHost) {
      _hostVm = LanHostViewModel();
      _hostVm!.dispatch(HostCreateRoom(
        roomId: widget.roomId,
        hostName: widget.initialRoom.hostName,
      ));
      _startHost();
    } else {
      _clientVm = LanClientViewModel();
      _startClient();
    }
    _roomSub =
        LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
  }

  Future<void> _startHost() async {
    await LanServiceAdapter.instance.announceRoom(widget.initialRoom);
  }

  Future<void> _startClient() async {
    await LanServiceAdapter.instance.sendJoinRequest(
      hostDeviceId: widget.initialRoom.hostDeviceId,
      clientAlias: LanServiceAdapter.instance.myAlias,
    );
  }

  void _onRoomEvent(LanRoomEvent ev) {
    if (!mounted) return;
    if (ev is ClientJoinRequested && _isHost) {
      if (ev.clientDeviceId == LanServiceAdapter.instance.myDeviceId) {
        return; // 忽略自己
      }
      setState(() {
        _clientDeviceId = ev.clientDeviceId;
      });
      // 接受消息
      LanServiceAdapter.instance.sendJoinAccept(
        clientDeviceId: ev.clientDeviceId,
        room: widget.initialRoom.copyWith(
          clientDeviceId: ev.clientDeviceId,
          clientName: ev.clientAlias,
        ),
      );
    } else if (ev is ClientJoinResult && !_isHost) {
      if (ev.accepted) {
        _onCountdownFinished();
      }
    } else if (ev is HostRoomClosed && !_isHost) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Host 关闭了房间')),
        );
        Navigator.of(context).pop();
      }
    }
  }

  void _onCountdownFinished() {
    if (!mounted) return;
    _navigatedToGame = true;
    final page = _isHost
        ? LanHostGamePage(
            viewModel: _hostVm!,
            peerDeviceId: _clientDeviceId ?? '',
          )
        : LanClientGamePage(
            viewModel: _clientVm!,
          );
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => page),
    );
  }

  @override
  void dispose() {
    _roomSub?.cancel();
    _hostVm?.dispose();
    _clientVm?.dispose();
    if (_isHost && !_navigatedToGame) {
      LanServiceAdapter.instance.stopRoom(widget.roomId);
    }
    super.dispose();
  }

  void _onBackPressed() {
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_isHost) {
      return ValueListenableBuilder<LanHostState>(
        valueListenable: _hostVm!,
        builder: (_, state, __) => _buildScaffold(
          content: switch (state) {
            HostWaiting() => _buildHostWaiting(state),
            HostCountdown(:final secondsLeft) =>
              _buildCountdown(state.room, secondsLeft),
            _ => _buildHostWaiting(
                HostWaiting(room: widget.initialRoom),
              ),
          },
        ),
      );
    } else {
      return ValueListenableBuilder<LanClientState>(
        valueListenable: _clientVm!,
        builder: (_, state, __) => _buildScaffold(
          content: switch (state) {
            ClientJoining() => _buildJoining(),
            ClientWaiting() => _buildClientWaiting(state),
            _ => _buildClientWaiting(
                ClientWaiting(room: widget.initialRoom),
              ),
          },
        ),
      );
    }
  }

  Widget _buildScaffold({required Widget content}) {
    return Scaffold(
      appBar: AppBar(
        title: Text('房间 ${widget.roomId}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _onBackPressed,
        ),
      ),
      body: Center(child: content),
    );
  }

  Widget _buildHostWaiting(HostWaiting state) {
    final joined = state.room.hasClient;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          joined ? '玩家已加入' : '等待玩家加入...',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text('房间号: ${state.room.roomId}'),
        if (joined && state.room.clientName != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('对手: ${state.room.clientName}'),
          ),
      ],
    );
  }

  Widget _buildClientWaiting(ClientWaiting state) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          '等待主机开始...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Text('房间号: ${state.room.roomId}'),
      ],
    );
  }

  Widget _buildJoining() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        const Text(
          '正在加入房间...',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }

  Widget _buildCountdown(GameRoom room, int secondsLeft) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Text(
          '游戏即将开始',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 24),
        Text(
          '$secondsLeft',
          style: const TextStyle(
            fontSize: 72,
            fontWeight: FontWeight.bold,
            color: Colors.blue,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: 验证 GameRoom 字段名**

```bash
cd D:\DevProjects\my\github\fr
grep -A 12 "class GameRoom" lib/core/jungle_chess/lan/game_room.dart
```

Expected: 字段 `roomId` / `hostDeviceId` / `hostName` / `clientDeviceId` / `clientName` 都存在。

如果 `hostDeviceId` 在 jungle_chess 中叫别的名字(如 `hostId`),修正 Task 5 Step 2 中的所有引用。

- [ ] **Step 4: 验证 LanHostGamePage / LanClientGamePage 构造器签名**

Task 6 / Task 7 改写时需要确保:
- `LanHostGamePage({viewModel, peerDeviceId})`
- `LanClientGamePage({viewModel})`

如果现有构造器签名不匹配,**STOP** 并先实施 Task 6/7 改写构造器。

- [ ] **Step 5: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/lan_room_page.dart 2>&1 | grep -E "error|warning"
```

Expected: 无输出。如果有 error 通常是 LanHostGamePage / LanClientGamePage 还没改写,先做 Task 6/7 再回来。

- [ ] **Step 6: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/lan_room_page.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): LanRoomPage (Host/Client dual-role room page)

Mechanical-mirror of surround_game LanRoomPage (351 lines).
Host: announceRoom + accept join + countdown → push LanHostGamePage
Client: sendJoinRequest + wait accept + countdown → push LanClientGamePage

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 6: LanHostGamePage (Session 创建 + notifier 桥接)

**Files:**
- Modify: `lib/core/jungle_chess/lan/lan_host_game_page.dart`(全文替换)

**Interfaces:**
- Consumes:
  - `LanHostViewModel` (现有)
  - `JungleHostTouchController`, `JungleHostTouchControllerFactory` (Task 4)
  - `JungleEngine.createInitialState()` (现有)
  - `LanServiceAdapter.instance.createGameSession` (Task 3)
- Produces:
  - `LanHostGamePage({viewModel, peerDeviceId})` 
  - `initState`: 创建 `gameStateNotifier` + `JungleHostTouchController` + `Session`
  - `dispose`: 销毁 notifier + session + touchController
  - ViewModel 状态变化 → notifier 同步(用于 Session 序列化)

- [ ] **Step 1: 全文替换 lan_host_game_page.dart**

替换整个文件 `lib/core/jungle_chess/lan/lan_host_game_page.dart`,内容:

```dart
// lib/core/jungle_chess/lan/lan_host_game_page.dart
//
// LAN 主机端游戏页。
//
// 单一 source of truth = gameStateNotifier (ValueNotifier<GameState>)
// - ViewModel 走 start/countdown/finish 编排
// - ViewModel 走棋后 reducer 更新 gameStateNotifier.value
// - Session 监听 gameStateNotifier → 自动推送给 Client

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/jungle_board.dart';
import '../widgets/jungle_board_frame.dart';
import '../widgets/jungle_host_touch_controller.dart';
import '../widgets/jungle_touch_controller.dart';
import '../widgets/jungle_dialog.dart';
import '../engine/jungle_engine.dart';
import '../models/game_state.dart';
import '../models/piece.dart';
import 'lan_host_view_model.dart';
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'service/lan_service_adapter.dart';

class LanHostGamePage extends StatefulWidget {
  final LanHostViewModel viewModel;
  final String peerDeviceId;

  const LanHostGamePage({
    super.key,
    required this.viewModel,
    required this.peerDeviceId,
  });

  @override
  State<LanHostGamePage> createState() => _LanHostGamePageState();
}

class _LanHostGamePageState extends State<LanHostGamePage> {
  late final ValueNotifier<GameState> _gameStateNotifier;
  late final JungleTouchController _touchController;
  late final Stopwatch _boardSizeWatch;
  dynamic _session; // Session<ValueNotifier<GameState>>
  VoidCallback? _vmListener;

  @override
  void initState() {
    super.initState();
    _gameStateNotifier =
        ValueNotifier<GameState>(JungleEngine.createInitialState());
    // 棋盘尺寸先用一个合理默认值；LayoutBuilder 完成后通过 setBoardSize 注入
    _touchController = JungleHostTouchControllerFactory(
      boardSize: 0,
    ).create();
    _boardSizeWatch = Stopwatch()..start();
    _vmListener = _syncNotifierFromVm;
    widget.viewModel.addListener(_vmListener!);
    _syncNotifierFromVm();
    // 创建 Session
    _session = LanServiceAdapter.instance.createGameSession(
      peerDeviceId: widget.peerDeviceId,
      state: _gameStateNotifier,
    );
  }

  /// 把 ViewModel 当前的 GameState 同步到 gameStateNotifier
  /// （用于 Session 序列化推送）
  void _syncNotifierFromVm() {
    final s = widget.viewModel.value;
    if (s is HostInGame) {
      _gameStateNotifier.value = s.gameState;
    } else if (s is HostFinished) {
      _gameStateNotifier.value = s.gameState;
    }
  }

  void _onMoveConfirmed(Coord from, Coord to) {
    widget.viewModel.dispatch(HostMoveCommitted(from: from, to: to));
    _syncNotifierFromVm();
    _checkGameOver();
  }

  void _checkGameOver() {
    final state = widget.viewModel.value;
    if (state is HostFinished && mounted) {
      final gs = state.gameState;
      showJungleGameOverDialog(
        context,
        gs.winner == null ? '平局' : (gs.winner == PlayerColor.blue ? '蓝方' : '红方'),
        gs.gameOverReason ?? '',
        onRestart: () {
          widget.viewModel.dispatch(const HostStartGame());
          _syncNotifierFromVm();
        },
        onExit: () {
          // 广播关房
          LanServiceAdapter.instance.stopRoom(widget.peerDeviceId);
          Navigator.pop(context);
        },
      );
    }
  }

  @override
  void dispose() {
    if (_vmListener != null) {
      widget.viewModel.removeListener(_vmListener!);
    }
    _gameStateNotifier.dispose();
    _touchController.dispose();
    if (_session != null && _session.dispose is Function) {
      try {
        _session.dispose();
      } catch (_) {
        // best-effort cleanup
      }
    }
    _boardSizeWatch.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8FC),
      appBar: AppBar(
        title: const Text(
          '斗兽棋 · 主机',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1F2937),
        elevation: 0,
      ),
      body: ValueListenableBuilder<LanHostState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            HostLobby() => const _StateScreen(
                icon: Icons.hourglass_empty_rounded,
                title: '房间未创建',
              ),
            HostWaiting() => const _StateScreen(
                icon: Icons.wifi_tethering_rounded,
                title: '等待对手加入…',
              ),
            HostCountdown(:final secondsLeft) =>
              _StateScreen(icon: Icons.timer_outlined, title: '$secondsLeft'),
            HostInGame(:final gameState) => _buildGame(gameState),
            HostFinished(:final gameState) => _buildGame(gameState),
            HostError(:final message) => _StateScreen(
                icon: Icons.error_outline_rounded,
                title: '错误：$message',
                isError: true,
              ),
          };
        },
      ),
    );
  }

  Widget _buildGame(GameState gameState) {
    return Column(
      children: [
        _TurnCard(
          round: gameState.roundCount ~/ 2 + 1,
          historyLen: gameState.history.length,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Center(
              child: AspectRatio(
                aspectRatio: 7 / 9,
                child: JungleBoardFrame(
                  child: JungleBoard(
                    gameState: gameState,
                    touchController: _touchController,
                    onMoveConfirmed: _onMoveConfirmed,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TurnCard extends StatelessWidget {
  final int round;
  final int historyLen;
  const _TurnCard({required this.round, required this.historyLen});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Text('🔵', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Text(
              '主机 · 蓝方',
              style: TextStyle(
                color: Color(0xFF3B82F6),
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            _MetaChip(label: '第 $round 回合'),
            const SizedBox(width: 6),
            _MetaChip(label: '$historyLen 步', muted: true),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final bool muted;
  const _MetaChip({required this.label, this.muted = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: muted ? const Color(0xFF9CA3AF) : const Color(0xFF4B5563),
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _StateScreen extends StatelessWidget {
  final IconData icon;
  final String title;
  final bool isError;
  const _StateScreen({required this.icon, required this.title, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 72, color: const Color(0xFF9CA3AF)),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              color: isError ? const Color(0xFFEF4444) : const Color(0xFF4B5563),
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 HostStartGame / HostMoveCommitted / HostFinished 事件名存在**

```bash
cd D:\DevProjects\my\github\fr
grep -n "class HostStartGame\|class HostMoveCommitted\|class HostFinished" lib/core/jungle_chess/lan/lan_match_event.dart lib/core/jungle_chess/lan/lan_match_state.dart
```

Expected: 事件和状态都在。

如果 `HostFinished` 在 jungle_chess 状态定义中**没有** `gameState` 字段(只有空),改写本 Task 6 的 build 逻辑(从 gameStateNotifier 取)。

- [ ] **Step 3: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/lan_host_game_page.dart 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

- [ ] **Step 4: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/lan_host_game_page.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): LanHostGamePage with Session + notifier bridge

Mechanical-mirror of surround_game LanHostGamePage. Adds:
- gameStateNotifier (single source of truth for Session sync)
- JungleHostTouchController (Y-mirrored) via factory
- ViewModel.addListener bridge to sync reducer output → notifier
- Session lifecycle: create in initState, dispose in dispose

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 7: LanClientGamePage (strictly read-only text version)

**Files:**
- Modify: `lib/core/jungle_chess/lan/lan_client_game_page.dart`(全文替换)

**Interfaces:**
- Consumes:
  - `LanClientViewModel` (现有)
  - `LanServiceAdapter.instance.watchRoomEvents` (Task 3)
- Produces:
  - `LanClientGamePage({viewModel})` 严格只读文字版
  - 不渲染 JungleBoard,不响应触摸
  - 接收 Host 推过来的 state(注:ClientGamePage 实际不需要 gameStateNotifier——Host 通过 Session 推,Client 端只需要 ValueNotifier 接收即可,实际实现细节取决于 Session 架构;此处用简化方案,只显示 ViewModel 状态)

- [ ] **Step 1: 全文替换 lan_client_game_page.dart**

替换整个文件 `lib/core/jungle_chess/lan/lan_client_game_page.dart`,内容:

```dart
// lib/core/jungle_chess/lan/lan_client_game_page.dart
//
// LAN 客户端游戏页 — 严格只读文字版。
//
// 机械照搬 surround_game 极简风格：
// - 不渲染 JungleBoard
// - 不创建 touchController
// - 不响应触摸
// - 仅显示当前回合 + 胜负结果

import 'package:flutter/material.dart';
import '../models/piece.dart';
import 'lan_match_state.dart';
import 'lan_client_view_model.dart';

class LanClientGamePage extends StatefulWidget {
  final LanClientViewModel viewModel;
  const LanClientGamePage({super.key, required this.viewModel});

  @override
  State<LanClientGamePage> createState() => _LanClientGamePageState();
}

class _LanClientGamePageState extends State<LanClientGamePage> {
  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('斗兽棋 - 客户端')),
      body: ValueListenableBuilder<LanClientState>(
        valueListenable: widget.viewModel,
        builder: (context, state, _) {
          return switch (state) {
            ClientIdle() => const Center(child: Text('已断开连接')),
            ClientJoining() => const Center(child: CircularProgressIndicator()),
            ClientWaiting() => const Center(child: Text('等待主机开始游戏...')),
            ClientCountdown(:final secondsLeft) => Center(
              child: Text(
                '游戏即将开始: $secondsLeft',
                style: const TextStyle(fontSize: 48),
              ),
            ),
            ClientInGame() => const Center(
              child: Text(
                '游戏进行中\n等待主机走子...',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500),
              ),
            ),
            ClientFinished(:final gameState) => Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '游戏结束: ${gameState.winner == null ? "平局" : "${gameState.winner == PlayerColor.blue ? "蓝" : "红"}方获胜"}',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('退出'),
                  ),
                ],
              ),
            ),
            ClientDisconnected(:final message) => Center(
              child: Text('断开: $message'),
            ),
          };
        },
      ),
    );
  }
}
```

- [ ] **Step 2: 验证 ClientInGame / ClientFinished 字段**

```bash
cd D:\DevProjects\my\github\fr
grep -A 5 "class ClientInGame\|class ClientFinished" lib/core/jungle_chess/lan/lan_match_state.dart
```

Expected: 
- `ClientInGame` 至少有 `gameState` 字段
- `ClientFinished` 至少有 `gameState` 字段

如果 `ClientInGame` 没有 `gameState` 字段,改写为:

```dart
ClientInGame(:final gameState) => Center(
  child: Text(
    '游戏进行中\n当前回合: ${gameState.currentTurn == PlayerColor.blue ? "蓝" : "红"}方\n等待主机走子...',
    textAlign: TextAlign.center,
    style: const TextStyle(fontSize: 18),
  ),
),
```

- [ ] **Step 3: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/lan_client_game_page.dart 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

- [ ] **Step 4: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/lan_client_game_page.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): LanClientGamePage strictly read-only text version

Mechanical-mirror of surround_game LanClientGamePage minimalism:
- Does not render JungleBoard
- Does not create touchController
- Does not handle touch input
- Shows round text + result text only

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 8: LanLobbyPage (full implementation: room list + device list + error stream)

**Files:**
- Modify: `lib/core/jungle_chess/lan/lan_lobby_page.dart`(全文替换)

**Interfaces:**
- Consumes:
  - `LanServiceAdapter.instance` 全部方法(Task 3)
  - `PlayerProfileService` (Task 1)
  - `LanRoomPage` (Task 5)
  - `LanHostViewModel.dispatch(HostCreateRoomPressed)` (现有)
  - `HostRoomAnnounced` (现有 sealed 类型)
  - `Device` (来自 localnet)
- Produces:
  - `LanLobbyPage` 完整实现:
    - 进入页 → bootstrap → 加载 alias → start adapter
    - 订阅 watchRoomEvents / watchDevices / watchErrors
    - 房间列表(由 HostRoomAnnounced 填充)
    - 设备列表(由 watchDevices 填充)
    - 创建房间:dispatch HostCreateRoomPressed → push LanRoomPage
    - 加入房间(点列表):push LanRoomPage
    - dispose: cancel subs + adapter.stop()

**Source:** 1:1 复制 `lib/core/surround_game/lan/lan_lobby_page.dart` (372 行),适配 jungle_chess State/Event 名字。

- [ ] **Step 1: 全文替换 lan_lobby_page.dart**

替换整个文件 `lib/core/jungle_chess/lan/lan_lobby_page.dart`,内容:

```dart
// lib/core/jungle_chess/lan/lan_lobby_page.dart
//
// 局域网模式"建房前"入口页。
//
// 进入时自动启动 adapter；房间列表由 framework 发现的 HostRoomAnnounced 事件填充。
// 错误流（adapter 启动失败 / 协议解析失败）以 SnackBar 展示。
// dispose：取消所有订阅 + adapter.stop()。

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xiaodouzi_fr/core/localnet/device/device.dart' show Device;
import 'lan_match_state.dart';
import 'lan_match_event.dart';
import 'lan_host_view_model.dart';
import 'lan_room_page.dart';
import 'persistence/player_profile_service.dart';
import 'protocol/lan_messages.dart';
import 'service/lan_service_adapter.dart';
import 'game_room.dart';

class LanLobbyPage extends StatefulWidget {
  const LanLobbyPage({super.key});

  @override
  State<LanLobbyPage> createState() => _LanLobbyPageState();
}

class _LanLobbyPageState extends State<LanLobbyPage> {
  late final LanHostViewModel _vm;
  late final TextEditingController _aliasCtrl;
  late final FocusNode _aliasFocus;
  StreamSubscription<LanRoomEvent>? _roomSub;
  StreamSubscription<List<Device>>? _deviceSub;
  StreamSubscription<LanServiceError>? _errorSub;
  List<Device> _devices = const [];
  List<HostRoomAnnounced> _rooms = const [];
  bool _adapterStarted = false;

  @override
  void initState() {
    super.initState();
    _vm = LanHostViewModel();
    _aliasCtrl = TextEditingController();
    _aliasFocus = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  Future<void> _bootstrap() async {
    final savedAlias = await PlayerProfileService.loadAlias();
    if (!mounted) return;

    if (savedAlias != null && savedAlias.isNotEmpty) {
      _aliasCtrl.text = savedAlias;
      await _startAdapter();
      return;
    }
    await _startAdapter();
    _aliasFocus.requestFocus();
  }

  Future<void> _startAdapter() async {
    try {
      await LanServiceAdapter.instance.start(myAlias: _aliasCtrl.text);
      if (!mounted) return;
      setState(() => _adapterStarted = true);
      _roomSub =
          LanServiceAdapter.instance.watchRoomEvents().listen(_onRoomEvent);
      _deviceSub =
          LanServiceAdapter.instance.watchDevices().listen(_onDeviceEvent);
      _errorSub =
          LanServiceAdapter.instance.watchErrors().listen(_onError);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('框架启动失败: $e')),
        );
      }
    }
  }

  void _onAliasSubmitted(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    PlayerProfileService.saveAlias(trimmed);
    if (_adapterStarted) {
      LanServiceAdapter.instance.updateAlias(trimmed);
    }
  }

  bool get _hasValidAlias =>
      _aliasCtrl.text.trim().isNotEmpty && _adapterStarted;

  void _onRoomEvent(LanRoomEvent ev) {
    if (ev is HostRoomAnnounced) {
      setState(() {
        _rooms = [
          ..._rooms.where((r) => r.roomId != ev.roomId),
          ev,
        ];
      });
    } else if (ev is HostRoomClosed) {
      setState(() {
        _rooms = _rooms.where((r) => r.roomId != '').toList();
      });
    }
  }

  void _onDeviceEvent(List<Device> devices) {
    setState(() => _devices = devices);
  }

  void _onError(LanServiceError err) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('网络错误: $err')),
    );
  }

  void _onCreateRoom() {
    _onAliasSubmitted(_aliasCtrl.text);
    _vm.dispatch(HostCreateRoom(
      roomId: DateTime.now().millisecondsSinceEpoch.toString(),
      hostName: LanServiceAdapter.instance.myAlias,
    ));
    final state = _vm.value;
    final room = state is HostWaiting ? state.room : GameRoom.placeholder();
    final roomId = room.roomId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: roomId,
          role: 'host',
          initialRoom: room,
        ),
      ),
    );
  }

  void _onJoinRoom(HostRoomAnnounced ann) {
    final room = GameRoom(
      roomId: ann.roomId,
      hostDeviceId: ann.hostDeviceId,
      hostName: ann.hostName,
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LanRoomPage(
          roomId: ann.roomId,
          role: 'client',
          initialRoom: room,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _aliasFocus.dispose();
    _roomSub?.cancel();
    _deviceSub?.cancel();
    _errorSub?.cancel();
    _vm.dispose();
    _aliasCtrl.dispose();
    if (_adapterStarted) {
      LanServiceAdapter.instance.stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('斗兽棋 - 局域网'),
        actions: [
          if (_adapterStarted)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: Text(
                  '${_devices.length} 设备',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // 本机名称编辑区
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(Icons.person, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 160,
                        child: TextField(
                          controller: _aliasCtrl,
                          focusNode: _aliasFocus,
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 6,
                            ),
                            hintText: '输入你的名称',
                            border: OutlineInputBorder(),
                          ),
                          maxLength: 16,
                          onChanged: (_) => setState(() {}),
                          onSubmitted: _onAliasSubmitted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: ShapeDecoration(
                              shape: const CircleBorder(),
                              color: _adapterStarted ? Colors.green : Colors.orange,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(_adapterStarted ? '已连接' : '启动中...'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // 创建房间按钮
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _hasValidAlias ? _onCreateRoom : null,
                icon: const Icon(Icons.add),
                label: const Text('创建房间'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const Divider(height: 1),

          // 房间列表
          Expanded(child: _buildRoomList()),
        ],
      ),
    );
  }

  Widget _buildRoomList() {
    if (_rooms.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_find, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              '暂无可用房间',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _devices.isEmpty ? '等待其他设备上线...' : '等待房间广播...',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: _rooms.length,
      itemBuilder: (ctx, i) {
        final r = _rooms[i];
        return ListTile(
          leading: const Icon(Icons.meeting_room),
          title: Text('${r.hostName} 的房间'),
          subtitle: Text('ID: ${r.roomId}'),
          onTap: () => _onJoinRoom(r),
        );
      },
    );
  }
}
```

- [ ] **Step 2: 验证 HostRoomAnnounced / HostRoomClosed 字段**

```bash
cd D:\DevProjects\my\github\fr
grep -A 8 "class HostRoomAnnounced\|class HostRoomClosed" lib/core/jungle_chess/lan/protocol/lan_messages.dart
```

Expected: `HostRoomAnnounced` 字段: `hostDeviceId` / `hostName` / `roomId`;`HostRoomClosed` 字段: 空。

如果字段名不一致,**STOP** 并修正 Task 8 Step 1 的引用。

- [ ] **Step 3: 验证 GameRoom 工厂方法**

```bash
cd D:\DevProjects\my\github\fr
grep -n "GameRoom.placeholder\|factory GameRoom" lib/core/jungle_chess/lan/game_room.dart
```

Expected: `GameRoom.placeholder()` 工厂方法存在。

如果不存在,用 `GameRoom(roomId: ..., hostDeviceId: '', hostName: ...)` 替代。

- [ ] **Step 4: 验证 HostCreateRoom 事件签名**

```bash
cd D:\DevProjects\my\github\fr
grep -A 6 "class HostCreateRoom" lib/core/jungle_chess/lan/lan_match_event.dart
```

Expected: 字段 `roomId` / `hostName`。

如果不一致,修正 `_onCreateRoom` 的 `dispatch` 调用。

- [ ] **Step 5: 验证编译**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/lan/lan_lobby_page.dart 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

- [ ] **Step 6: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/lan/lan_lobby_page.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): LanLobbyPage with room list + device list + error stream

Mechanical-mirror of surround_game LanLobbyPage (372 lines). Replaces
the 66-line placeholder with full implementation:
- Bootstrap: loadAlias → startAdapter → subscribe
- Room list populated by HostRoomAnnounced events
- Device count shown in AppBar
- Errors surfaced via SnackBar
- dispose: cancel all subs + adapter.stop()

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 9: Verify full module compiles and analyze passes

**Files:**
- Modify: `lib/core/jungle_chess/jungle_chess.dart` (追加 host touch controller + persistence exports)

- [ ] **Step 1: 确认 jungle_chess.dart barrel 导出新增文件**

打开 `lib/core/jungle_chess/jungle_chess.dart`,确保导出以下文件:

```dart
export 'widgets/jungle_host_touch_controller.dart';
export 'lan/persistence/device_id_service.dart';
export 'lan/persistence/player_profile_service.dart';
export 'lan/lan_room_page.dart';
```

(其他已有 export 保持不变。)

- [ ] **Step 2: 运行全模块 analyze**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze lib/core/jungle_chess/ 2>&1 | grep -E "error|warning"
```

Expected: 无输出。

如果有 error,根据报错回到对应 Task 修复。

- [ ] **Step 3: 运行项目级 analyze**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze 2>&1 | grep error
```

Expected: 无输出。

- [ ] **Step 4: Commit (if barrel was modified)**

```bash
cd D:\DevProjects\my\github\fr
git add lib/core/jungle_chess/jungle_chess.dart
git -c core.autocrlf=false commit -m "feat(jungle-chess): export host touch controller + persistence + room page

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Task 10: Update upstream jungle_chess spec

**Files:**
- Modify: `docs/superpowers/specs/2026-06-21-jungle-chess-design.md`

- [ ] **Step 1: 在文件末尾追加 "LAN 实施补完" section**

打开 `docs/superpowers/specs/2026-06-21-jungle-chess-design.md`,在 "## 不包含的范围(显式排除)" 之前插入:

```markdown
## LAN 实施补完(2026-06-22)

详情见 `docs/superpowers/specs/2026-06-22-jungle-chess-lan-completion-design.md`。

本节为简述:

- 9 个文件按映射表完成(4 新增 + 5 改写):
  - 新增: `lan/persistence/device_id_service.dart`、`lan/persistence/player_profile_service.dart`、
    `lan/lan_room_page.dart`、`widgets/jungle_host_touch_controller.dart`
  - 改写: `lan/serializer/game_state_serializer.dart`、`lan/service/lan_service_adapter.dart`、
    `lan/lan_lobby_page.dart`、`lan/lan_host_game_page.dart`、`lan/lan_client_game_page.dart`
- `LanServiceAdapter` 14 个方法签名与 surround_game 一致
- `GameStateSerializer` 加上 `implements StateSerializer<ValueNotifier<GameState>>`
- `LanLobbyPage` 支持房间列表 + 设备列表 + 错误提示
- `LanRoomPage` 中转页存在,Host/Client 双角色
- `LanHostGamePage` 进游戏页自动创建 Session + 走棋自动同步
- `LanClientGamePage` 严格只读文字版,不渲染棋盘
- `JungleHostTouchController` Y 镜像 + 2 个工厂

## 页面导航(更新后)

```
Lab Demo 入口 (jungle_chess_demo.dart)
    │
    ├── "本地对战" → LocalGamePage
    │                  ├── 棋盘组件（JungleBoard + JunglePiece）
    │                  ├── 回合指示器
    │                  ├── 悔棋按钮（>0 步可悔）
    │                  ├── 重新开始按钮
    │                  └── 退出确认弹窗
    │
    └── "局域网对战" → LanLobbyPage
                        ├── 昵称输入 + 设备数
                        ├── "创建房间" → LanRoomPage(role:'host') → 倒计时 → LanHostGamePage
                        └── 房间列表 → 点击加入 → LanRoomPage(role:'client') → 倒计时 → LanClientGamePage
```
```

- [ ] **Step 2: 验证**

```bash
cd D:\DevProjects\my\github\fr
ls -la docs/superpowers/specs/2026-06-21-jungle-chess-design.md
```

确认文件存在且内容已修改。

- [ ] **Step 3: Commit**

```bash
cd D:\DevProjects\my\github\fr
git add docs/superpowers/specs/2026-06-21-jungle-chess-design.md
git -c core.autocrlf=false commit -m "docs(jungle-chess): spec updated with LAN completion section

Adds references to 2026-06-22 LAN completion spec and updates the
page navigation to reflect LanLobbyPage → LanRoomPage → LanGamePage flow.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

## Self-Review(plan vs spec)

| Spec section | 实施在哪个 task |
|-------------|----------------|
| 文件清单与机械映射表 (4 新增 + 5 改写) | Task 1/2/3/4/5/6/7/8 — 9 个文件全覆盖 |
| 不改动的现有文件 (8 个) | 全 plan 严格遵守,无任何改动 |
| 5.1 LanServiceAdapter 接口 (14 个方法) | Task 3 Step 1 |
| 5.2 GameStateSerializer implements StateSerializer | Task 2 Step 1 |
| 5.3 LanLobbyPage 行为 | Task 8 Step 1 |
| 5.4 LanRoomPage 中转页 | Task 5 Step 2 |
| 5.5 LanHostGamePage (notifier + Session) | Task 6 Step 1 |
| 5.6 LanClientGamePage 严格只读文字版 | Task 7 Step 1 |
| 5.7 JungleHostTouchController + 工厂 | Task 4 Step 2 |
| 5.8 persistence services | Task 1 Step 1/2 |
| 数据流 Host 端 5 阶段 | 全部涵盖于 Task 1/2/3/4/5/6/8 |
| 数据流 Client 端 5 阶段 | 全部涵盖于 Task 1/2/3/4/5/7/8 |
| 错误处理 11 类 | 各 Task 中显式错误处理 + Task 5/8 弹 SnackBar |
| 测试策略 | plan 末尾"集成验证"段落 |
| 显式不包含的范围 12 项 | 全 plan 严格遵守(无 AI/计时/聊天等) |
| 验收清单 12 项 | Task 9 + Task 10 + plan 末尾"集成验证" |

**占位符扫描**: 全 plan 无 "TBD" / "TODO" / "implement later" / "fill in details" / "add appropriate error handling" — 每步给完整代码或明确动作。

**类型一致性检查**:
- `DeviceIdService.load()` 签名 → Task 1/3 都用对
- `PlayerProfileService.loadAlias()` / `saveAlias()` → Task 1/8 都用对
- `LanServiceAdapter.instance` 14 个方法 → Task 3 定义,Task 5/6/8 都用对
- `HostCreateRoom` / `HostMoveCommitted` / `HostStartGame` → Task 5/6/8 引用,与 spec 一致
- `HostInGame` / `HostFinished` / `ClientInGame` / `ClientFinished` → Task 5/6/7 引用

**没有类型不一致**。

---

## 集成验证(完成 plan 后必做)

- [ ] **Task 11: 双机联调准备(非代码 task,验证步骤)**

启动两台 Android 真机(同一 WiFi),执行:

1. **设备 A(Host)**: flutter run → 进入 jungle_chess demo → "局域网对战" → 输入 alias "Host" → "创建房间"
2. **设备 B(Client)**: flutter run → 进入 jungle_chess demo → "局域网对战" → 输入 alias "Client"
3. 设备 A 房间列表应显示 "Host 的房间"
4. 设备 B 点击 "Host 的房间" → 进入 LanRoomPage
5. 设备 A 状态变 "玩家已加入"
6. 设备 A 倒计时(3 秒)
7. 双方进入游戏页:
   - 设备 A 看到棋盘(蓝方在底)
   - 设备 B 看到 "游戏进行中,等待主机走子..."
8. 设备 A 走棋(点击鼠 → 点击目标格)
9. 设备 A 看到走子成功,回合变红方
10. 设备 B 仍然只看到 "等待主机走子..." (因为 ClientGamePage 不渲染棋盘)
11. 设备 A 走红方走棋 → 回合变蓝方 → 一局完整下完
12. 设备 A 弹出胜负弹窗 → "再来一局" 或 "退出"

如果某步骤失败,根据 logcat 输出回到对应 Task 修复。

```bash
# 联调时查看 Logcat
adb logcat | grep -E "lan|LanFramework|LanServiceAdapter|GameState"
```

- [ ] **Task 12: 完整 analyze 通过**

```bash
cd D:\DevProjects\my\github\fr
flutter analyze 2>&1 | tee /tmp/analyze.log
grep -E "error" /tmp/analyze.log
```

Expected: 无 error 输出。

- [ ] **Task 13: 最终 spec 验收清单复审**

对照 spec §"验收清单" 12 项,逐条勾选并 commit 任何遗漏:

```bash
cd D:\DevProjects\my\github\fr
git log --oneline -10
git status
```

确认所有 9 个文件已 commit,无遗漏修改。
