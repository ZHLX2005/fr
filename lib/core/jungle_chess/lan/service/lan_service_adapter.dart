// lib/core/jungle_chess/lan/service/lan_service_adapter.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../models/game_state.dart';
import '../protocol/lan_messages.dart';
import '../game_room.dart';
// Note: localnet 框架引用，实际实现时需根据 localnet API 调整

/// LAN 服务适配器（桥接 Game 层和 localnet 框架）
class JungleLanServiceAdapter {
  JungleLanServiceAdapter._();
  static final instance = JungleLanServiceAdapter._();

  bool _started = false;

  Future<void> start({required String myAlias}) async {
    // TODO: 启动 localnet 框架
    // await fw.LanFramework.instance.start(...);
    _started = true;
  }

  Future<void> stop() async {
    _started = false;
  }

  bool get isStarted => _started;

  // 房间宣布/停止
  Stream<GameRoom> watchRooms() {
    // TODO: watch 房间公告
    return const Stream.empty();
  }

  Future<void> announceRoom(GameRoom room) async {
    // TODO: UDP 多播 roomAnnounce
  }

  Future<void> stopRoom() async {
    // TODO: UDP 多播 roomClosed
  }

  // 加入/结果
  Future<void> sendJoinRequest(String hostDeviceId, String alias) async {
    // TODO: UDP send join request
  }

  Future<void> sendJoinResult(String clientDeviceId, bool accepted) async {
    // TODO: UDP send join result
  }

  // 协议事件流
  Stream<LanRoomEvent> watchRoomEvents() {
    // TODO: 监听协议消息并解析
    return const Stream.empty();
  }

  // 游戏 Session
  void createGameSession({
    required String peerId,
    required ValueNotifier<GameState> state,
    required String channelName,
  }) {
    // TODO: 创建 Session 双向同步
    // final serializer = GameStateSerializer();
    // final session = LanFramework.instance.createSession(...)
  }

  // 发送游戏开始广播
  Future<void> sendGameStart(Map<String, dynamic> initialState) async {
    // TODO: 通知对端游戏开始
  }

  // 发送断线通知
  Future<void> sendDisconnect(String message) async {
    // TODO: 通知对端
  }
}
