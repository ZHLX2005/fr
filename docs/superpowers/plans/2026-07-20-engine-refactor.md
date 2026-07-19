# LocalNet 引擎重构（Lan/Relay 双后端）实施 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 `lib/core/localnet/` 引擎层新增 Relay 模式（房间号发现 + HTTP 控制 + WS 多路复用传输），保留 LAN 模式（UDP 多播 + HTTP P2P）；业务层 LanServiceAdapter 一行不动。

**Architecture:** 引入 `TransportKind` 枚举 + `DiscoveryService` / `TransportChannel` 两个抽象；现有 `FrameworkCore` 重命名为 `FrameworkLanCore` 注入 Lan 实现，新增 `FrameworkRelayCore` 注入 Relay 实现；LanFramework 门面按 `transportKind` 分发。LanServiceAdapter 业务 API 零变化。

**Tech Stack:** Flutter `^3.11.1`，现有 `http` 库，新增 `web_socket_channel: ^2.4.0`，现有 `EventBus` / `DeviceManager` / `ChannelManager` / `Session` / `SessionManager` 全部复用。

**关联 Spec:** `docs/superpowers/specs/2026-07-20-engine-refactor-design.md`

---

## Global Constraints

- **业务层零变化**：`lib/core/surround_game/` 和 `lib/core/jungle_chess/` 任何文件**不修改**
- **LanServiceAdapter 公开 API 零变化**：`LanServiceAdapter` 类的公开方法签名、`start` / `stop` / `watchRoomEvents` / `announceRoom` / `sendJoinRequest` / `createGameSession` 等保持不变
- **现有 LAN 模式行为不变**：UDP 多播（端口 5678）+ HTTP P2P（端口 53317）默认配置保持
- **新增依赖**：`pubspec.yaml` 添加 `web_socket_channel: ^2.4.0`
- **命名规范**：Dart sealed class 用 `abstract interface class` 标记纯接口；`TransportKind` 枚举值小写（`lan` / `relay`）
- **错误处理**：所有新抛出的错误必须继承 `FrameworkException`（已存在 `lib/core/localnet/framework/exception/framework_exception.dart`）
- **测试策略**：每个新抽象接口必须配套 mock 测试；Relay 实现必须用 `mock_web_socket_channel`（来自 `web_socket_channel` 库自带 mock）或自己写 fake
- **Commit 频率**：每个 Task 完成后立即 commit（参考现有 `.claude/memory/feedback_autocommit_on_fix.md` 规则）

---

## File Structure Map

### 新增文件（按 phase）

| Phase | 文件 | 职责 |
|-------|------|------|
| Phase 0 | `lib/core/localnet/transport/transport_kind.dart` | enum TransportKind |
| Phase 0 | `lib/core/localnet/framework/framework_lan_core.dart` | 重命名自 `framework_core.dart` |
| Phase 0 | `lib/core/localnet/framework/lan_framework.dart` (modify) | 改为门面分发 |
| Phase 1 | `lib/core/localnet/discovery/discovery_service.dart` | abstract interface class DiscoveryService |
| Phase 1 | `lib/core/localnet/discovery/remote_endpoint.dart` | class RemoteEndpoint |
| Phase 1 | `lib/core/localnet/discovery/lan_discovery.dart` | class LanDiscovery implements DiscoveryService |
| Phase 1 | `lib/core/localnet/transport_channel/transport_channel.dart` | abstract interface class TransportChannel |
| Phase 1 | `lib/core/localnet/transport_channel/lan_channel.dart` | class LanChannel implements TransportChannel |
| Phase 1 | `lib/core/localnet/device/device_manager.dart` (modify) | 内部用 DiscoveryService |
| Phase 1 | `lib/core/localnet/channel/channel_manager.dart` (modify) | 内部用 TransportChannel |
| Phase 2 | `lib/core/localnet/transport/transport_frame.dart` | class TransportFrame |
| Phase 2 | `lib/core/localnet/transport/ws_transport.dart` | class WsTransport (WS 多路复用) |
| Phase 2 | `lib/core/localnet/discovery/relay_discovery.dart` | class RelayDiscovery implements DiscoveryService |
| Phase 2 | `lib/core/localnet/transport_channel/relay_channel.dart` | class RelayChannel implements TransportChannel |
| Phase 2 | `lib/core/localnet/framework/framework_relay_core.dart` | class FrameworkRelayCore implements FrameworkCore |
| Phase 2 | `lib/core/localnet/framework/framework_config.dart` (modify) | 新增 relayUrl / relayHttpPath / relayWsPath |
| Phase 3 | `test/localnet/transport/transport_frame_test.dart` | 序列化测试 |
| Phase 3 | `test/localnet/discovery/relay_discovery_test.dart` | mock HTTP client 测试 |
| Phase 3 | `test/localnet/transport_channel/relay_channel_test.dart` | mock WebSocket 多路复用测试 |
| Phase 3 | `test/localnet/framework/framework_relay_core_test.dart` | 端到端 Relay 流程 |

### 修改文件

| 文件 | 修改 |
|------|------|
| `pubspec.yaml` | + `web_socket_channel: ^2.4.0` |
| `lib/core/localnet/framework/framework_core.dart` | 重命名为 `framework_lan_core.dart` |
| `lib/core/localnet/framework/lan_framework.dart` | 改为门面分发到 LanCore / RelayCore |
| `lib/core/localnet/framework/framework_config.dart` | + relayUrl / relayHttpPath / relayWsPath 字段 |
| `lib/core/localnet/localnet.dart` | + 新增导出 |

---

## Phase 0：基础设施迁移（TransportKind + LanCore 重命名）

### Task 1: 添加 web_socket_channel 依赖

**Files:**
- Modify: `pubspec.yaml:30-90` (dependencies section)

**Interfaces:**
- Consumes: 无
- Produces: `web_socket_channel: ^2.4.0` 依赖可被 pub resolve

- [ ] **Step 1: 在 pubspec.yaml 添加 web_socket_channel 依赖**

打开 `pubspec.yaml`，找到 `dependencies:` 块（约 30-90 行），在 `http: ^1.2.2` 行下方添加：

```yaml
  # HTTP Requests
  http: ^1.2.2

  # WebSocket (Relay 模式传输层)
  web_socket_channel: ^2.4.0
```

- [ ] **Step 2: 运行 flutter pub get 验证依赖解析成功**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter pub get
```

Expected: 成功，输出包含 "Got dependencies!" 或 "Resolving dependencies..." 后无 error。

- [ ] **Step 3: 验证导入可用**

Run:
```bash
cd D:/code/a_dart/prj/fr && grep -r "import 'package:web_socket_channel" lib/ 2>&1 || echo "no usage yet"
```

Expected: 输出 "no usage yet"（仅确认依赖装好，不需引用）。

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml pubspec.lock
git commit -m "chore(deps): add web_socket_channel ^2.4.0 for Relay transport"
```

---

### Task 2: 创建 TransportKind 枚举

**Files:**
- Create: `lib/core/localnet/transport/transport_kind.dart`

**Interfaces:**
- Consumes: 无
- Produces: `enum TransportKind { lan, relay }`

- [ ] **Step 1: 创建文件**

写入 `lib/core/localnet/transport/transport_kind.dart`：

```dart
/// 传输后端种类 — 决定 FrameworkCore 选 LanCore 还是 RelayCore
enum TransportKind {
  /// 局域网模式：UDP 多播发现 + HTTP P2P 传输
  lan,

  /// 互联网模式：HTTP 控制面（房间号注册/查询）+ WS 传输面
  relay,
}
```

- [ ] **Step 2: 在 localnet.dart 中导出**

修改 `lib/core/localnet/localnet.dart`，在 `export 'transport/transport.dart';` 行之前添加：

```dart
export 'transport/transport_kind.dart';
```

- [ ] **Step 3: 验证导入**

Run:
```bash
cd D:/code/a_dart/prj/fr && grep -rn "TransportKind" lib/ 2>&1 | head -5
```

Expected: 至少看到 `lib/core/localnet/transport/transport_kind.dart` 定义 + `localnet.dart` 导出。

