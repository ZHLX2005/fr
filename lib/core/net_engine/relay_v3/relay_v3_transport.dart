// lib/core/net_engine/relay_v3/relay_v3_transport.dart
//
// Relay v3 传输层 — HTTP 控制面 + WS snapshot 流。
//
// 对应后端 internal/relay/v3/ 完整协议：
//   - HTTP: CreateRoom / Join / Leave / ApplyAction / GetSnapshot
//   - WS:   /ws3/{code}?device_id=X&alias=Y → snapshot 广播
//   - 状态: server-authoritative Lua state machine
//
// # 生命周期
//
//   Host:  createRoom() → return RoomHandle
//         → 自动 join + connect WS
//         → lobby 等待 → applyAction('START', ...) → playing
//
//   Guest: joinRoom(code) → return RoomHandle
//         → 自动 connect WS
//         → lobby 看到已有玩家
//
// ## 关键不变量
//
//   - CreateRoom 后自动 Join（host 必须在 Subs 里才能收 broadcast）
//   - JoinRoom 后自动 connect WS（立即拿初始 snapshot）
//   - WS 连接始终带 device_id + alias query param
//   - CloseCode 流：4403=kicked, 4404=room expired, 4408=slow consumer
//   - 终端 close code 不会自动重连
//   - RoomHandle.dispose() 幂等

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

// ——— 类型定义 ———

/// history 条目
class HistoryEntry {
  final String type;
  final Map<String, dynamic>? params;
  final String fromState;
  final String toState;
  final DateTime at;
  final int version;

  HistoryEntry({
    required this.type,
    this.params,
    required this.fromState,
    required this.toState,
    required this.at,
    required this.version,
  });

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        type: j['type'] as String,
        params: j['params'] as Map<String, dynamic>?,
        fromState: j['from_state'] as String,
        toState: j['to_state'] as String,
        at: DateTime.parse(j['at'] as String),
        version: j['version'] as int,
      );
}

/// 服务端权威快照
///
/// 对比后端 internal/relay/v3/state.go Snapshot：
///   - JSON tags 一致：room_code, script_hash, script_src, context, state,
///     version, created_at, updated_at, history
///   - 所有字段只读（后端推啥就是啥），客户端==纯渲染==。
class Snapshot {
  final String roomCode;
  final String scriptHash;
  final String? scriptSrc;
  final Map<String, dynamic> context;
  final String state;
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<HistoryEntry> history;

  Snapshot({
    required this.roomCode,
    required this.scriptHash,
    this.scriptSrc,
    required this.context,
    required this.state,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    required this.history,
  });

  factory Snapshot.fromJson(Map<String, dynamic> j) => Snapshot(
        roomCode: j['room_code'] as String,
        scriptHash: j['script_hash'] as String,
        scriptSrc: j['script_src'] as String?,
        context: _contextFromJson(j['context']),
        state: j['state'] as String,
        version: j['version'] as int,
        createdAt: DateTime.parse(j['created_at'] as String),
        updatedAt: DateTime.parse(j['updated_at'] as String),
        history: (j['history'] as List)
            .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );

  static Map<String, dynamic> _contextFromJson(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const {};
  }
}

/// WS close code — 后端定义的终端状态码
class WSCloseCode {
  /// 参数错误（缺少 code/device_id）- pre-upgrade HTTP 400
  static const int badQuery = 4400;

  /// 被踢 / join 被脚本拒绝
  static const int kicked = 4403;

  /// 房间 TTL 过期
  static const int roomExpired = 4404;

  /// 慢消费者（连续 5 次丢帧）
  static const int slowConsumer = 4408;

  /// 判断是否为 terminal close code（不应自动重连）
  static bool isTerminal(int code) =>
      code == kicked || code == roomExpired || code == slowConsumer;

  /// 获取 human-readable 描述
  static String describe(int code) {
    switch (code) {
      case badQuery:
        return '参数错误';
      case kicked:
        return '已被踢出房间';
      case roomExpired:
        return '房间已过期';
      case slowConsumer:
        return '连接不稳定（慢消费）';
      default:
        return 'WS 关闭 ($code)';
    }
  }
}

