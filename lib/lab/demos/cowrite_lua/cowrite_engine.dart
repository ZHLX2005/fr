// lib/lab/demos/cowrite_lua/cowrite_engine.dart
//
// Co-Write Notebook — 网络动作封装 + Snapshot 便捷读取。
//
// 设计要点：
//   - 服务端权威字段：broadcaster_id / broadcaster_line / broadcaster_version /
//     content / players / follow_settings
//   - 客户端用本地 TextEditingController 维护本地编辑内容；debounce 后发 EDIT
//   - 广播权语义：broadcaster_id == nil 表示无人占用；同一时刻最多一人持有

import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart';

export 'cowrite_lua_script.dart' show kCoWriteScript;
export 'cowrite_constants.dart' show kCoWriteRelayUrl;
export 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_v3_transport.dart'
    show Snapshot, RoomHandle, RelayV3Transport;

// ══════════════════════════════════════════════════════════════
// 网络动作的语义封装
// ══════════════════════════════════════════════════════════════

/// Co-Write 互联网协作的网络动作封装（语义层）。
class CoWriteRoom {
  CoWriteRoom(this.handle);
  final RoomHandle handle;

  String get deviceId => handle.transport.deviceId;

  // ── 网络动作 ──

  /// 全量覆盖笔记内容（任意一方 EDIT 都会替换全文）。
  Future<void> edit(String content) =>
      handle.applyAction(type: 'EDIT', params: {'content': content});

  /// 申请占用首行广播权。已被他人占 → 服务端静默拒绝（前端看快照即可）。
  Future<void> startBroadcast() =>
      handle.applyAction(type: 'START_BROADCAST', params: const {});

  /// 主动释放广播权（仅持有者生效）。
  Future<void> stopBroadcast() =>
      handle.applyAction(type: 'STOP_BROADCAST', params: const {});

  /// 持有者更新视图首行行号（1-indexed）。
  Future<void> broadcastLine(int line) =>
      handle.applyAction(type: 'BROADCAST_LINE', params: {'line': line});

  /// 设置自己的"自动对齐到对方首行"开关。
  Future<void> setFollow(bool follow) =>
      handle.applyAction(type: 'SET_FOLLOW', params: {'follow': follow});

  // ── Snapshot 便捷读取 ──

  static String? hostId(Snapshot? s) => s?.context['host_id']?.toString();

  static Map<String, String> players(Snapshot? s) {
    final raw = s?.context['players'];
    if (raw is! Map) return const {};
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }

  /// 笔记当前内容（服务端权威）。
  static String content(Snapshot? s) {
    final raw = s?.context['content'];
    return raw is String ? raw : '';
  }

  /// 首行广播权持有者的 device_id（null = 无人占用）。
  static String? broadcasterId(Snapshot? s) =>
      s?.context['broadcaster_id']?.toString();

  /// 持有者广播的视图首行行号（1-indexed）。
  static int? broadcasterLine(Snapshot? s) {
    final raw = s?.context['broadcaster_line'];
    if (raw is num) return raw.toInt();
    return null;
  }

  /// 广播版本号（单调递增；用于防止自己本地滚动事件回放覆盖新值）。
  static int? broadcasterVersion(Snapshot? s) {
    final raw = s?.context['broadcaster_version'];
    if (raw is num) return raw.toInt();
    return null;
  }

  /// 我的 follow 偏好（自动对齐开关）。
  static bool amFollowing(Snapshot? s, String myDeviceId) {
    final raw = s?.context['follow_settings'];
    if (raw is! Map) return false;
    return raw[myDeviceId] == true;
  }

  /// 我是不是当前广播持有者？
  static bool amBroadcaster(Snapshot? s, String myDeviceId) {
    return broadcasterId(s) == myDeviceId;
  }

  /// 当前广播持有者的 alias（显示给非持有者看的提示用）。
  static String? broadcasterAlias(Snapshot? s) {
    final id = broadcasterId(s);
    if (id == null) return null;
    return players(s)[id];
  }
}
