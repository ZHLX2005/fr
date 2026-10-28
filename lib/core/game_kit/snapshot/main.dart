// 联机快照 context 通用访问器 —— 服务端协议契约层（2026-10-28 自 7 个 lua demo 抽离）。
//
// 背景：每个 lua 联机游戏的 Room 类都各自抄了一份**逐字相同**的 snapshot
// context 解析器（players / readyMap / actionPermissions / hostId / winner）。
// 这些函数读的是**服务端 Lua 脚本写入的同一批 context 键**，属于协议契约而非
// 游戏私有逻辑 —— 抄一份改一处就会漏（服务端加字段 / 改键名时必然漂移）。
// 抽到这里后：协议键名只有一处真相，各游戏 Room 类只保留自己的私有访问器
// （棋步重建、专属计数等），公共部分改为委托。
//
// 依赖方向：game_kit → net_engine（Snapshot 类型），纯逻辑，不含 UI。

import '../../net_engine/relay_v3/relay_v3_transport.dart';

/// 服务端 snapshot context 的公共读取入口。
class GameSnapshot {
  GameSnapshot._();

  /// 房主设备 id（context['host_id']）。
  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  /// 玩家表：device_id → 玩家标识（context['players']）。
  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 准备状态：device_id → 是否已 ACK（context['ready']）。
  static Map<String, bool> readyMap(Snapshot? s) {
    final raw = s?.context['ready'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v == true));
  }

  /// 动作权限表：action → 规则（any / host / current_player …）。
  /// context['action_permissions']，★服务端约束的单点真相。
  static Map<String, String> actionPermissions(Snapshot? s) {
    final raw = s?.context['action_permissions'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 胜者标识（context['winner']）。
  static String? winner(Snapshot? s) => s?.context['winner']?.toString();

  /// 能否执行某动作 —— 按服务端下发的 [actionPermissions] 规则判定。
  ///
  /// 规则语义（服务端 Lua 脚本写入，与各游戏无关）：
  /// - 缺省 / `any` → 任何人都能做
  /// - `host` → 房主（各游戏里房主即先手方，故用 isBlack 传）
  /// - `current_player` → 当前行动方
  static bool canPerform(
    String action,
    Snapshot? snap, {
    required bool isBlack,
    required bool isMyTurn,
  }) {
    final rule = actionPermissions(snap)[action];
    if (rule == null || rule == 'any') return true;
    if (rule == 'host') return isBlack;
    if (rule == 'current_player') return isMyTurn;
    return false;
  }
}