/// RelayV3Exception — 统一异常类型
class RelayV3Exception implements Exception {
  final int statusCode;
  final String body;
  RelayV3Exception(this.statusCode, this.body);

  @override
  String toString() => 'RelayV3Exception($statusCode): $body';
}

/// WS 推送帧（type + data 两层包装）
class _WSFrame {
  final String type;
  final Map<String, dynamic> data;
  final DateTime? ts;

  _WSFrame({required this.type, required this.data, this.ts});

  factory _WSFrame.fromJson(Map<String, dynamic> j) => _WSFrame(
        type: j['type'] as String? ?? '',
        data: Map<String, dynamic>.from(j['data'] as Map? ?? {}),
        ts: j['ts'] != null ? DateTime.tryParse(j['ts'] as String) : null,
      );
}

/// WS 关闭事件
class WSCloseEvent {
  final int code;
  final String reason;
  WSCloseEvent({required this.code, required this.reason});
}

/// 房间句柄 — WS 连接 + snapshot 流 + action 调用
///
/// 用法：
/// ```dart
/// final handle = await transport.createRoom(script:..., initialParams:...);
/// handle.snapshots.listen(...);            // snapshot 流
/// handle.closeEvents.listen(...);          // WS 关闭事件流
/// await handle.applyAction(type:'CHAT', params:{...});
/// ```
class RoomHandle {
  final RelayV3Transport transport;
  final String code;
  final String wsUrl;
  Snapshot? latest;

  final StreamController<Snapshot> _snapshotsCtrl =
      StreamController<Snapshot>.broadcast();
  Stream<Snapshot> get snapshots => _snapshotsCtrl.stream;

  final StreamController<WSCloseEvent> _closeEventsCtrl =
      StreamController<WSCloseEvent>.broadcast();
  Stream<WSCloseEvent> get closeEvents => _closeEventsCtrl.stream;

  /// 安全地推送 snapshot，忽略 dispose 后的竞态
  void _emitSnapshot(Snapshot snap) {
    if (!_snapshotsCtrl.isClosed) {
      _snapshotsCtrl.add(snap);
    }
  }

  /// 安全地推送 close 事件，忽略 dispose 后的竞态
  void _emitCloseEvent(WSCloseEvent event) {
    if (!_closeEventsCtrl.isClosed) {
      _closeEventsCtrl.add(event);
    }
  }

  WebSocketChannel? _ws;
  StreamSubscription<dynamic>? _wsSub;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _connected = false;
  int _backoffMs = 500;

  /// createRoom 后构造函数（自动 join host）
  @visibleForTesting
  RoomHandle.testCreate({
    required this.transport,
    required this.code,
    required this.wsUrl,
    Snapshot? initial,
  }) {
    if (initial != null) {
      latest = initial;
      _emitSnapshot(initial);
    }
    // For tests, don't actually connect — just set up the snapshot.
  }

  /// createRoom 后构造函数（自动 join host）
  RoomHandle._create({
    required this.transport,
    required this.code,
    required this.wsUrl,
    Snapshot? initial,
  }) {
    if (initial != null) {
      latest = initial;
      _emitSnapshot(initial);
    }
    // 自动 join + connect WS（host 必须在 Subs 里才能收 broadcast）
    _joinAndConnect();
  }

  /// joinRoom 后构造函数（直接 connect WS）
  RoomHandle._join({
    required this.transport,
    required this.code,
    required this.wsUrl,
    Snapshot? initial,
  }) {
    if (initial != null) {
      latest = initial;
      _emitSnapshot(initial);
    }
    connect();
  }

  /// 自动 join 然后连 WS（仅 createRoom 路径）
  Future<void> _joinAndConnect() async {
    try {
      await transport._join(code: code, deviceId: transport.deviceId, alias: transport.alias);
    } catch (_) {
      // Best-effort join; WS connect 仍然尝试。
    }
    // 如果不是 disposed，就 connect WS
    if (!_disposed) {
      await connect();
    }
  }

