import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'surround_game_constants.dart';
import 'models/game_room.dart';
import 'models/player_input.dart';
import 'models/game_state.dart';

// 以下为全局单例引用
// import 'package:xiaodouzi_fr/core/localnet/localnet.dart';

/// 路由注册回调类型 — 对应 DiscoveryService.registerRoute
typedef RouteRegistrar = void Function(
  String path,
  Future<void> Function(HttpRequest) handler,
);

/// 围追堵截游戏服务 — 全局单例
///
/// 职责：
/// 1. 房间管理（创建/加入/离开）
/// 2. 向 LocalNet DiscoveryService 注册 HTTP 路由
/// 3. 游戏状态同步
///
/// 生命周期跟随 App，需要时通过 SurroundGameService() 获取实例。
class SurroundGameService {
  // ==================== 单例工厂 ====================

  static final SurroundGameService _instance = SurroundGameService._internal();
  factory SurroundGameService() => _instance;
  SurroundGameService._internal();

  // ==================== 状态 ====================

  /// 当前房间
  GameRoom? _currentRoom;
  GameRoom? get currentRoom => _currentRoom;

  /// 当前游戏状态
  GameState? _currentGameState;
  GameState? get currentGameState => _currentGameState;

  /// 是否为房间主机
  bool get isHost => _currentRoom?.hostId == _myDeviceId;

  /// 本机设备 ID（由外部注入，默认 UUID）
  String _myDeviceId = Uuid().v4();
  String get myDeviceId => _myDeviceId;

  /// 本机名称
  String _myName = 'Player';
  String get myName => _myName;

  /// 本机 IP（由 LocalNetService 探测后通过 init 注入）
  String? _myIp;
  String? get myIp => _myIp;

  /// 房间流
  final _roomsController = StreamController<List<GameRoom>>.broadcast();
  Stream<List<GameRoom>> get roomsStream => _roomsController.stream;
  List<GameRoom> get rooms => _roomsList;
  final List<GameRoom> _roomsList = [];

  /// 游戏状态流
  final _gameStateController = StreamController<GameState>.broadcast();
  Stream<GameState> get gameStateStream => _gameStateController.stream;

  /// 主机收到的输入流
  final _inputController = StreamController<PlayerInput>.broadcast();
  Stream<PlayerInput> get inputStream => _inputController.stream;

  /// 是否已初始化
  bool _initialized = false;

  /// 发现服务的引用（运行态由 init 注入）
  RouteRegistrar? _registerRoute;

  // ==================== 初始化 ====================

  /// 初始化游戏服务
  ///
  /// [registerRoute] LocalNet DiscoveryService.registerRoute 方法
  /// [deviceId] 本机设备 ID
  /// [deviceName] 本机显示名称
  /// [myIp] 本机 IP（由 LocalNet 提供）
  void init({
    required RouteRegistrar registerRoute,
    String? deviceId,
    String? deviceName,
    String? myIp,
  }) {
    if (_initialized) return;

    _registerRoute = registerRoute;
    _myDeviceId = deviceId ?? _myDeviceId;
    _myName = deviceName ?? _myName;
    _myIp = myIp;

    _registerGameRoutes();

    _initialized = true;
    debugPrint('[SurroundGame] 服务已初始化');
  }

  /// 注册游戏 HTTP 路由
  void _registerGameRoutes() {
    _registerRoute?.call(SurroundGameConstants.kPathGameInfo, _handleGameInfo);
    _registerRoute?.call(SurroundGameConstants.kPathGameJoin, _handleGameJoin);
    _registerRoute?.call(
      SurroundGameConstants.kPathGameLeave,
      _handleGameLeave,
    );
    _registerRoute?.call(SurroundGameConstants.kPathGameSync, _handleGameSync);
    _registerRoute?.call(
      SurroundGameConstants.kPathGameInput,
      _handleGameInput,
    );
  }

  // ==================== 房间管理 ====================

