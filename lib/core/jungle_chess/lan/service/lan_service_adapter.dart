// lib/core/jungle_chess/lan/service/lan_service_adapter.dart
//
// 新引擎模式：Transport 由业务层直接创建（LanTransport.create()），
// adapter.attach(transport) 绑定，DataLog 同步游戏状态。
// 只有 LAN 模式。

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:xiaodouzi_fr/core/localnet/localnet.dart' as fw;

import '../game_room.dart';
import '../../models/game_state.dart';
import '../../engine/jungle_engine.dart';
import '../protocol/lan_messages.dart';
import '../persistence/player_profile_service.dart';

class LanServiceError {
  LanServiceError(this.message, {this.cause});
  final String message;
  final Object? cause;
  @override
  String toString() => 'LanServiceError($message)';
}

abstract class LanServiceAdapter {
  static final LanServiceAdapter instance = _JungleLanServiceAdapterImpl();

  void attach(fw.Transport transport, {required String alias});
  void detach();
  bool get isRunning;
  String get myDeviceId;
  String get myAlias;

  Stream<List<String>> watchPeers();
  Stream<LanRoomEvent> watchRoomEvents();
  Stream<LanServiceError> watchErrors();

  Future<void> announceRoom(GameRoom room);
  Future<void> stopRoom(String roomId);
  void acceptJoin(String clientDeviceId);
  void joinGameScope(String roomId);
  void syncGameState(GameState newState);
  void onGameStateChanged(void Function(GameState)? cb);
  String? get currentGameScope;
}

class _JungleLanServiceAdapterImpl implements LanServiceAdapter {
  fw.Transport? _transport;
  String? _alias;
  String? _gameScope;
  bool _isRunning = false;

  final Set<String> _peers = {};
  final StreamController<List<String>> _peersCtrl =
      StreamController<List<String>>.broadcast();
  final StreamController<LanRoomEvent> _roomEventsCtrl =
      StreamController<LanRoomEvent>.broadcast();
  final StreamController<LanServiceError> _errorsCtrl =
      StreamController<LanServiceError>.broadcast();
  StreamSubscription<fw.TransportEvent>? _eventSub;
  StreamSubscription<fw.DataLog>? _gameScopeSub;

  void Function(GameState)? _onGameStateChanged;

  // presence 追踪
  final Set<String> _presentNodes = {};
  void Function(String deviceId, String alias, String role)? onPeerPresent;

  @override
  bool get isRunning => _isRunning;
  @override
  String get myDeviceId => _transport?.myNodeId ?? '';
  @override
  String get myAlias => _alias ?? '';
  @override
  String? get currentGameScope => _gameScope;

  void _broadcastPresence(String role, String status) {
    final t = _transport;
    if (t == null) return;
    for (final scope in t.activeScopes) {
      t.sendEvent(scope, 'presence', {
        'deviceId': t.myNodeId,
        'alias': _alias ?? '',
        'role': role,
        'status': status,
      });
    }
  }