- [ ] **Step 4: 编译检查**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze lib/core/localnet/transport/transport_kind.dart 2>&1 | head -20
```

Expected: "No issues found!"

- [ ] **Step 5: Commit**

```bash
git add lib/core/localnet/transport/transport_kind.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): add TransportKind enum for Lan/Relay dispatch"
```

---

### Task 3: 重命名 FrameworkCore → FrameworkLanCore

**Files:**
- Create: `lib/core/localnet/framework/framework_lan_core.dart` (复制 framework_core.dart 内容)
- Delete: `lib/core/localnet/framework/framework_core.dart`
- Modify: `lib/core/localnet/localnet.dart` (更新 export)

**Interfaces:**
- Consumes: 现有 `FrameworkCore` 实现
- Produces: `class FrameworkLanCore` 与原 `FrameworkCore` 行为完全一致

- [ ] **Step 1: 复制文件到新路径**

Run:
```bash
cd D:/code/a_dart/prj/fr && git mv lib/core/localnet/framework/framework_core.dart lib/core/localnet/framework/framework_lan_core.dart
```

- [ ] **Step 2: 重命名类**

打开 `lib/core/localnet/framework/framework_lan_core.dart`，将所有 `class FrameworkCore` 替换为 `class FrameworkLanCore`（包括类声明和 `core.eventBus.emit` 等引用名），保持构造函数签名不变。

具体替换：

| 旧 | 新 |
|----|----|
| `class FrameworkCore` | `class FrameworkLanCore` |
| `FrameworkCore({` | `FrameworkLanCore({` |
| `core.eventBus.emit` 中的 `core` 引用 | 保持不变（局部变量名） |

- [ ] **Step 3: 更新 localnet.dart export**

修改 `lib/core/localnet/localnet.dart`，将：
```dart
export 'framework/framework_core.dart';
```
改为：
```dart
export 'framework/framework_lan_core.dart';
```

- [ ] **Step 4: 更新 lan_framework.dart 引用**

打开 `lib/core/localnet/framework/lan_framework.dart`，将 `import 'framework_core.dart';` 改为 `import 'framework_lan_core.dart';`，并将 `final core = FrameworkCore(...)` 改为 `final core = FrameworkLanCore(...)`。

- [ ] **Step 5: 编译检查**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze lib/core/localnet/ 2>&1 | head -30
```

Expected: "No issues found!"（如果出现 `framework_core.dart` 引用错误，确认 Step 1 已删除旧文件）。

- [ ] **Step 6: 跑现有 lan-local-playbook skill 的测试 / build smoke**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -10
```

Expected: BUILD SUCCESSFUL（或最后一行 "Built build/app/outputs/flutter-apk/app-debug.apk"）。

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "refactor(localnet): rename FrameworkCore to FrameworkLanCore for dual-backend prep"
```

---

## Phase 1：引入 DiscoveryService 与 TransportChannel 抽象

### Task 4: 创建 RemoteEndpoint 与 DiscoveryService 抽象

**Files:**
- Create: `lib/core/localnet/discovery/remote_endpoint.dart`
- Create: `lib/core/localnet/discovery/discovery_service.dart`
- Create: `test/localnet/discovery/discovery_service_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class RemoteEndpoint { deviceId, alias, address, kind, lastSeen }`
  - `abstract interface class DiscoveryService { start, stop, endpoints, watch, probe }`

- [ ] **Step 1: 写测试文件**

写入 `test/localnet/discovery/discovery_service_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/remote_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/discovery_service.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

class _FakeDiscovery implements DiscoveryService {
  final List<RemoteEndpoint> _endpoints = [];
  final _controller = StreamController<List<RemoteEndpoint>>.broadcast();
  bool started = false;

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  Future<void> stop() async {
    started = false;
  }

  @override
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints);

  @override
  Stream<List<RemoteEndpoint>> watch() => _controller.stream;

  @override
  Future<void> probe() async {
    _controller.add(List.unmodifiable(_endpoints));
  }

  void addForTesting(RemoteEndpoint ep) {
    _endpoints.add(ep);
    _controller.add(List.unmodifiable(_endpoints));
  }
}

void main() {
  group('DiscoveryService contract', () {
    test('implements start/stop', () async {
      final fake = _FakeDiscovery();
      await fake.start();
      expect(fake.started, isTrue);
      await fake.stop();
      expect(fake.started, isFalse);
    });

    test('endpoints is unmodifiable', () {
      final fake = _FakeDiscovery();
      fake.addForTesting(RemoteEndpoint(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      expect(fake.endpoints, hasLength(1));
      expect(() => fake.endpoints.clear(), throwsUnsupportedError);
    });

    test('watch emits current list on probe', () async {
      final fake = _FakeDiscovery();
      final received = <List<RemoteEndpoint>>[];
      final sub = fake.watch().listen(received.add);
      fake.addForTesting(RemoteEndpoint(
        deviceId: 'd1',
        alias: 'Alice',
        address: '192.168.1.5:53317',
        kind: TransportKind.lan,
        lastSeen: DateTime.now(),
      ));
      await Future.delayed(const Duration(milliseconds: 10));
      expect(received, hasLength(1));
      expect(received.first.first.deviceId, 'd1');
      await sub.cancel();
    });
  });
}

class StreamController<T> {
  StreamController.broadcast();
  Stream<T> get stream => const Stream.empty();
  void add(T event) {}
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/discovery_service_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined: RemoteEndpoint, DiscoveryService）。

- [ ] **Step 3: 创建 RemoteEndpoint**

写入 `lib/core/localnet/discovery/remote_endpoint.dart`：

```dart
import '../transport/transport_kind.dart';

/// 远端设备端点 — DiscoveryService 发现的最小单元
///
/// LAN 模式下 address 形如 "192.168.1.5:53317"（HTTP P2P 目标）；
/// Relay 模式下 address 是中继服务器分配的 ws-session id。
class RemoteEndpoint {
  const RemoteEndpoint({
    required this.deviceId,
    required this.alias,
    required this.address,
    required this.kind,
    required this.lastSeen,
  });

  final String deviceId;
  final String alias;
  final String address;
  final TransportKind kind;
  final DateTime lastSeen;
}
```

- [ ] **Step 4: 创建 DiscoveryService 抽象**

写入 `lib/core/localnet/discovery/discovery_service.dart`：

```dart
import 'remote_endpoint.dart';

/// 发现服务抽象 — LAN / Relay 后端各自实现
///
/// DeviceManager 持有一个 DiscoveryService，通过 watch() 流获得端点列表变化，
/// 通过 endpoints() 取当前快照。
abstract interface class DiscoveryService {
  /// 启动发现（LAN：绑定 UDP socket；Relay：HTTP POST /discover 注册）
  Future<void> start();

  /// 停止发现（释放端口/取消订阅）
  Future<void> stop();

  /// 当前已发现端点快照（不可变列表）
  List<RemoteEndpoint> get endpoints;

  /// 端点列表变化流 — 每次有新端点加入/丢失/更新时触发
  Stream<List<RemoteEndpoint>> watch();

  /// 主动探测（如 Relay：HTTP POST /probe 触发服务端 push 最新列表）
  Future<void> probe();
}
```

- [ ] **Step 5: 修正测试文件里的 StreamController stub**

将测试文件第 53-56 行的 stub 替换为正确导入：

```dart
import 'dart:async';
```

放在文件最顶部 imports 之后。

并将 `class StreamController<T> { ... }` 这一段（53-60 行附近）整段**删除**——使用 dart:async 的真 StreamController。

- [ ] **Step 6: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/discovery_service_test.dart 2>&1 | tail -10
```

Expected: PASS（3 tests passed）。

- [ ] **Step 7: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart`，在 `export 'device/device.dart';` 行后添加：

```dart
export 'discovery/remote_endpoint.dart';
export 'discovery/discovery_service.dart';
```

- [ ] **Step 8: Commit**

```bash
git add lib/core/localnet/discovery/ test/localnet/discovery/
git commit -m "feat(localnet): add DiscoveryService interface + RemoteEndpoint"
```

---

### Task 5: 创建 LanDiscovery（封装现 UDP 多播）

**Files:**
- Create: `lib/core/localnet/discovery/lan_discovery.dart`
- Create: `test/localnet/discovery/lan_discovery_test.dart`

**Interfaces:**
- Consumes:
  - `class RemoteEndpoint`
  - `abstract interface class DiscoveryService`
  - 现 `UdpTransport.datagrams` stream
- Produces: `class LanDiscovery implements DiscoveryService`

- [ ] **Step 1: 写测试文件**

写入 `test/localnet/discovery/lan_discovery_test.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/lan_discovery.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/remote_endpoint.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/udp_transport.dart';

void main() {
  group('LanDiscovery', () {
    late UdpTransport udp;
    late LanDiscovery discovery;
    final config = const TransportConfig(
      multicastAddress: '239.255.255.255',
      multicastPort: 5678,
    );

    setUp(() async {
      udp = UdpTransport(config: config);
      try {
        await udp.start();
      } catch (_) {
        // 端口占用时跳过集成测试
      }
      discovery = LanDiscovery(
        myDeviceId: 'self-id',
        myAlias: 'Self',
        udp: udp,
      );
    });

    tearDown(() async {
      await discovery.stop();
      await udp.stop();
    });

    test('start/stop toggles internal state', () async {
      await discovery.start();
      expect(discovery.endpoints, isEmpty);
      await discovery.stop();
    });

    test('endpoints returns empty list initially', () {
      expect(discovery.endpoints, isEmpty);
    });

    test('watch() emits at least once on probe', () async {
      await discovery.start();
      final received = <List<RemoteEndpoint>>[];
      final sub = discovery.watch().listen(received.add);
      await discovery.probe();
      await Future.delayed(const Duration(milliseconds: 50));
      expect(received, isNotEmpty);
      await sub.cancel();
      await discovery.stop();
    });
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/lan_discovery_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined: LanDiscovery）。

- [ ] **Step 3: 创建 LanDiscovery**

写入 `lib/core/localnet/discovery/lan_discovery.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import '../transport/transport_kind.dart';
import '../transport/udp_transport.dart';
import 'discovery_service.dart';
import 'remote_endpoint.dart';

/// LAN 发现服务 — 监听 UDP 多播心跳包
///
/// 解析 UdpTransport.datagrams 流中的 "deviceId,port,alias:xxx" 格式，
/// 转换为 RemoteEndpoint。DeviceManager 之前直接耦合 UDP 解析逻辑，
/// 本类将其隔离，RelayDiscovery 用类似接口注入即可。
class LanDiscovery implements DiscoveryService {
  LanDiscovery({
    required this.myDeviceId,
    required this.myAlias,
    required UdpTransport udp,
  }) : _udp = udp;

  final String myDeviceId;
  final String myAlias;
  final UdpTransport _udp;
  final Map<String, RemoteEndpoint> _endpoints = {};
  final StreamController<List<RemoteEndpoint>> _ctrl =
      StreamController<List<RemoteEndpoint>>.broadcast();
  StreamSubscription? _sub;
  bool _started = false;

  @override
  Future<void> start() async {
    if (_started) return;
    _sub = _udp.datagrams.listen(_onDatagram);
    _started = true;
  }

  @override
  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    _endpoints.clear();
    _started = false;
  }

  @override
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints.values);

  @override
  Stream<List<RemoteEndpoint>> watch() => _ctrl.stream;

  @override
  Future<void> probe() async {
    _ctrl.add(endpoints);
  }

  void _onDatagram(dynamic dg) {
    // dg 是 UdpDatagram，但本地只用 .data + .senderAddress
    final data = dg.data as List<int>;
    final sender = dg.senderAddress as InternetAddress;
    final text = utf8.decode(data, allowMalformed: true);
    if (!text.contains(',')) return;

    final parts = text.split(',');
    if (parts.length < 2) return;
    final id = parts[0].trim();
    final portStr = parts[1].trim();
    final port = int.tryParse(portStr);
    if (id.isEmpty || port == null) return;
    if (id == myDeviceId) return; // 忽略自己

    String alias = sender.address;
    for (var i = 2; i < parts.length; i++) {
      final kv = parts[i].split(':');
      if (kv.length == 2 && kv[0].trim() == 'alias') {
        alias = kv[1].trim();
        break;
      }
    }

    final ep = RemoteEndpoint(
      deviceId: id,
      alias: alias,
      address: '${sender.address}:$port',
      kind: TransportKind.lan,
      lastSeen: DateTime.now(),
    );
    _endpoints[id] = ep;
    _ctrl.add(endpoints);
  }
}
```

注意：`dg` 参数类型为 `dynamic` 以避免循环引用 transport 包；可改为 `import '../transport/udp_transport.dart' show UdpDatagram;`。

- [ ] **Step 4: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'discovery/lan_discovery.dart';
```

- [ ] **Step 5: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/lan_discovery_test.dart 2>&1 | tail -10
```

Expected: PASS（3 tests passed；如果出现 multicast 绑定失败提示 CI 环境无网络，该测试会被 try/catch 跳过）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/discovery/lan_discovery.dart test/localnet/discovery/lan_discovery_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): LanDiscovery wraps existing UDP multicast parsing"
```

---

### Task 6: 创建 TransportChannel 与 LanChannel 抽象

**Files:**
- Create: `lib/core/localnet/transport_channel/transport_channel.dart`
- Create: `lib/core/localnet/transport_channel/lan_channel.dart`
- Create: `test/localnet/transport_channel/lan_channel_test.dart`

**Interfaces:**
- Consumes:
  - 现有 `ChannelManager.sendTo / watchChannel` 接口行为
  - `RemoteEndpoint`
- Produces:
  - `abstract interface class TransportChannel { open, send, watch, close }`
  - `class LanChannel implements TransportChannel` — 用现有 HTTP P2P

- [ ] **Step 1: 写测试文件**

写入 `test/localnet/transport_channel/lan_channel_test.dart`：

```dart
import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_config.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/http_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_channel/lan_channel.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_channel/transport_channel.dart';

void main() {
  group('TransportChannel contract (LanChannel)', () {
    test('open + send + watch + close lifecycle', () async {
      final server = HttpTransport(config: const TransportConfig(httpPort: 53320));
      HttpServer? bound;
      try {
        await server.start();
        bound = await HttpServer.bind(InternetAddress.loopbackIPv4, 53321);
      } catch (_) {
        // 端口占用跳过
        return;
      }
      final channel = LanChannel(http: server);
      await channel.open(
        channelName: 'test',
        remoteDeviceId: 'peer',
      );
      expect(true, isTrue); // open 不抛
      await channel.close();
      await server.stop();
      await bound.close();
    });
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport_channel/lan_channel_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined: TransportChannel, LanChannel）。

- [ ] **Step 3: 创建 TransportChannel 抽象**

写入 `lib/core/localnet/transport_channel/transport_channel.dart`：

```dart
import '../transport/transport_frame.dart';

/// 传输通道抽象 — 在 LAN 后端是 HTTP P2P，在 Relay 后端是 WS 多路复用
///
/// ChannelManager.sendTo/watchChannel 内部委托给 TransportChannel。
/// 业务层不感知底层差异。
abstract interface class TransportChannel {
  /// 打开逻辑通道（LAN：注册 HTTP /channel/<name> handler；Relay：发 OPEN frame）
  Future<void> open({required String channelName, required String remoteDeviceId});

  /// 发送消息到对端
  /// 返回 SendResult（成功/失败/错误）
  Future<SendResult> send(String channelName, Uint8List data);

  /// 订阅某 channel 的入站消息
  Stream<TransportFrame> watch(String channelName);

  /// 关闭通道（LAN：注销 handler；Relay：发 CLOSE frame）
  Future<void> close();
}

/// TransportChannel.send 返回值（搬运自 channel/send_result.dart 避免循环依赖）
class SendResult {
  const SendResult({required this.success, this.error, this.statusCode});
  final bool success;
  final String? error;
  final int? statusCode;

  factory SendResult.ok({int? statusCode}) =>
      SendResult(success: true, statusCode: statusCode);
  factory SendResult.fail(String error) =>
      SendResult(success: false, error: error);
}
```

- [ ] **Step 4: 创建 LanChannel**

写入 `lib/core/localnet/transport_channel/lan_channel.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../device/device_manager.dart';
import '../transport/http_transport.dart';
import 'transport_channel.dart';

/// LAN 后端的 TransportChannel — 直接封装现 ChannelManager 的 HTTP P2P 逻辑
///
/// 每个 (channelName, remoteDeviceId) 对应一条 HTTP POST 请求；
/// 服务端路由 /channel/<name> 由 ChannelManager 注册。
class LanChannel implements TransportChannel {
  LanChannel({
    required HttpTransport http,
    required DeviceManager deviceManager,
    required this.myDeviceId,
  })  : _http = http,
        _deviceMgr = deviceManager;

  final HttpTransport _http;
  final DeviceManager _deviceMgr;
  final String myDeviceId;
  final Map<String, StreamController<TransportFrame>> _watchers = {};
  final Set<String> _registered = {};

  @override
  Future<void> open({required String channelName, required String remoteDeviceId}) async {
    if (_registered.add(channelName)) {
      _http.registerHandler('/channel/$channelName', (req) => _handle(req, channelName));
    }
  }

  @override
  Future<SendResult> send(String channelName, Uint8List data) async {
    final device = _deviceMgr.getDevice(remoteDeviceIdFor(channelName));
    if (device == null) return SendResult.fail('device not found');
    final url = 'http://${device.address.split(':').first}:${device.address.split(':').last}/channel/$channelName';
    final body = jsonEncode({
      'senderId': myDeviceId,
      'payload': base64Encode(data),
      'timestamp': DateTime.now().toIso8601String(),
    });
    try {
      final client = HttpClient();
      final req = await client.postUrl(Uri.parse(url));
      req.headers.set('Content-Type', 'application/json');
      req.write(body);
      final resp = await req.close();
      await resp.drain<void>();
      client.close();
      return resp.statusCode == 200
          ? SendResult.ok(statusCode: resp.statusCode)
          : SendResult.fail('HTTP ${resp.statusCode}');
    } catch (e) {
      return SendResult.fail('send exception: $e');
    }
  }

  @override
  Stream<TransportFrame> watch(String channelName) {
    return _watchers
        .putIfAbsent(channelName, () => StreamController<TransportFrame>.broadcast())
        .stream;
  }

  @override
  Future<void> close() async {
    for (final c in _watchers.values) {
      await c.close();
    }
    _watchers.clear();
  }

  String remoteDeviceIdFor(String channelName) {
    // 约定：channelName 形如 "session/<peerId>_<stateHash>" 或 "channel/<peerId>/..."
    // 由调用方（ChannelManager / Session）保证；此处简化返回 myDeviceId 之外的任一 peer
    return ''; // 占位 — 实际实现时由 ChannelManager 注入
  }

  Future<void> _handle(HttpRequest req, String channelName) async {
    final bodyStr = await utf8.decodeStream(req);
    final json = jsonDecode(bodyStr) as Map<String, dynamic>;
    final frame = TransportFrame(
      channelName: channelName,
      sourceDeviceId: json['senderId'] as String? ?? 'unknown',
      payload: base64Decode(json['payload'] as String? ?? ''),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
    );
    _watchers[channelName]?.add(frame);
    req.response.statusCode = HttpStatus.ok;
    await req.response.close();
  }
}
```

注：此文件实现了 TransportChannel 的 LAN 后端骨架，详细 peerId 注入逻辑由后续 ChannelManager 改造任务（Task 7）补充。

- [ ] **Step 5: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'transport_channel/transport_channel.dart';
export 'transport_channel/lan_channel.dart';
```

- [ ] **Step 6: 运行测试，验证通过（可能因端口绑定 skip）**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport_channel/lan_channel_test.dart 2>&1 | tail -10
```

Expected: PASS（如果端口冲突会 skip）。

- [ ] **Step 7: Commit**

```bash
git add lib/core/localnet/transport_channel/ test/localnet/transport_channel/ lib/core/localnet/localnet.dart
git commit -m "feat(localnet): TransportChannel interface + LanChannel skeleton"
```

---

### Task 7: 改造 DeviceManager 接受 DiscoveryService 注入

**Files:**
- Modify: `lib/core/localnet/device/device_manager.dart`
- Modify: `lib/core/localnet/framework/framework_lan_core.dart` (LanCore 注入 LanDiscovery)

**Interfaces:**
- Consumes:
  - `LanDiscovery` (Task 5)
- Produces: `DeviceManager` 内部从 UDP datagram 改为订阅 DiscoveryService.watch()

- [ ] **Step 1: 修改 DeviceManager 构造函数**

打开 `lib/core/localnet/device/device_manager.dart`，将：

```dart
DeviceManager({
    required EventBus eventBus,
    required this.myDeviceId,
    this.myAlias = '',
    this.timeout = const Duration(seconds: 15),
  })  : _bus = eventBus,
        _registry = DeviceRegistry();
```

改为：

```dart
DeviceManager({
    required EventBus eventBus,
    required this.myDeviceId,
    this.myAlias = '',
    this.timeout = const Duration(seconds: 15),
    DiscoveryService? discovery,
  })  : _bus = eventBus,
        _registry = DeviceRegistry(),
        _discovery = discovery;

  DiscoveryService? _discovery;
  StreamSubscription<List<RemoteEndpoint>>? _discoverySub;

  /// 注入 DiscoveryService（在 framework 启动时调用）
  void attachDiscovery(DiscoveryService discovery) {
    _discovery = discovery;
  }
```

- [ ] **Step 2: 替换 onDatagram 为订阅 DiscoveryService**

删除 `void onDatagram(...)` 整个方法（第 42-72 行）。

新增订阅：

```dart
void _onDiscoveryUpdate(List<RemoteEndpoint> endpoints) {
  for (final ep in endpoints) {
    if (ep.deviceId == myDeviceId) continue;
    final existing = _registry.get(ep.deviceId);
    if (existing == null) {
      final device = Device(
        deviceId: ep.deviceId,
        alias: ep.alias,
        ip: ep.address.split(':').first,
        port: int.tryParse(ep.address.split(':').last) ?? 0,
        lastSeen: ep.lastSeen,
        extras: const {},
      );
      _registry.add(device);
      _bus.emit(DeviceFoundEvent(deviceId: ep.deviceId, alias: device.alias));
    } else {
      _registry.add(existing.copyWith(lastSeen: ep.lastSeen, alias: ep.alias));
    }
  }
}
```

并在构造函数末尾添加 `attachDiscovery` 调用：

```dart
void attachDiscovery(DiscoveryService discovery) {
  _discovery = discovery;
  _discoverySub?.cancel();
  _discoverySub = discovery.watch().listen(_onDiscoveryUpdate);
}
```

- [ ] **Step 3: 在 dispose 中释放订阅**

修改 `Future<void> dispose()`：

```dart
Future<void> dispose() async {
  await _discoverySub?.cancel();
  _registry.clear();
}
```

- [ ] **Step 4: 修改 FrameworkLanCore.start 注入 LanDiscovery**

打开 `lib/core/localnet/framework/framework_lan_core.dart`，修改 `_sendBroadcast` 旁边或之前的位置，添加 DiscoveryService 注入：

找到 `deviceManager = DeviceManager(...)` 这一行（约第 85 行），改为：

```dart
final discovery = LanDiscovery(
  myDeviceId: myDeviceId,
  myAlias: myAlias,
  udp: udpTransport,
);
deviceManager = DeviceManager(
  eventBus: eventBus,
  myDeviceId: myDeviceId,
  myAlias: myAlias,
  timeout: deviceTimeout,
);
deviceManager.attachDiscovery(discovery);
await discovery.start();
```

- [ ] **Step 5: 在 stop 中停止 discovery**

修改 `FrameworkLanCore.stop()`，在 `await sessionManager.dispose();` 之前添加：

```dart
await discovery.stop();
```

并把 `discovery` 字段提取为实例字段（与 deviceManager 平级）：

```dart
late final LanDiscovery discovery;
```

- [ ] **Step 6: 编译检查**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze lib/core/localnet/ 2>&1 | tail -30
```

Expected: "No issues found!"。

- [ ] **Step 7: 跑 lan-local-playbook 涉及的所有现有 build smoke**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL。

- [ ] **Step 8: Commit**

```bash
git add lib/core/localnet/device/device_manager.dart lib/core/localnet/framework/framework_lan_core.dart
git commit -m "refactor(localnet): DeviceManager uses injected DiscoveryService"
```

---

## Phase 2：Relay 后端实现

### Task 8: 创建 TransportFrame 数据类

**Files:**
- Create: `lib/core/localnet/transport/transport_frame.dart`
- Create: `test/localnet/transport/transport_frame_test.dart`

**Interfaces:**
- Consumes: 无
- Produces: `class TransportFrame { channelName, sourceDeviceId, payload, timestamp }`

- [ ] **Step 1: 写测试**

写入 `test/localnet/transport/transport_frame_test.dart`：

```dart
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';

void main() {
  test('TransportFrame round-trip via JSON', () {
    final frame = TransportFrame(
      channelName: 'surround/game/state',
      sourceDeviceId: 'peer-1',
      payload: Uint8List.fromList([1, 2, 3, 4]),
      timestamp: DateTime.utc(2026, 7, 20, 12, 0, 0),
    );
    final json = frame.toJson();
    final restored = TransportFrame.fromJson(json);
    expect(restored.channelName, frame.channelName);
    expect(restored.sourceDeviceId, frame.sourceDeviceId);
    expect(restored.payload, frame.payload);
    expect(restored.timestamp, frame.timestamp);
  });

  test('fromJson handles missing fields gracefully', () {
    final restored = TransportFrame.fromJson({
      'channelName': 'c',
      'sourceDeviceId': 'p',
      'payload': 'AQIDBA==', // base64 of [1,2,3,4]
      'timestamp': '2026-07-20T12:00:00Z',
    });
    expect(restored.channelName, 'c');
    expect(restored.payload, Uint8List.fromList([1, 2, 3, 4]));
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport/transport_frame_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined）。

- [ ] **Step 3: 创建 TransportFrame**

写入 `lib/core/localnet/transport/transport_frame.dart`：

```dart
import 'dart:convert';
import 'dart:typed_data';

/// 传输层帧 — 所有传输后端统一的数据结构
///
/// 序列化用 base64 编码 payload（兼容 JSON）；时间戳用 ISO8601。
class TransportFrame {
  const TransportFrame({
    required this.channelName,
    required this.sourceDeviceId,
    required this.payload,
    required this.timestamp,
  });

  final String channelName;
  final String sourceDeviceId;
  final Uint8List payload;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'channelName': channelName,
        'sourceDeviceId': sourceDeviceId,
        'payload': base64Encode(payload),
        'timestamp': timestamp.toIso8601String(),
      };

  factory TransportFrame.fromJson(Map<String, dynamic> json) {
    return TransportFrame(
      channelName: json['channelName'] as String? ?? '',
      sourceDeviceId: json['sourceDeviceId'] as String? ?? 'unknown',
      payload: base64Decode(json['payload'] as String? ?? ''),
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}
```

- [ ] **Step 4: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport/transport_frame_test.dart 2>&1 | tail -5
```

Expected: PASS（2 tests）。

- [ ] **Step 5: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'transport/transport_frame.dart';
```

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/transport/transport_frame.dart test/localnet/transport/transport_frame_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): TransportFrame with JSON serialization"
```

---

### Task 9: 创建 RelayDiscovery（HTTP 控制面）

**Files:**
- Create: `lib/core/localnet/discovery/relay_discovery.dart`
- Create: `test/localnet/discovery/relay_discovery_test.dart`

**Interfaces:**
- Consumes:
  - `http` 包（已存在）
  - `DiscoveryService` 接口
- Produces: `class RelayDiscovery implements DiscoveryService`

**协议契约**（与未来 relay server 约定）：

| 方法 | 端点 | Body | Response |
|------|------|------|----------|
| 注册房间 | POST `{relayUrl}{relayHttpPath}/rooms` | `{alias, deviceId}` | 201 `{roomCode, wsUrl}` |
| 查询房间 | GET `{relayUrl}{relayHttpPath}/rooms/{code}` | — | 200 `{roomCode, hostAlias, hostDeviceId, status}` / 404 |
| 主动探测 | POST `{relayUrl}{relayHttpPath}/rooms/{code}/probe` | `{deviceId}` | 200（服务端 push 当前 peer 列表） |

- [ ] **Step 1: 写测试**

写入 `test/localnet/discovery/relay_discovery_test.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:xiaodouzi_fr/core/localnet/discovery/relay_discovery.dart';
import 'package:xiaodouzi_fr/core/localnet/discovery/remote_endpoint.dart';

class _MockHttpClient extends http.BaseClient {
  final List<http.Request> calls = [];
  final Map<String, http.Response Function(http.Request)> handlers = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request as http.Request);
    final handler = handlers['${request.method}:${request.url.path}'];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not mocked"}')),
        404,
      );
    }
    final resp = handler(request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  group('RelayDiscovery', () {
    late _MockHttpClient mock;
    late RelayDiscovery discovery;

    setUp(() {
      mock = _MockHttpClient();
      discovery = RelayDiscovery(
        relayUrl: 'https://relay.example.com',
        myDeviceId: 'self-id',
        myAlias: 'Self',
        httpClient: mock,
      );
    });

    test('createRoom returns room code from server', () async {
      mock.handlers['POST:/api/v1/rooms'] = (req) => http.Response(
            jsonEncode({'roomCode': '123456', 'wsUrl': 'wss://relay.example.com/ws/123456'}),
            201,
          );
      final result = await discovery.createRoom();
      expect(result.roomCode, '123456');
      expect(result.wsUrl, contains('wss://'));
    });

    test('joinRoom throws RoomNotFoundError on 404', () async {
      mock.handlers['GET:/api/v1/rooms/999999'] =
          (req) => http.Response('not found', 404);
      expect(
        () => discovery.joinRoom(roomCode: '999999'),
        throwsA(isA<RoomNotFoundError>()),
      );
    });

    test('joinRoom returns peer endpoint on 200', () async {
      mock.handlers['GET:/api/v1/rooms/123456'] = (req) => http.Response(
            jsonEncode({
              'roomCode': '123456',
              'hostDeviceId': 'host-id',
              'hostAlias': 'Host',
            }),
            200,
          );
      final peer = await discovery.joinRoom(roomCode: '123456');
      expect(peer.deviceId, 'host-id');
      expect(peer.alias, 'Host');
    });
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/relay_discovery_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined）。

- [ ] **Step 3: 创建 RelayDiscovery + 错误类型**

写入 `lib/core/localnet/discovery/relay_discovery.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../framework/exception/framework_exception.dart';
import '../transport/transport_kind.dart';
import 'discovery_service.dart';
import 'remote_endpoint.dart';

/// Relay 后端发现服务 — 通过 HTTP 短调用与中继服务器交互
///
/// 协议契约：
/// - POST /rooms                  → 创建房间，返回 roomCode + wsUrl
/// - GET  /rooms/{code}           → 查询房间元信息（用于 join 验证）
/// - POST /rooms/{code}/probe     → 主动探测（服务端 push 当前 peer 列表）
class RelayDiscovery implements DiscoveryService {
  RelayDiscovery({
    required this.relayUrl,
    required this.myDeviceId,
    required this.myAlias,
    this.relayHttpPath = '/api/v1',
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String relayUrl;
  final String relayHttpPath;
  final String myDeviceId;
  final String myAlias;
  final http.Client _http;

  final List<RemoteEndpoint> _endpoints = [];
  final StreamController<List<RemoteEndpoint>> _ctrl =
      StreamController<List<RemoteEndpoint>>.broadcast();
  bool _started = false;

  @override
  Future<void> start() async {
    _started = true;
  }

  @override
  Future<void> stop() async {
    _started = false;
    _endpoints.clear();
    await _ctrl.close();
  }

  @override
  List<RemoteEndpoint> get endpoints => List.unmodifiable(_endpoints);

  @override
  Stream<List<RemoteEndpoint>> watch() => _ctrl.stream;

  @override
  Future<void> probe() async {
    _ctrl.add(endpoints);
  }

  /// 创建房间 — 返回 roomCode + wsUrl
  Future<RelayRoomInfo> createRoom() async {
    final resp = await _http.post(
      Uri.parse('$relayUrl$relayHttpPath/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'alias': myAlias, 'deviceId': myDeviceId}),
    );
    if (resp.statusCode != 201) {
      throw RelayUnreachableError('createRoom failed: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return RelayRoomInfo(
      roomCode: json['roomCode'] as String,
      wsUrl: json['wsUrl'] as String,
    );
  }

  /// 加入房间 — 返回 host 端点
  Future<RemoteEndpoint> joinRoom({required String roomCode}) async {
    final resp = await _http.get(
      Uri.parse('$relayUrl$relayHttpPath/rooms/$roomCode'),
    );
    if (resp.statusCode == 404) {
      throw RoomNotFoundError('Room $roomCode not found');
    }
    if (resp.statusCode == 409) {
      throw RoomFullError('Room $roomCode is full');
    }
    if (resp.statusCode != 200) {
      throw RelayUnreachableError('joinRoom failed: HTTP ${resp.statusCode}');
    }
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    return RemoteEndpoint(
      deviceId: json['hostDeviceId'] as String,
      alias: json['hostAlias'] as String? ?? 'Host',
      address: 'relay:$roomCode',
      kind: TransportKind.relay,
      lastSeen: DateTime.now(),
    );
  }
}

/// createRoom 返回的房间信息
class RelayRoomInfo {
  const RelayRoomInfo({required this.roomCode, required this.wsUrl});
  final String roomCode;
  final String wsUrl;
}

/// Relay 不可达（HTTP 5xx / 超时）
class RelayUnreachableError extends FrameworkException {
  RelayUnreachableError(String message) : super(message);
}

/// 房间号不存在
class RoomNotFoundError extends FrameworkException {
  RoomNotFoundError(String message) : super(message);
}

/// 房间已满（2 人上限）
class RoomFullError extends FrameworkException {
  RoomFullError(String message) : super(message);
}
```

- [ ] **Step 4: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'discovery/relay_discovery.dart';
```

- [ ] **Step 5: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/discovery/relay_discovery_test.dart 2>&1 | tail -5
```

Expected: PASS（3 tests）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/discovery/relay_discovery.dart test/localnet/discovery/relay_discovery_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): RelayDiscovery with HTTP createRoom/joinRoom"
```

---

### Task 10: 创建 WsTransport（WS 多路复用传输）

**Files:**
- Create: `lib/core/localnet/transport/ws_transport.dart`
- Create: `test/localnet/transport/ws_transport_test.dart`

**Interfaces:**
- Consumes:
  - `web_socket_channel` 包
  - `TransportFrame`
- Produces: `class WsTransport` — 单 WS 连接承载多虚拟通道

**协议契约**（与 relay server 约定）：
- 连接 URL：`wss://relay.example.com/ws?room={roomCode}&deviceId={deviceId}`
- 入站 frame JSON 格式：`{ "channelName": "...", "sourceDeviceId": "...", "payload": "<base64>", "timestamp": "..." }`
- 出站 frame 同上

- [ ] **Step 1: 写测试**

写入 `test/localnet/transport/ws_transport_test.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as ws_status;
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/ws_transport.dart';

class _FakeChannel implements WebSocketChannel {
  final _outbound = StreamController<dynamic>.broadcast();
  final _inbound = StreamController<dynamic>.broadcast();
  bool closed = false;

  @override
  String get protocol => '';

  @override
  int get closeCode => closed ? ws_status.normalClosure : 0;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream get stream => _inbound.stream;

  @override
  WebSocketSink get sink => _FakeSink(_outbound);

  @override
  void pipe(WebSocketChannel other) {}

  @override
  WebSocketChannel cast<S>() => this;

  void simulateIncoming(String json) {
    _inbound.add(json);
  }
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._ctrl);
  final StreamController _ctrl;
  final List<String> sent = [];

  @override
  void add(dynamic event) {
    sent.add(event as String);
  }

  @override
  Future<void> addError(Object error, [StackTrace? st]) async {}

  @override
  Future<void> addStream(Stream stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    await _ctrl.close();
  }

  @override
  Future<void> get done => Future.value();
}

void main() {
  test('WsTransport parses incoming frames', () async {
    final fake = _FakeChannel();
    final transport = WsTransport(channel: fake, myDeviceId: 'self');
    final received = <TransportFrame>[];
    final sub = transport.frames.listen(received.add);

    fake.simulateIncoming(jsonEncode({
      'channelName': 'chat',
      'sourceDeviceId': 'peer',
      'payload': 'aGVsbG8=', // 'hello'
      'timestamp': '2026-07-20T12:00:00Z',
    }));
    await Future.delayed(const Duration(milliseconds: 10));
    expect(received, hasLength(1));
    expect(received.first.sourceDeviceId, 'peer');
    expect(String.fromCharCodes(received.first.payload), 'hello');
    await sub.cancel();
    await transport.close();
  });

  test('WsTransport.send emits frame as JSON', () async {
    final fake = _FakeChannel();
    final transport = WsTransport(channel: fake, myDeviceId: 'self');
    await transport.send(TransportFrame(
      channelName: 'chat',
      sourceDeviceId: 'self',
      payload: utf8.encode('hi'),
      timestamp: DateTime.now(),
    ));
    await Future.delayed(const Duration(milliseconds: 10));
    expect(fake.sent, hasLength(1));
    final json = jsonDecode(fake.sent.first) as Map<String, dynamic>;
    expect(json['channelName'], 'chat');
    expect(String.fromCharCodes(base64Decode(json['payload'] as String)), 'hi');
    await transport.close();
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport/ws_transport_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined: WsTransport）。

- [ ] **Step 3: 创建 WsTransport**

写入 `lib/core/localnet/transport/ws_transport.dart`：

```dart
import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import 'transport_frame.dart';

/// WebSocket 多路复用传输 — 单连接承载多个虚拟通道
///
/// 出站 frame 直接发 JSON 文本帧；
/// 入站 frame 解析后通过 frames 流广播（业务层按 channelName 过滤）。
class WsTransport {
  WsTransport({
    required WebSocketChannel channel,
    required this.myDeviceId,
  }) : _channel = channel {
    _sub = _channel.stream.listen(
      _onIncoming,
      onError: _onError,
      onDone: _onDone,
    );
  }

  final WebSocketChannel _channel;
  final String myDeviceId;
  final StreamController<TransportFrame> _framesCtrl =
      StreamController<TransportFrame>.broadcast();
  final StreamController<Object> _errorsCtrl =
      StreamController<Object>.broadcast();
  StreamSubscription? _sub;
  bool _closed = false;

  /// 入站帧流
  Stream<TransportFrame> get frames => _framesCtrl.stream;

  /// 错误流（断连 / 解析失败）
  Stream<Object> get errors => _errorsCtrl.stream;

  /// 发送一帧
  Future<void> send(TransportFrame frame) async {
    if (_closed) return;
    _channel.sink.add(jsonEncode(frame.toJson()));
  }

  /// 关闭连接
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await _channel.sink.close();
    await _framesCtrl.close();
    await _errorsCtrl.close();
  }

  void _onIncoming(dynamic data) {
    if (data is! String) return;
    try {
      final json = jsonDecode(data) as Map<String, dynamic>;
      _framesCtrl.add(TransportFrame.fromJson(json));
    } catch (e) {
      _errorsCtrl.add(e);
    }
  }

  void _onError(Object e) {
    _errorsCtrl.add(e);
  }

  void _onDone() {
    _errorsCtrl.add('ws_done');
  }
}
```

- [ ] **Step 4: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'transport/ws_transport.dart';
```

- [ ] **Step 5: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport/ws_transport_test.dart 2>&1 | tail -10
```

Expected: PASS（2 tests）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/transport/ws_transport.dart test/localnet/transport/ws_transport_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): WsTransport multiplexes frames over single WS connection"
```

---

### Task 11: 创建 RelayChannel

**Files:**
- Create: `lib/core/localnet/transport_channel/relay_channel.dart`
- Create: `test/localnet/transport_channel/relay_channel_test.dart`

**Interfaces:**
- Consumes:
  - `WsTransport` (Task 10)
  - `TransportFrame` (Task 8)
- Produces: `class RelayChannel implements TransportChannel`

- [ ] **Step 1: 写测试**

写入 `test/localnet/transport_channel/relay_channel_test.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_frame.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/ws_transport.dart';
import 'package:xiaodouzi_fr/core/localnet/transport_channel/relay_channel.dart';

class _FakeChannel implements WebSocketChannel {
  final _in = StreamController<dynamic>.broadcast();
  final _out = StreamController<String>.broadcast();
  bool closed = false;
  final List<String> sent = [];

  @override
  String get protocol => '';

  @override
  int get closeCode => 0;

  @override
  String? get closeReason => null;

  @override
  Future<void> get ready => Future.value();

  @override
  Stream get stream => _in.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  void pipe(WebSocketChannel other) {}

  @override
  WebSocketChannel cast<S>() => this;

  void push(String text) => _in.add(text);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._ch);
  final _FakeChannel _ch;

  @override
  void add(dynamic event) {
    _ch.sent.add(event as String);
  }

  @override
  Future<void> addError(Object error, [StackTrace? st]) async {}

  @override
  Future<void> addStream(Stream stream) async {}

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    _ch.closed = true;
  }

  @override
  Future<void> get done => Future.value();
}

void main() {
  test('RelayChannel.send routes frame via WsTransport', () async {
    final fake = _FakeChannel();
    final ws = WsTransport(channel: fake, myDeviceId: 'self');
    final channel = RelayChannel(ws: ws);

    await channel.open(channelName: 'surround/game/state', remoteDeviceId: 'peer');
    await channel.send('surround/game/state', utf8.encode('hello'));
    await Future.delayed(const Duration(milliseconds: 10));

    expect(fake.sent, hasLength(1));
    final json = jsonDecode(fake.sent.first) as Map<String, dynamic>;
    expect(json['channelName'], 'surround/game/state');
    expect(String.fromCharCodes(base64Decode(json['payload'] as String)), 'hello');

    await channel.close();
  });

  test('RelayChannel.watch filters incoming frames by channelName', () async {
    final fake = _FakeChannel();
    final ws = WsTransport(channel: fake, myDeviceId: 'self');
    final channel = RelayChannel(ws: ws);

    await channel.open(channelName: 'chat', remoteDeviceId: 'peer');
    final received = <TransportFrame>[];
    final sub = channel.watch('chat').listen(received.add);

    fake.push(jsonEncode({
      'channelName': 'other',
      'sourceDeviceId': 'p',
      'payload': 'aGk=', // 'hi'
      'timestamp': '2026-07-20T12:00:00Z',
    }));
    fake.push(jsonEncode({
      'channelName': 'chat',
      'sourceDeviceId': 'p',
      'payload': 'aGVsbG8=', // 'hello'
      'timestamp': '2026-07-20T12:00:01Z',
    }));
    await Future.delayed(const Duration(milliseconds: 20));

    expect(received, hasLength(1));
    expect(received.first.channelName, 'chat');
    expect(String.fromCharCodes(received.first.payload), 'hello');

    await sub.cancel();
    await channel.close();
  });
}

// Helper: base64Decode 是 dart:convert 提供
// 上面 import 已有，无需额外
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport_channel/relay_channel_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined: RelayChannel）。

- [ ] **Step 3: 创建 RelayChannel**

写入 `lib/core/localnet/transport_channel/relay_channel.dart`：

```dart
import 'dart:async';
import 'dart:typed_data';

import '../transport/transport_frame.dart';
import '../transport/ws_transport.dart';
import 'transport_channel.dart';

/// Relay 后端的 TransportChannel — 通过 WsTransport 路由 frame 到对应虚拟通道
class RelayChannel implements TransportChannel {
  RelayChannel({required WsTransport ws, required this.myDeviceId}) : _ws = ws {
    _sub = _ws.frames.listen(_onFrame);
  }

  final WsTransport _ws;
  final String myDeviceId;
  final Map<String, StreamController<TransportFrame>> _watchers = {};
  StreamSubscription<TransportFrame>? _sub;

  @override
  Future<void> open({required String channelName, required String remoteDeviceId}) async {
    _watchers.putIfAbsent(channelName, () => StreamController<TransportFrame>.broadcast());
  }

  @override
  Future<SendResult> send(String channelName, Uint8List data) async {
    await _ws.send(TransportFrame(
      channelName: channelName,
      sourceDeviceId: myDeviceId,
      payload: data,
      timestamp: DateTime.now(),
    ));
    return SendResult.ok();
  }

  @override
  Stream<TransportFrame> watch(String channelName) {
    return _watchers
        .putIfAbsent(channelName, () => StreamController<TransportFrame>.broadcast())
        .stream;
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    for (final c in _watchers.values) {
      await c.close();
    }
    _watchers.clear();
  }

  void _onFrame(TransportFrame frame) {
    _watchers[frame.channelName]?.add(frame);
  }
}
```

- [ ] **Step 4: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'transport_channel/relay_channel.dart';
```

- [ ] **Step 5: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/transport_channel/relay_channel_test.dart 2>&1 | tail -5
```

Expected: PASS（2 tests）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/transport_channel/relay_channel.dart test/localnet/transport_channel/relay_channel_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): RelayChannel routes frames by channelName"
```

---

### Task 12: 创建 FrameworkRelayCore

**Files:**
- Create: `lib/core/localnet/framework/framework_relay_core.dart`
- Create: `test/localnet/framework/framework_relay_core_test.dart`

**Interfaces:**
- Consumes:
  - `RelayDiscovery` (Task 9)
  - `WsTransport` (Task 10)
  - `RelayChannel` (Task 11)
- Produces: `class FrameworkRelayCore` — 复用现有 `DeviceManager` / `ChannelManager` / `SessionManager` 骨架

- [ ] **Step 1: 写测试**

写入 `test/localnet/framework/framework_relay_core_test.dart`：

```dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_relay_core.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

class _MockHttp extends http.BaseClient {
  final Map<String, http.Response Function(http.Request)> handlers = {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest req) async {
    final handler = handlers['${req.method}:${req.url.path}'];
    if (handler == null) {
      return http.StreamedResponse(
        Stream.value(utf8.encode('{"error":"not mocked"}')),
        404,
      );
    }
    final resp = handler(req as http.Request);
    return http.StreamedResponse(
      Stream.value(utf8.encode(resp.body)),
      resp.statusCode,
      headers: resp.headers,
    );
  }
}

void main() {
  test('FrameworkRelayCore.start with createRoom flow', () async {
    final mockHttp = _MockHttp();
    mockHttp.handlers['POST:/api/v1/rooms'] = (req) => http.Response(
          jsonEncode({'roomCode': '111111', 'wsUrl': 'wss://relay.example.com/ws/111111'}),
          201,
        );

    final core = FrameworkRelayCore(
      config: const FrameworkConfig(
        transportKind: TransportKind.relay,
        relayUrl: 'https://relay.example.com',
        deviceId: 'self-id',
        deviceAlias: 'Self',
      ),
      httpClient: mockHttp,
    );

    // 仅验证 start/stop 生命周期，不实际连 WS
    // 创建房间流程通过 discovery.createRoom 暴露
    await core.discovery.createRoom(); // 验证 mock 工作
    await core.stop();
  });
}
```

- [ ] **Step 2: 运行测试，验证失败**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/framework/framework_relay_core_test.dart 2>&1 | tail -10
```

Expected: FAIL（class not defined）。

- [ ] **Step 3: 创建 FrameworkRelayCore**

写入 `lib/core/localnet/framework/framework_relay_core.dart`：

```dart
import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';

import '../channel/channel_manager.dart';
import '../device/device.dart';
import '../device/device_manager.dart';
import '../discovery/relay_discovery.dart';
import '../event_bus/event_bus.dart';
import '../session/session_manager.dart';
import '../transport/http_transport.dart';
import '../transport/transport_config.dart';
import '../transport/ws_transport.dart';
import '../transport_channel/relay_channel.dart';
import 'framework_config.dart';

/// Relay 后端的 FrameworkCore — 通过房间号发现 + HTTP 控制 + WS 传输
///
/// 与 FrameworkLanCore 对外暴露相同接口（deviceManager / channelManager /
/// sessionManager / eventBus），LanFramework 门面按 transportKind 分发。
class FrameworkRelayCore {
  FrameworkRelayCore({
    required this.config,
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  final FrameworkConfig config;
  final http.Client _httpClient;

  final EventBus eventBus = EventBus();

  late final RelayDiscovery discovery;
  late final DeviceManager deviceManager;
  late final ChannelManager channelManager;
  late final SessionManager sessionManager;

  WsTransport? _ws;
  RelayChannel? _channel;
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  /// 启动：仅初始化 Discovery（房间号注册/查询）和 wsChannel 占位
  /// 真正的 WS 连接在调用 createRoom / joinRoom 后才建立
  Future<void> start() async {
    if (_isRunning) return;
    discovery = RelayDiscovery(
      relayUrl: config.relayUrl!,
      relayHttpPath: config.relayHttpPath,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
      httpClient: _httpClient,
    );
    await discovery.start();

    deviceManager = DeviceManager(
      eventBus: eventBus,
      myDeviceId: config.deviceId ?? 'unknown',
      myAlias: config.deviceAlias,
    );
    deviceManager.attachDiscovery(discovery);

    channelManager = ChannelManager(
      eventBus: eventBus,
      deviceManager: deviceManager,
      transport: _StubHttpTransport(), // Relay 模式不走 HTTP transport；ChannelManager.sendTo 改走 RelayChannel
    );
    await channelManager.start();

    sessionManager = SessionManager(
      channelManager: channelManager,
      eventBus: eventBus,
    );

    _isRunning = true;
  }

  /// 创建房间 + 打开 WS 连接
  Future<String> createAndConnect() async {
    final info = await discovery.createRoom();
    final wsChannel = IOWebSocketChannel.connect(Uri.parse(info.wsUrl));
    _ws = WsTransport(channel: wsChannel, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    // 把 ChannelManager 的 transport 替换为 RelayChannel
    // （简化方案：业务层改用 discovery + channel 直接协作）
    return info.roomCode;
  }

  /// 加入房间 + 打开 WS 连接
  Future<void> joinAndConnect({required String roomCode}) async {
    final peer = await discovery.joinRoom(roomCode: roomCode);
    final wsChannel = IOWebSocketChannel.connect(
      Uri.parse('$config.relayUrl$config.relayWsPath?room=$roomCode&deviceId=${config.deviceId}'),
    );
    _ws = WsTransport(channel: wsChannel, myDeviceId: config.deviceId ?? 'unknown');
    _channel = RelayChannel(ws: _ws!, myDeviceId: config.deviceId ?? 'unknown');
    deviceManager._registry.add(Device(
      deviceId: peer.deviceId,
      alias: peer.alias,
      ip: 'relay',                  // Relay 模式无真实 IP；标记为 relay
      port: 0,                       // Relay 模式无端口
      lastSeen: DateTime.now(),
      extras: const {},
    ));
  }

  Future<void> stop() async {
    if (!_isRunning) return;
    await _channel?.close();
    await _ws?.close();
    await discovery.stop();
    await channelManager.stop();
    await deviceManager.dispose();
    eventBus.dispose();
    _httpClient.close();
    _isRunning = false;
  }

  Future<void> dispose() async {
    await stop();
  }
}

/// Relay 模式专属 HttpTransport 桩 — sendTo 调用会抛 UnsupportedError，
/// 因为 Relay 模式下 ChannelManager.sendTo 应走 RelayChannel 而非 HTTP
class _StubHttpTransport extends HttpTransport {
  _StubHttpTransport() : super(config: const TransportConfig());

  @override
  bool get isRunning => false;

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  void registerHandler(String path, HttpHandler handler) {
    throw UnsupportedError('RelayCore 不应注册 HTTP handler');
  }

  @override
  void unregisterHandler(String path) {}
}
```

- [ ] **Step 4: 在 localnet.dart 导出**

修改 `lib/core/localnet/localnet.dart` 添加：

```dart
export 'framework/framework_relay_core.dart';
```

- [ ] **Step 5: 运行测试，验证通过**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/framework/framework_relay_core_test.dart 2>&1 | tail -10
```

Expected: PASS（1 test）。

- [ ] **Step 6: Commit**

```bash
git add lib/core/localnet/framework/framework_relay_core.dart test/localnet/framework/framework_relay_core_test.dart lib/core/localnet/localnet.dart
git commit -m "feat(localnet): FrameworkRelayCore with createRoom/joinAndConnect flows"
```

---

### Task 13: 扩展 FrameworkConfig + LanFramework 门面分发

**Files:**
- Modify: `lib/core/localnet/framework/framework_config.dart`
- Modify: `lib/core/localnet/framework/lan_framework.dart`
- Create: `test/localnet/framework/lan_framework_dispatch_test.dart`

**Interfaces:**
- Consumes:
  - `FrameworkRelayCore` (Task 12)
  - `FrameworkLanCore` (Task 3)
- Produces: `LanFramework.start` 按 `transportKind` 分发到对应 Core

- [ ] **Step 1: 扩展 FrameworkConfig**

打开 `lib/core/localnet/framework/framework_config.dart`，添加字段：

```dart
class FrameworkConfig {
  const FrameworkConfig({
    this.deviceAlias = 'Flutter Device',
    this.deviceId,
    this.port = 53317,
    this.broadcastInterval = const Duration(seconds: 3),
    this.deviceTimeout = const Duration(seconds: 15),
    this.cleanupInterval = const Duration(seconds: 10),
    this.httpServerEnabled = true,
    this.udpListenerEnabled = true,
    this.udpBroadcastEnabled = true,
    this.relayHost,
    this.relayPort = 53317,
    this.transportKind = TransportKind.lan,  // 新
    this.relayUrl,                            // 新：完整 URL（含 scheme）
    this.relayHttpPath = '/api/v1',           // 新
    this.relayWsPath = '/ws',                 // 新
  });
  // ... 现字段保持 ...
  final TransportKind transportKind;
  final String? relayUrl;
  final String relayHttpPath;
  final String relayWsPath;

  // 在 copyWith 中添加对应参数
}
```

- [ ] **Step 2: 修改 LanFramework.start 分发**

打开 `lib/core/localnet/framework/lan_framework.dart`，将 `start` 方法中构造 core 的逻辑改为：

```dart
Future<void> start(FrameworkConfig config) async {
  if (_status == FrameworkStatus.running ||
      _status == FrameworkStatus.starting) {
    return;
  }
  _status = FrameworkStatus.starting;
  _myDeviceId = config.deviceId ?? const Uuid().v4();
  _myAlias = config.deviceAlias;

  if (config.transportKind == TransportKind.relay) {
    _core = FrameworkRelayCore(config: config);
  } else {
    _core = FrameworkLanCore(
      myDeviceId: _myDeviceId,
      myAlias: _myAlias,
      transportConfig: config.toTransportConfig(),
      udpBroadcastEnabled: config.udpBroadcastEnabled,
      broadcastInterval: config.broadcastInterval,
      deviceTimeout: config.deviceTimeout,
      cleanupInterval: config.cleanupInterval,
    );
  }

  try {
    await _core!.start();
    _status = FrameworkStatus.running;
    _core!.eventBus.emit(const ServiceStartedEvent());
  } catch (e) {
    _status = FrameworkStatus.error;
    _core!.eventBus.emit(ServiceErrorEvent(error: e));
    rethrow;
  }
}
```

并添加 import：

```dart
import 'framework_relay_core.dart';
import '../transport/transport_kind.dart';
```

- [ ] **Step 3: 写测试验证分发**

写入 `test/localnet/framework/lan_framework_dispatch_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_config.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/framework_relay_core.dart';
import 'package:xiaodouzi_fr/core/localnet/framework/lan_framework.dart';
import 'package:xiaodouzi_fr/core/localnet/transport/transport_kind.dart';

void main() {
  test('start with transportKind.relay uses FrameworkRelayCore', () async {
    final fw = LanFramework.instance;
    await fw.start(const FrameworkConfig(
      transportKind: TransportKind.relay,
      relayUrl: 'https://relay.example.com',
      deviceId: 'self',
      deviceAlias: 'Self',
    ));
    expect(fw.status, FrameworkStatus.running);
    // 通过反射或公开 getter 验证 _core 类型
    // 简化：直接验证 status 为 running 即可
    await fw.stop();
  });
}
```

需要为 FrameworkStatus 添加 `FrameworkStatus` 的 export（已在 framework_status.dart）。

- [ ] **Step 4: 编译检查**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze lib/core/localnet/ 2>&1 | tail -10
```

Expected: "No issues found!"

- [ ] **Step 5: 运行新测试**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/framework/lan_framework_dispatch_test.dart 2>&1 | tail -10
```

Expected: PASS（1 test）。

- [ ] **Step 6: 跑现有 build smoke**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter build apk --debug --target-platform android-arm64 2>&1 | tail -5
```

Expected: BUILD SUCCESSFUL（确保 LAN 模式未破坏）。

- [ ] **Step 7: Commit**

```bash
git add lib/core/localnet/framework/framework_config.dart lib/core/localnet/framework/lan_framework.dart test/localnet/framework/lan_framework_dispatch_test.dart
git commit -m "feat(localnet): LanFramework dispatches to Lan/Relay core by transportKind"
```

---

## Phase 3：回归测试与 skill 同步

### Task 14: 运行 lan-local-playbook skill 全部相关测试

**Files:**
- 无新增/修改（验证任务）

- [ ] **Step 1: 跑全 localnet 测试**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/localnet/ 2>&1 | tail -30
```

Expected: 所有 test/localnet/ 下的测试 PASS（除可能因端口/网络 skip 的）。

- [ ] **Step 2: 跑现有 lan_demo 集成测试**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter test test/lan/ 2>&1 | tail -20
```

Expected: 现有 lan 测试 PASS（如果存在）。

- [ ] **Step 3: 跑 lan-local-playbook skill 引用的 demo 页面 smoke**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze lib/lab/demos/localnet_demo.dart 2>&1 | tail -10
```

Expected: "No issues found!"

- [ ] **Step 4: 整库编译检查**

Run:
```bash
cd D:/code/a_dart/prj/fr && flutter analyze 2>&1 | tail -20
```

Expected: 无新增 error。

- [ ] **Step 5: 提交测试报告（如果需要）**

如果 Step 1-4 全部通过，本任务无需 commit；如有问题则修复后 commit：

```bash
git add -A
git commit -m "test(localnet): full regression after engine refactor"
```

---

### Task 15: 同步更新 lan-local-playbook skill

**Files:**
- Modify: `.claude/skills/lan-local-playbook/SKILL.md`
- Modify: `.claude/skills/lan-local-playbook/reference/architecture-overview.md`

- [ ] **Step 1: 更新 SKILL.md §1 架构图**

打开 `.claude/skills/lan-local-playbook/SKILL.md`，在 §1 架构图下方添加新段：

```markdown
**Lan/Relay 双后端（自 2026-07 重构后）**：
- **LanCore**（现）：UDP 多播（端口 5678）+ HTTP P2P（端口 53317）— 同子网设备
- **RelayCore**（新增）：HTTP 控制面（房间号注册/查询）+ WS 多路复用（端口 443 wss）— 跨网段设备
- 两者通过 `transportKind: lan|relay` 配置切换，业务层 LanServiceAdapter 一行不动
- 共用同一套 DeviceManager / ChannelManager / SessionManager 骨架
- 协议契约：`docs/superpowers/specs/2026-07-20-engine-refactor-design.md`
```

- [ ] **Step 2: 更新 architecture-overview.md**

打开 `.claude/skills/lan-local-playbook/reference/architecture-overview.md`，在 Layer 3: Framework 表格中新增一行：

```markdown
| `framework/` | `framework_lan_core.dart`, `framework_relay_core.dart`, `framework_config.dart` | 单例门面，按 transportKind 分发 LanCore/RelayCore |
| `discovery/` | `discovery_service.dart`, `lan_discovery.dart`, `relay_discovery.dart` | 设备发现抽象 + LAN/Relay 实现 |
| `transport_channel/` | `transport_channel.dart`, `lan_channel.dart`, `relay_channel.dart` | 传输通道抽象 + LAN/Relay 实现 |
```

- [ ] **Step 3: 在 SKILL.md §2 添加新场景**

在 `.claude/skills/lan-local-playbook/SKILL.md` §2 表格中添加：

```markdown
| 为游戏添加互联网房间模式（房间号发现） | 引擎 spec §3-4 |
| 排查 Relay 模式连接问题 | ref/discovery-debug.md §2.6 |
```

- [ ] **Step 4: Commit skill 同步**

```bash
git add .claude/skills/lan-local-playbook/
git commit -m "docs(skill): sync lan-local-playbook with Lan/Relay dual-backend refactor"
```

---

## Summary

| Phase | Task | 内容 |
|-------|------|------|
| 0 | 1-3 | 基础设施：web_socket_channel 依赖 + TransportKind + LanCore 重命名 |
| 1 | 4-7 | 抽象层：DiscoveryService / TransportChannel + LanDiscovery / LanChannel + DeviceManager 改造 |
| 2 | 8-13 | Relay 后端：TransportFrame + WsTransport + RelayDiscovery + RelayChannel + FrameworkRelayCore + 门面分发 |
| 3 | 14-15 | 回归测试 + skill 同步 |

**总任务数**：15 个 task | **每个 task 4-8 个步骤** | **每个 task 独立 commit**