  /// 创建房间
  GameRoom createRoom({String? roomName, String? hostIp}) {
    final room = GameRoom(
      roomId: roomName ?? '${_myName}的房间',
      hostId: _myDeviceId,
      hostName: _myName,
      hostIp: hostIp ?? '',
      createdAt: DateTime.now(),
    );

    // 移除同一个主机的旧房间（避免重复堆积）
    _roomsList.removeWhere((r) => r.hostId == _myDeviceId);
    _currentRoom = room;
    _roomsList.add(room);
    _roomsController.add(List.from(_roomsList));
    debugPrint('[SurroundGame] 创建房间: ${room.roomId}');
    return room;
  }

  /// 添加发现的外部房间（由 LocalNet 发现回调调用）
  void addDiscoveredRoom(GameRoom room) {
    final exists = _roomsList.any((r) => r.roomId == room.roomId);
    if (!exists && room.hostId != _myDeviceId) {
      _roomsList.add(room);
      _roomsController.add(List.from(_roomsList));
    }
  }

  /// 加入房间
  bool joinRoom(GameRoom room) {
    if (room.isFull) return false;

    _currentRoom = room;
    debugPrint('[SurroundGame] 加入房间: ${room.roomId}');
    return true;
  }

  /// 离开房间
  void leaveRoom() {
    if (_currentRoom != null) {
      _roomsList.removeWhere((r) =>
          r.roomId == _currentRoom!.roomId ||
          r.hostId == _myDeviceId);
      _roomsController.add(List.from(_roomsList));
    }
    _currentRoom = null;
    _currentGameState = null;
    debugPrint('[SurroundGame] 离开房间');
  }

  // ==================== 游戏控制 ====================



  // ==================== HTTP 路由处理 ====================

  /// 处理游戏信息查询
  Future<void> _handleGameInfo(HttpRequest request) async {
    final info = {
      'roomId': _currentRoom?.roomId ?? '',
      'roomState': _currentRoom?.state.name ?? 'waiting',
      'playerCount': _currentRoom?.playerCount ?? 1,
      'maxPlayers': SurroundGameConstants.kMaxPlayers,
      'gameType': SurroundGameConstants.kGameType,
    };
    request.response.headers.set('Content-Type', 'application/json');
    request.response.write(jsonEncode(info));
    await request.response.close();
  }

  /// 处理加入房间请求
  Future<void> _handleGameJoin(HttpRequest request) async {
    try {
      final bodyBytes = await request.fold<List<int>>(
        [],
        (prev, element) => prev..addAll(element),
      );
      final body = utf8.decode(bodyBytes);
      final params = Uri.splitQueryString(body);
      final playerId = params['deviceId'] ?? '';
      final playerName = params['name'] ?? 'Unknown';

      if (_currentRoom == null || _currentRoom!.isFull) {
        request.response.statusCode = 400;
        await request.response.close();
        return;
      }

      _currentRoom = _currentRoom!.copyWith(
        clientId: playerId.isNotEmpty ? playerId : null,
        clientName: playerName,
      );

      debugPrint('[SurroundGame] 玩家加入: $playerName ($playerId)');
      request.response.write('OK');
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 400;
      await request.response.close();
    }
  }

  /// 处理离开房间请求
  Future<void> _handleGameLeave(HttpRequest request) async {
    if (_currentRoom != null) {
      _currentRoom = _currentRoom!.copyWith(clientId: null, clientName: null);
    }
    request.response.write('OK');
    await request.response.close();
  }

  /// 处理游戏状态同步
  Future<void> _handleGameSync(HttpRequest request) async {
    try {
      final bodyBytes = await request.fold<List<int>>(
        [],
        (prev, element) => prev..addAll(element),
      );
      final body = utf8.decode(bodyBytes);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final state = GameState.fromJson(json);

      _currentGameState = state;
      _gameStateController.add(state);

      request.response.write('OK');
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 400;
      await request.response.close();
    }
  }