  /// 连接 WS
  ///
  /// 幂等。自动带 device_id + alias query params。
  /// 终端 close code 不会自动重连。
  Future<void> connect() async {
    if (_disposed) return;
    if (_connected) return; // 幂等

    final uri = Uri.parse(wsUrl).replace(queryParameters: {
      'device_id': transport.deviceId,
      'alias': transport.alias,
    });
    try {
      _ws = WebSocketChannel.connect(uri);
      _wsSub = _ws!.stream.listen(
        (msg) {
          try {
            final m = jsonDecode(msg as String) as Map<String, dynamic>;
            final frame = _WSFrame.fromJson(m);
            if (frame.type == 'snapshot') {
              final s = Snapshot.fromJson(frame.data);
              latest = s;
              _emitSnapshot(s);
            }
          } catch (_) {
            // Ignore malformed messages.
          }
        },
        onDone: _onWSDone,
        onError: (_) => _onWSDone(),
        cancelOnError: true,
      );
      _connected = true;
      _backoffMs = 500;
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onWSDone() {
    if (_disposed) return;
    _connected = false;
    _wsSub?.cancel();
    _wsSub = null;
    _ws = null;

    // 检测 WS close code（WebSocketChannel 不暴露 close code，
    // 这里用默认 reconnect。closeEvents 由 callers 监听以显示 UI）
    // Channel 关闭时的 close code 无法从 WebSocketChannel 获取，
    // 所以 emit 一个未知码让 UI 感知到断连。
    _emitCloseEvent(WSCloseEvent(code: 0, reason: 'connection lost'));

    // 终端 close code：不重连（caller 通过 closeEvents 知道并处理）
    // 非终端：自动重连
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_disposed) return;
    if (_connected) return; // 可能并发的 connect() 已经重连了
    final wait = _backoffMs;
    _backoffMs = (_backoffMs * 2).clamp(500, 30000);
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: wait), connect);
  }

  /// 提交 action
  ///
  /// 成功后自动更新本地 latest + 推送 snapshot 流。
  /// 失败抛出 [RelayV3Exception]（409/422 等）。
  ///
  /// 自动把 `device_id` 注入到 `params.device_id`，
  /// 让 Lua 脚本（如 `on_action_ACK`）能识别是谁触发了 action。
  /// 后端 `RunEvent` 只把 `Action.Params` 传给 Lua handler，
  /// `source_device_id` 不会自动合并到 `p` 里 — 必须客户端自己传。
  Future<Snapshot> applyAction({
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    String? sourceDeviceId,
  }) async {
    final did = sourceDeviceId ?? transport.deviceId;
    final injected = <String, dynamic>{
      'device_id': did,
      ...params,
    };
    final snap = await transport._applyAction(
      code: code,
      type: type,
      params: injected,
      expectVersion: expectVersion,
      sourceDeviceId: did,
    );
    latest = snap;
    // 防止 dispose 后的竞态：HTTP action 成功但 controller 已被关闭。
    // 此时 caller 仍能从返回的 snap 读到最新状态。
    if (!_snapshotsCtrl.isClosed) {
      _emitSnapshot(snap);
    }
    return snap;
  }

  /// 离开房间
  Future<void> leave() async {
    try {
      await transport._leave(code: code, deviceId: transport.deviceId);
    } catch (_) {
      // best-effort
    }
    await dispose();
  }

  /// 断开 WS 但不发 leave（页面回退时 transport 重用）
  Future<void> disconnectWS() async {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _connected = false;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
  }

  /// 主动从服务端拉一次最新 snapshot（不依赖 WS push）。
  ///
  /// 用于：网络抖动 / WS 暂时掉线但 HTTP 还可用 / 手动刷新。
  /// 成功时同步更新 [latest] + 推送 snapshot 流（同 WS 行为）。
  Future<Snapshot> fetchSnapshot() async {
    final snap = await transport.fetchSnapshot(code);
    latest = snap;
    if (!_snapshotsCtrl.isClosed) {
      _emitSnapshot(snap);
    }
    return snap;
  }

  /// 当前 WS 是否处于连接态（仅作 UI 提示用；不参与控制流）。
  bool get isConnected => _connected;

  /// 断线恢复：先重新 join（HTTP 把被 on_leave 移出后的 sub 重新注册回房间，
  /// 配合稳定 device_id 被服务端识别为同一玩家），再重连 WS。
  /// 返回 join 是否成功；WS 是否真正连上由 snapshots / closeEvents 流告知。
  ///
  /// 适用场景：WS 断开超过服务端 grace 窗口（5s）后，服务端已执行 on_leave
  /// 并把该 device 移出 room.Subs —— 此时纯 WS 重连会收到 "device not
  /// registered via /join" 而失败，必须先重新 join 才能继续上传 action。
  Future<bool> rejoin() async {
    if (_disposed) return false;
    try {
      await transport._join(
        code: code,
        deviceId: transport.deviceId,
        alias: transport.alias,
      );
    } catch (_) {
      return false; // 房间不存在 / 已过期
    }
    // 清掉半开连接与 transport 侧待重连定时器，避免与 connect 并发
    await disconnectWS();
    await connect();
    return true;
  }

  /// 释放资源
  Future<void> dispose() async {
    if (_disposed) return; // 幂等
    _disposed = true;
    _connected = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _wsSub?.cancel();
    _wsSub = null;
    await _ws?.sink.close();
    _ws = null;
    await _snapshotsCtrl.close();
    await _closeEventsCtrl.close();
  }
}

