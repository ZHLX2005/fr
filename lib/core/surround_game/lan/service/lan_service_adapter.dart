// lib/core/surround_game/lan/service/lan_service_adapter.dart
//
// 业务层唯一接触 localnet 引擎的边界。
//
// Discovery widget（LanDiscovery / RelayDiscovery）处理发现 + HTTP 三次握手，
// onPeerSelected 返回的 transport 已经是双向可信任连接。
// 业务层只需要：1) attach transport，2) 创建/加入房间，3) 通过 DataLog scope
// 同步游戏状态。

import 'dart:async';

import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import '../game_room.dart';
import '../../models/game_state.dart';
import '../../engine/game_engine.dart';
import '../protocol/lan_messages.dart';

/// 适配器错误
class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

/// 业务层 LAN 服务适配器（具体类，可直接 new）
class LanServiceAdapter {
  static LanServiceAdapter instance = LanServiceAdapter();

  /// 绑定一个已建立双向连接的 Transport（由 Discovery widget 交回）
  void attach(fw.Transport transport, {required String alias}) {
    detach();
    _transport = transport;
    _alias = alias;
    _isRunning = true;

    _eventSub = transport.events.listen((ev) {
      // 关房事件由 host 写入 DataLog 触发
    });
  }

  /// 解绑，清理订阅
  void detach() {
    _eventSub?.cancel();
    _eventSub = null;
    _gameScopeSub?.cancel();
    _gameScopeSub = null;
    _gameScope = null;
    _transport = null;
    _alias = null;
    _onGameStateChanged = null;
    _isRunning = false;
  }

  fw.Transport? _transport;
  String? _alias;
  String? _gameScope;
  bool _isRunning = false;

  StreamSubscription<fw.DataLog>? _gameScopeSub;
  StreamSubscription<fw.TransportEvent>? _eventSub;

  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();

  void Function(GameState)? _onGameStateChanged;

  bool get isRunning => _isRunning;
  String get myDeviceId => _transport?.myNodeId ?? '';
  String get myAlias => _alias ?? '';
  String? get currentGameScope => _gameScope;

  Stream<LanRoomEvent> watchRoomEvents() => _roomEventsCtrl.stream;
  Stream<LanServiceError> watchErrors() => _errorsCtrl.stream;

  /// 创建游戏房间（host 调用）
  Future<String> createRoom(GameRoom room) async {
    final t = _transport;
    if (t == null) throw LanServiceError('未连接');
    _gameScope = 'game-${room.roomId}';
    await t.joinScope(_gameScope!);
    _watchGameScope();

    final log = t.getScope(_gameScope!);
    log?.merge({
      'phase': 'playing',
      'host': {'id': t.myNodeId, 'alias': _alias},
      'gameState': QuoridorEngine.initialize().toJson(),
    }, localNodeId: t.myNodeId);
    t.broadcastScope(_gameScope!);

    _roomEventsCtrl.add(HostRoomAnnounced(
      room: room,
      hostDeviceId: t.myNodeId,
      hostAlias: _alias ?? '',
    ));
    return room.roomId;
  }

  /// 加入房间 scope
  void joinGameScope(String roomId) {
    final t = _transport;
    if (t == null) return;
    _gameScope = 'game-$roomId';
    t.joinScope(_gameScope!);
    _watchGameScope();
  }

  void _watchGameScope() {
    final scope = _gameScope;
    final t = _transport;
    if (scope == null || t == null) return;
    _gameScopeSub?.cancel();
    _gameScopeSub = t.watchScope(scope).listen(_onGameScopeChanged);
  }

  void _onGameScopeChanged(fw.DataLog log) {
    final t = _transport;
    if (t == null || log.fromNodeId == t.myNodeId) return;

    // gameState 变化 → 更新本地 notifier
    final gsRaw = log.state['gameState'] as Map<String, dynamic>?;
    if (gsRaw != null) {
      final gs = QuoridorEngine.replayHistory(
        GameState.fromJson(gsRaw).history,
      );
      _onGameStateChanged?.call(gs);
    }

    // 关房
    if (log.state['closed'] == true) {
      _roomEventsCtrl.add(HostRoomClosed(roomId: _gameScope ?? ''));
    }
  }

  /// 注册游戏状态回调（game page initState 调用）
  void onGameStateChanged(void Function(GameState)? cb) {
    _onGameStateChanged = cb;
  }

  /// 推送游戏状态（本地 → scope）
  void syncGameState(GameState newState) {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    if (log == null) return;
    log.merge({'gameState': newState.toJson()}, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
  }

  /// 关闭房间（host 调用）
  Future<void> closeRoom(String roomId) async {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    log?.merge({'closed': true}, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
    _roomEventsCtrl.add(HostRoomClosed(roomId: roomId));
  }
}