  /// 处理玩家输入（Host 接收 client 的走棋方向）
  Future<void> _handleGameInput(HttpRequest request) async {
    try {
      final bodyBytes = await request.fold<List<int>>(
        [],
        (prev, element) => prev..addAll(element),
      );
      final body = utf8.decode(bodyBytes);
      final json = jsonDecode(body) as Map<String, dynamic>;
      final input = PlayerInput.fromJson(json);

      _inputController.add(input);

      request.response.write('OK');
      await request.response.close();
    } catch (e) {
      request.response.statusCode = 400;
      await request.response.close();
    }
  }

  // ==================== 网络发送辅助 ====================

  /// 发送游戏输入到 Host
  Future<bool> sendInputToHost(
    String hostIp,
    int hostPort,
    Direction direction,
    int step,
  ) async {
    final input = PlayerInput(
      playerId: _myDeviceId,
      direction: direction,
      stepNumber: step,
    );

    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse('http://$hostIp:$hostPort${SurroundGameConstants.kPathGameInput}'),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(input.toJson()));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SurroundGame] 发送输入失败: $e');
      return false;
    }
  }

  /// 发送游戏状态给客机
  Future<bool> sendStateToClient(
    String clientIp,
    int clientPort,
    GameState state,
  ) async {
    try {
      final client = HttpClient();
      final request = await client.postUrl(
        Uri.parse(
          'http://$clientIp:$clientPort${SurroundGameConstants.kPathGameSync}',
        ),
      );
      request.headers.set('Content-Type', 'application/json');
      request.write(jsonEncode(state.toJson()));
      final response = await request.close();
      await response.drain<void>();
      client.close();
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('[SurroundGame] 发送状态失败: $e');
      return false;
    }
  }

  // ==================== 清理 ====================

  void dispose() {
    _roomsController.close();
    _gameStateController.close();
    _inputController.close();
    _currentRoom = null;
    _currentGameState = null;
    _initialized = false;
  }

  // ==================== UDP 广播支持 ====================

  /// 当前是否有开放房间（影响广播是否携带游戏字段）
  bool get hasOpenRoom => _currentRoom != null;

  /// 构建广播扩展字段（追加到 UDP 心跳）
  ///
  /// 返回 `['g:surround', 'r:房间ID', 'p:1/2']` 或 null
  List<String>? buildBroadcastExtras() {
    final room = _currentRoom;
    if (room == null) return null;
    return [
      '${SurroundGameConstants.kBroadcastGame}:${SurroundGameConstants.kGameType}',
      '${SurroundGameConstants.kBroadcastRoom}:${room.roomId}',
      '${SurroundGameConstants.kBroadcastPlayers}:${room.playerCount}/${room.maxPlayers}',
    ];
  }

  /// 处理从其他设备接收的 UDP 广播（解析扩展字段 → 添加房间）
  ///
  /// 由 LocalNet DiscoveryService 收到 UDP 数据报时调用
  void onUdpBroadcastReceived({
    required String deviceId,
    required String senderIp,
    required int senderPort,
    required Map<String, String> extras,
  }) {
    final gameType = extras[SurroundGameConstants.kBroadcastGame];
    if (gameType != SurroundGameConstants.kGameType) return;

    final roomId = extras[SurroundGameConstants.kBroadcastRoom] ?? '';
    final players = extras[SurroundGameConstants.kBroadcastPlayers] ?? '0/2';
    final playerCount = int.tryParse(players.split('/').first) ?? 0;

    final room = GameRoom(
      roomId: roomId.isEmpty ? '${extras["hostName"] ?? "Remote"}的房间' : roomId,
      hostId: deviceId,
      hostName: extras['hostName'] ?? 'Remote Player',
      hostIp: senderIp,
      hostPort: senderPort,
      clientId: playerCount >= 2 ? '_full_' : null,
      clientName: playerCount >= 2 ? '已满' : null,
      createdAt: DateTime.now(),
    );

    addDiscoveredRoom(room);
  }
}

/// 全局游戏服务实例
final surroundGameService = SurroundGameService();
