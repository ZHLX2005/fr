// lib/core/surround_game/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 引擎的边界。
//
// 新引擎模式：Transport 由 Discovery widget 创建并交回（onPeerSelected），
// 业务层通过 adapter.attach(transport) 绑定，通过 DataLog 同步游戏状态。
//
// 统一支持 LAN 和 Relay — Transport 抽象层消除了模式分支。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import '../game_room.dart';
import '../../models/game_state.dart';
import '../../engine/game_engine.dart';
import '../protocol/lan_messages.dart';
import '../persistence/player_profile_service.dart';

/// 适配器错误
class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _GameServiceAdapterImpl();

  /// 绑定一个已建立连接的 Transport（由 Discovery widget 交回）
  void attach(fw.Transport transport, {required String alias});

  /// 解绑，清理订阅
  void detach();

  bool get isRunning;
  String get myDeviceId;
  String get myAlias;

  /// 当前 scope 内的 peer id 列表
  Stream<List<String>> watchPeers();

  /// 房间事件流（协议消息桥接）
  Stream<LanRoomEvent> watchRoomEvents();

  /// 错误流
  Stream<LanServiceError> watchErrors();

  /// 创建游戏房间
  Future<String> createRoom(GameRoom room);

  /// 加入游戏房间的游戏 scope
  void joinGameScope(String roomId);

  /// 接受用户的加入请求
  Future<void> acceptJoin(String clientDeviceId);

  /// 注册游戏状态回调（game page 在 initState 调用）
  void onGameStateChanged(void Function(GameState)? cb);

  /// 推送游戏状态（本地 → scope）
  void syncGameState(GameState newState);

  /// 当前加入的游戏 scope 名
  String? get currentGameScope;

  /// 关闭房间
  Future<void> closeRoom(String roomId);
}

class _GameServiceAdapterImpl implements LanServiceAdapter {
  fw.Transport? _transport;
  String? _alias;
  String? _gameScope;
  bool _isRunning = false;

  // scope 数据监听
  StreamSubscription<fw.DataLog>? _gameScopeSub;

  // 事件总线
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();
  final StreamController<List<String>> _peersCtrl =
      StreamController<List<String>>.broadcast();
  final Set<String> _peers = {};
  StreamSubscription<fw.TransportEvent>? _eventSub;

  // 游戏状态回调（由 game page 注册）
  void Function(GameState)? _onGameStateChanged;

  @override
  bool get isRunning => _isRunning;

  @override
  String get myDeviceId => _transport?.myNodeId ?? '';

  @override
  String get myAlias => _alias ?? '';

  @override
  String? get currentGameScope => _gameScope;

  @override
  void attach(fw.Transport transport, {required String alias}) {
    detach();
    _transport = transport;
    _alias = alias;
    _isRunning = true;

    // 监听事件总线：peer 加入/离开
    _eventSub = transport.events.listen((ev) {
      if (ev.topic == 'peer-joined-scope') {
        final from = ev.data['from'] as String?;
        if (from != null && from != transport.myNodeId) {
          _peers.add(from);
          _peersCtrl.add(List.unmodifiable(_peers));
        }
      }
    });
  }

  @override
  void detach() {
    _eventSub?.cancel();
    _eventSub = null;
    _gameScopeSub?.cancel();
    _gameScopeSub = null;
    _peers.clear();
    _peersCtrl.add(List.unmodifiable(_peers));
    _gameScope = null;
    _transport = null;
    _alias = null;
    _onGameStateChanged = null;
    _isRunning = false;
  }

  @override
  Stream<List<String>> watchPeers() => _peersCtrl.stream;

  @override
  Stream<LanRoomEvent> watchRoomEvents() => _roomEventsCtrl.stream;

  @override
  Stream<LanServiceError> watchErrors() => _errorsCtrl.stream;

  // ============ 房间生命周期 ============

