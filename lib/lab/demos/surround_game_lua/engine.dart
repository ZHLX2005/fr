// lib/lab/demos/surround_game_lua/engine.dart
// 围追堵截 Lua 版 — 网络动作封装 + Snapshot 便捷读取 + 镜像工具

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';
import 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart';
import 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart';
import 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart';

export 'package:xiaodouzi_fr/core/net_p2p/scripts/lua_scripts.dart' show kSurroundGameScript;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;
export 'package:xiaodouzi_fr/core/surround_game/engine/game_engine.dart' show QuoridorEngine;
export 'package:xiaodouzi_fr/core/surround_game/models/game_state.dart'
    show GameState, MoveRecord;
export 'package:xiaodouzi_fr/core/surround_game/surround_game_constants.dart'
    show WallOrientation, GameStatus;

/// 围追堵截网络动作的语义封装。
class SgRoom {
  SgRoom(this.handle);
  final RoomHandle handle;

  bool get isHost => handle.transport.deviceId.startsWith('sg-');
  String get deviceId => handle.transport.deviceId;

  Future<void> ack()    => handle.applyAction(type: 'ACK', params: const {});
  Future<void> deal()   => handle.applyAction(type: 'DEAL', params: const {});
  Future<void> reset()  => handle.applyAction(type: 'RESET', params: const {});
  Future<void> move(MoveRecord record) =>
      handle.applyAction(type: 'MOVE', params: {'move': record.toJson()});

  /// 从 snapshot history 重建 GameState
  static GameState rebuildGameState(Snapshot? s) {
    if (s == null) return QuoridorEngine.initialize();
    final raw = s.context['history'];
    if (raw is! List || raw.isEmpty) return QuoridorEngine.initialize();
    final records = raw
        .map((e) => MoveRecord.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    return QuoridorEngine.replayHistory(records);
  }

  /// 从 snapshot 取 host_id
  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  /// 从 snapshot 取 players map
  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 当前是否是 host 的回合
  static bool isMyTurn(Snapshot? snap, GameState gs, String myId) {
    final hostId_ = hostId(snap);
    if (hostId_ == null) return false;
    if (gs.history.isEmpty) return myId == hostId_;
    final last = gs.history.last;
    return last.isTopPlayer ? myId != hostId_ : myId == hostId_;
  }
}

// ── 镜像坐标工具 ──

/// 棋盘镜像：服务端用规范坐标（host = top = y=0, guest = bottom = y=8）。
/// 每个客户端看到自己在下方的视觉。
class SgMirror {
  SgMirror({required bool isHostSide}) : _need = isHostSide;
  final bool _need;

  int mirrorY(int y) => _need ? 8 - y : y;

  /// 触摸坐标 → 规范 cellId
  int canonicalCellId(int tx, int ty) => mirrorY(ty) * 9 + tx;

  /// 规范 cellId → 显示 cellId
  int displayCellId(int canonical) {
    if (!_need) return canonical;
    final y = canonical ~/ 9, x = canonical % 9;
    return mirrorY(y) * 9 + x;
  }

  /// 规范 validMoves → 显示 validMoves
  Set<int> displayValidMoves(Set<int> src) {
    if (!_need) return src;
    return src.map((c) => (mirrorY(c ~/ 9)) * 9 + (c % 9)).toSet();
  }

  /// 规范 history → 显示 history（墙坐标 + 走棋坐标翻转）
  List<MoveRecord> displayHistory(List<MoveRecord> src) {
    if (!_need) return src;
    return src.map((m) {
      if (m.isWall) {
        return MoveRecord.wall(
          x: m.x, y: mirrorY(m.y), orientation: m.orientation!,
          isTopPlayer: m.isTopPlayer,
        );
      }
      return MoveRecord.move(cellId: mirrorY(m.y) * 9 + m.x, isTopPlayer: m.isTopPlayer);
    }).toList();
  }

  /// 规范 wall validator — 把镜像 y 转回规范
  bool validateWall(
    GameState gs, int wx, int wy, WallOrientation o,
  ) =>
      QuoridorEngine.isWallPlacementValid(
        gs.wallGrid, gs.adjacency, gs.topPlayerId, gs.bottomPlayerId,
        wx, mirrorY(wy), o,
      );
}