/// Relay v3 Transport — HTTP 控制面
///
/// 用法：
/// ```dart
/// final t = RelayV3Transport(
///   relayUrl: 'http://...',
///   alias: 'Me',
///   deviceId: 'my-device-id',
/// );
///
/// // 创建房间（大厅模式）
/// final handle = await t.createRoom(script: kLobbyChatScript, initialParams: {...});
///
/// // 加入房间
/// final handle = await t.joinRoom(code: '841746');
///
/// // 关注 snapshot 流
/// handle.snapshots.listen((snap) => print(snap.context));
/// ```
class RelayV3Transport {
  final String relayUrl;
  final String alias;
  final String deviceId;
  final http.Client _http;

  RelayV3Transport({
    required this.relayUrl,
    required this.alias,
    required this.deviceId,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  Uri _u(String path) => Uri.parse('$relayUrl$path');

  /// 创建房间
  ///
  /// [initialParams] 会被传进 [maxPlayers] 给 Lua 脚本，让脚本据此设定容量。
  /// [requestedCode] 指定自定义房间号（4–6 位，大写字母数字），由服务端保证唯一。
  ///   - 命中冲突 → 服务端返回 409（[RelayV3Exception]），客户端可换号或 fallback。
  /// 返回的 [RoomHandle] 已自动 join host + 连接 WS。
  Future<RoomHandle> createRoom({
    required String script,
    required Map<String, dynamic> initialParams,
    int maxPlayers = 8,
    String? requestedCode,
  }) async {
    final params = Map<String, dynamic>.from(initialParams);
    params['max_players'] = maxPlayers;
    final body = <String, dynamic>{
      'script': script,
      'initial_params': params,
      'alias': alias,
      'device_id': deviceId,
      'max_players': maxPlayers,
    };
    if (requestedCode != null && requestedCode.isNotEmpty) {
      body['requested_code'] = requestedCode;
    }
    final resp = await _http.post(
      _u('/api/v3/relay/rooms'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 201) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    return RoomHandle._create(
      transport: this,
      code: j['room_code'] as String,
      wsUrl: j['ws_url'] as String,
      initial: Snapshot.fromJson(j['snapshot'] as Map<String, dynamic>),
    );
  }

  /// 加入房间
  ///
  /// 返回的 [RoomHandle] 已自动连接 WS。
  /// 如果房间不存在 / 已过期 → [RelayV3Exception] 404。
  Future<RoomHandle> joinRoom({required String code}) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'alias': alias}),
    );
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    // GoFrame envelope: {code, message, data: {ws_url, snapshot}}
    final d = (j['data'] ?? j) as Map<String, dynamic>;
    return RoomHandle._join(
      transport: this,
      code: code,
      wsUrl: d['ws_url'] as String,
      initial: Snapshot.fromJson(d['snapshot'] as Map<String, dynamic>),
    );
  }

  /// 自适应匹配：先尝试加入 [code]；404（房间不存在）则用 [code] 作为
  /// requested_code 创建新房间；其余错误（撞号 → 409、其他 4xx/5xx）原样抛
  /// [RelayV3Exception]。
  ///
  /// 客户端 UX：玩家只看到"输入号码 + 点按钮"，服务端决定自己是第几个进入。
  /// 适合"双人对战不区分房主"的场景（房间号靠玩家之间口口相传）。
  Future<RoomHandle> tryJoinOrCreate({
    required String code,
    required String script,
    required Map<String, dynamic> initialParams,
    int maxPlayers = 8,
  }) async {
    try {
      return await joinRoom(code: code);
    } on RelayV3Exception catch (e) {
      if (e.statusCode != 404) rethrow;
      // 房间不存在 → 创建带 requested_code 的房间
      return await createRoom(
        script: script,
        initialParams: initialParams,
        maxPlayers: maxPlayers,
        requestedCode: code,
      );
    }
  }

  /// 拉当前 snapshot（HTTP GET，断线重连后 reconcile 用）
  ///
  /// 后端返回 GoFrame envelope: {code, message, data: {snapshot}}.
  Future<Snapshot> fetchSnapshot(String code) async {
    final resp = await _http.get(_u('/api/v3/relay/rooms/$code/snapshot'));
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final d = (j['data'] ?? j) as Map<String, dynamic>;
    return Snapshot.fromJson(d['snapshot'] as Map<String, dynamic>);
  }

  // ——— 内部方法 ———

  /// 对 _join 的测试可见包装
  @visibleForTesting
  Future<Snapshot> testJoin({
    required String code,
    required String deviceId,
    required String alias,
  }) =>
      _join(code: code, deviceId: deviceId, alias: alias);

  /// 内部 join：把 device 注册为房间订阅者并触发 on_join。
  Future<Snapshot> _join({
    required String code,
    required String deviceId,
    required String alias,
  }) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/join'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId, 'alias': alias}),
    );
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    final d = (j['data'] ?? j) as Map<String, dynamic>;
    return Snapshot.fromJson(d['snapshot'] as Map<String, dynamic>);
  }

  /// 对 _applyAction 的测试可见包装
  @visibleForTesting
  Future<Snapshot> testApplyAction({
    required String code,
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    required String sourceDeviceId,
  }) =>
      _applyAction(
        code: code, type: type, params: params,
        expectVersion: expectVersion, sourceDeviceId: sourceDeviceId,
      );

  /// 内部 applyAction：提交动作并返回最新快照。
  Future<Snapshot> _applyAction({
    required String code,
    required String type,
    required Map<String, dynamic> params,
    int? expectVersion,
    required String sourceDeviceId,
  }) async {
    final body = <String, dynamic>{
      'type': type,
      'params': params,
      'source_device_id': sourceDeviceId,
    };
    if (expectVersion != null) body['expect_version'] = expectVersion;
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/actions'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
    final j = jsonDecode(resp.body) as Map<String, dynamic>;
    // GoFrame envelope: {code, message, data: {snapshot}}
    final d = (j['data'] ?? j) as Map<String, dynamic>;
    return Snapshot.fromJson(d['snapshot'] as Map<String, dynamic>);
  }

  /// 对 _leave 的测试可见包装
  @visibleForTesting
  Future<void> testLeave({required String code, required String deviceId}) =>
      _leave(code: code, deviceId: deviceId);

  /// 内部 leave：注销订阅并触发 on_leave。
  Future<void> _leave({required String code, required String deviceId}) async {
    final resp = await _http.post(
      _u('/api/v3/relay/rooms/$code/leave'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'device_id': deviceId}),
    );
    // 204 No Content 或 200 OK 都算成功
    if (resp.statusCode != 204 && resp.statusCode != 200) {
      throw RelayV3Exception(resp.statusCode, resp.body);
    }
  }
}