  @override
  Future<String> createRoom(GameRoom room) async {
    final t = _transport;
    if (t == null) throw LanServiceError('未连接');
    _gameScope = 'game-${room.roomId}';
    await t.joinScope(_gameScope!);
    _watchGameScope();

    // 初始写入：host 身份 + phase=waiting
    final log = t.getScope(_gameScope!);
    log?.merge({
      'phase': 'waiting',
      'host': {'id': t.myNodeId, 'alias': _alias},
    }, localNodeId: t.myNodeId);
    t.broadcastScope(_gameScope!);

    // 广播房间通知（兼容旧协议）
    _roomEventsCtrl.add(HostRoomAnnounced(
      room: room,
      hostDeviceId: t.myNodeId,
      hostAlias: _alias ?? '',
    ));
    return room.roomId;
  }

  @override
  void joinGameScope(String roomId) {
    final t = _transport;
    if (t == null) return;
    _gameScope = 'game-$roomId';
    t.joinScope(_gameScope!);
    _watchGameScope();

    // 写入：client 身份 + join 请求
    final log = t.getScope(_gameScope!);
    log?.merge({
      'client': {'id': t.myNodeId, 'alias': _alias, 'joinRequested': true},
    }, localNodeId: t.myNodeId);
    t.broadcastScope(_gameScope!);
  }

  void _watchGameScope() {
    final scope = _gameScope;
    final t = _transport;
    if (scope == null || t == null) return;
    _gameScopeSub?.cancel();
    _gameScopeSub = t.watchScope(scope).listen((log) {
      _onGameScopeChanged(log);
    });
  }

  void _onGameScopeChanged(fw.DataLog log) {
    final fromId = log.fromNodeId;
    final t = _transport;
    if (t == null || fromId == t.myNodeId) return;

    // 解析 scope 状态变化 → 触发事件
    final phase = log.state['phase'] as String? ?? '';
    final host = log.state['host'] as Map<String, dynamic>?;
    final client = log.state['client'] as Map<String, dynamic>?;

    // client 请求加入
    if (client?['joinRequested'] == true && host != null) {
      _roomEventsCtrl.add(ClientJoinRequested(
        clientDeviceId: client!['id'] as String,
        clientAlias: client['alias'] as String? ?? '?',
        roomId: scopeFromLog(log) ?? '',
      ));
    }

    // host 接受加入
    if (host?['accepted'] == true && client != null) {
      _roomEventsCtrl.add(ClientJoinResult(
        roomId: scopeFromLog(log) ?? '',
        clientDeviceId: client['id'] as String,
        accepted: true,
      ));
    }

    // gameState 变化 → 更新本地 notifier
    if (phase == 'playing') {
      final gsRaw = log.state['gameState'] as Map<String, dynamic>?;
      if (gsRaw != null) {
        final gs = QuoridorEngine.replayHistory(
          GameState.fromJson(gsRaw).history,
        );
        _onGameStateChanged?.call(gs);
      }
    }

    // host 关闭房间
    if (log.state['closed'] == true) {
      _roomEventsCtrl.add(HostRoomClosed(
        roomId: scopeFromLog(log) ?? '',
      ));
    }
  }

  String? scopeFromLog(fw.DataLog log) {
    final parts = log.scope.split('-');
    return parts.length >= 2 ? parts.sublist(1).join('-') : log.scope;
  }

  // ============ 游戏状态同步 ============

  @override
  void syncGameState(GameState newState) {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    if (log == null) return;
    log.merge({'gameState': newState.toJson()}, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
  }

  /// 注册游戏状态回调（game page 在 initState 调用）
  void onGameStateChanged(void Function(GameState)? cb) {
    _onGameStateChanged = cb;
  }

  // ============ 房间关闭 ============

  @override
  Future<void> closeRoom(String roomId) async {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    log?.merge({'closed': true}, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
    // 广播关房事件
    _roomEventsCtrl.add(HostRoomClosed(roomId: roomId));
  }

  Future<void> acceptJoin(String clientDeviceId) async {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    if (log == null) return;
    log.merge({
      'phase': 'playing',
      'client': {
        ...((log.state['client'] as Map?)?.cast<String, dynamic>() ?? {}),
        'accepted': true,
      },
      'gameState': QuoridorEngine.initialize().toJson(),
    }, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
  }

  Future<void> sendJoinRequest() async {
    // joinGameScope 已经通过 DataLog 写了 joinRequested
    // 此方法保持签名兼容，但实际逻辑在 joinGameScope 内
  }
}