  @override
  void attach(fw.Transport transport, {required String alias}) {
    detach();
    _transport = transport;
    _alias = alias;
    _isRunning = true;

    _eventSub = transport.events.listen((ev) {
      if (ev.topic == 'peer-joined-scope') {
        final from = ev.data['from'] as String?;
        if (from != null && from != transport.myNodeId) {
          _peers.add(from);
          _peersCtrl.add(List.unmodifiable(_peers));
        }
      }
      // 握手 — host 收到 client 加入请求
      if (ev.topic == 'handshake-join') {
        final cid = ev.data['clientDeviceId'] as String?;
        final alias = ev.data['clientAlias'] as String? ?? '?';
        if (cid != null && cid != transport.myNodeId) {
          _roomEventsCtrl.add(ClientJoinRequested(
            clientDeviceId: cid,
            clientAlias: alias,
          ));
        }
      }
      // 握手 — client 收到 host 接受
      if (ev.topic == 'handshake-accepted') {
        _roomEventsCtrl.add(ClientJoinResult(accepted: true));
      }
      // presence — 对端状态上报
      if (ev.topic == 'presence') {
        final did = ev.data['deviceId'] as String?;
        if (did == null || did == transport.myNodeId) return;
        _presentNodes.add(did);
        onPeerPresent?.call(
          did,
          ev.data['alias'] as String? ?? '?',
          ev.data['role'] as String? ?? '?',
        );
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
    _presentNodes.clear();
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

  @override
  Future<void> announceRoom(GameRoom room) async {
    final t = _transport;
    if (t == null) return;
    _gameScope = 'game-${room.roomId}';
    await t.joinScope(_gameScope!);
    _watchGameScope();

    final log = t.getScope(_gameScope!);
    log?.merge({
      'phase': 'waiting',
      'host': {'id': t.myNodeId, 'alias': _alias},
    }, localNodeId: t.myNodeId);
    t.broadcastScope(_gameScope!);

    _roomEventsCtrl.add(HostRoomAnnounced(
      hostDeviceId: t.myNodeId,
      hostName: _alias ?? '',
      roomId: room.roomId,
    ));

    // presence：host 就绪
    _broadcastPresence('host', 'waiting');
  }

  @override
  void joinGameScope(String roomId) {
    final t = _transport;
    if (t == null) return;
    _gameScope = 'game-$roomId';
    t.joinScope(_gameScope!);
    _watchGameScope();

    final log = t.getScope(_gameScope!);
    log?.merge({
      'client': {'id': t.myNodeId, 'alias': _alias, 'joinRequested': true},
    }, localNodeId: t.myNodeId);
    t.broadcastScope(_gameScope!);

    // 握手：事件总线通知 host
    t.sendEvent(_gameScope!, 'handshake-join', {
      'clientDeviceId': t.myNodeId,
      'clientAlias': _alias ?? '',
      'roomId': roomId,
    });

    // presence
    _broadcastPresence('client', 'joining');
  }

  void _watchGameScope() {
    final scope = _gameScope;
    final t = _transport;
    if (scope == null || t == null) return;
    _gameScopeSub?.cancel();
    _gameScopeSub = t.watchScope(scope).listen(_onGameScopeChanged);
  }

  void _onGameScopeChanged(fw.DataLog log) {
    final fromId = log.fromNodeId;
    final t = _transport;
    if (t == null || fromId == t.myNodeId) return;

    final phase = log.state['phase'] as String? ?? '';
    final host = log.state['host'] as Map<String, dynamic>?;
    final client = log.state['client'] as Map<String, dynamic>?;

    if (client?['joinRequested'] == true && host != null) {
      final c = client!;
      _roomEventsCtrl.add(ClientJoinRequested(
        clientDeviceId: c['id'] as String,
        clientAlias: client['alias'] as String? ?? '?',
      ));
    }
    // accepted 写入 client 字段
    if (client?['accepted'] == true) {
      _roomEventsCtrl.add(ClientJoinResult(accepted: true));
    }
    if (phase == 'playing') {
      final gsRaw = log.state['gameState'] as Map<String, dynamic>?;
      if (gsRaw != null) {
        _onGameStateChanged?.call(GameState.fromJson(gsRaw));
      }
    }
    if (log.state['closed'] == true) {
      _roomEventsCtrl.add(HostRoomClosed());
    }
  }

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

  @override
  void onGameStateChanged(void Function(GameState)? cb) {
    _onGameStateChanged = cb;
  }

  @override
  void acceptJoin(String clientDeviceId) {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;

    // DataLog 路径
    final log = t.getScope(scope);
    if (log != null) {
      log.merge({
        'phase': 'playing',
        'client': {
          ...((log.state['client'] as Map?)?.cast<String, dynamic>() ?? {}),
          'accepted': true,
        },
        'gameState': JungleEngine.createInitialState().toJson(),
      }, localNodeId: t.myNodeId);
      t.broadcastScope(scope);
    }

    // 握手路径
    t.sendEvent(scope, 'handshake-accepted', {
      'roomId': scope.startsWith('game-') ? scope.substring(5) : scope,
      'clientDeviceId': clientDeviceId,
    });

    // presence
    _broadcastPresence('host', 'ready');
  }

  @override
  Future<void> stopRoom(String roomId) async {
    final t = _transport;
    final scope = _gameScope;
    if (t == null || scope == null) return;
    final log = t.getScope(scope);
    log?.merge({'closed': true}, localNodeId: t.myNodeId);
    t.broadcastScope(scope);
    _roomEventsCtrl.add(HostRoomClosed());
  }
}
