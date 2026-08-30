// lib/core/chess/p2p/chess_identity.dart
//
// 国际象棋玩家身份的稳定标识（identity）—— 替代"会话级 deviceId / token"。
//
// 背景（Bug 根因）：
//   国际象棋用 transport.deviceId 作为玩家身份键（host_id / guest_id /
//   players / rejected_join 都以它为 key）。而 RelayDeviceId 是**设备级**的
//   （首次生成后持久化，跨启动稳定）；旧实现"已登录"用 token 字符串
//   （uid-<token>）当身份 —— token 会随重登录 / token 刷新变化，于是：
//   · 同一真实用户换 token 再进同一房间 → 被当作"新玩家" → 满员误判
//     （Bug 1 房间人满）
//   · 重新进房 → 新 identity ≠ 原 host_id/guest_id → 一方身份丢失
//     → _resolveMyColor 判错 → 显示对方视角棋盘（Bug 2）
//
// 修复（Option A：只改 chess 侧，不动 RelayV3Transport / 服务端契约）：
//   让 chess 传给 transport 的 deviceId = **稳定的登录 uid（真实 userId）优先**，
//   未登录回退设备级 UUID：
//     chessIdentity() = 已持久化 userId ? uid-<userId> : 设备级 UUID
//   其它 7 个 Lua 游戏仍用会话级 RelayDeviceId，不受影响。
//
// 登录 uid 的来源：注册/登录成功后（register_flow_controller / user_auth_service）
// 把后端返回的真实 `userId` 持久化到 SharedPreferences（key chess_user_id），
// 这里直接读它 —— userId 是账号的真实主键，跨会话 / 跨 token / 跨设备同一账号
// 都稳定不变，正是社交对弈想要的。token 只是凭证，永不当作身份。
//
// 设计：
//   · 会话内缓存（identity 一旦解析就固定），避免每次建房都走 IO；
//     登录/注册成功会调 [persistUserId] 主动清缓存重新解析。
//   · [persistUserId] 由登录/注册流程调用（含测试注入假存储）。

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../net_engine/relay_v3/relay_device_id.dart';

/// 国际象棋玩家稳定身份（真实登录 userId 优先，未登录回退设备级 UUID）。
class ChessIdentity {
  /// 会话内缓存：一次解析后固定，避免每次建房都走 SharedPreferences IO。
  static String? _cached;

  /// 测试用 SharedPreferences 假实现注入点（空实现 → 走真实 SharedPreferences）。
  @visibleForTesting
  static SharedPreferencesAsync? debugPrefsAsync;

  static const _loginPrefix = 'uid-';

  /// SharedPreferences key（真实登录 userId，持久化后即玩家稳定身份）。
  static const String userIdKey = 'chess_user_id';

  /// 返回国际象棋玩家稳定身份字符串。
  ///
  /// 规则：
  ///   1. 已持久化登录 userId → `uid-<userId>`（真实登录 uid 优先）；
  ///   2. 未登录 → `RelayDeviceId.get()`（设备级稳定 UUID，跨启动稳定）。
  ///
  /// 幂等 + 会话内缓存。拿不到任何稳定源时回退设备 UUID（兜底），绝不抛异常。
  static Future<String> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;

    String id;
    try {
      final userId = await _readUserId();
      if (userId != null && userId.isNotEmpty) {
        // 真实登录 uid：跨会话 / 跨 token / 跨设备同一账号稳定不变。
        id = '$_loginPrefix$userId';
      } else {
        id = await RelayDeviceId.get();
      }
    } catch (_) {
      // 极端回退（存储异常）：仍给一个稳定设备 id，保证身份不空、不抛。
      id = await RelayDeviceId.get();
    }
    _cached = id;
    return id;
  }

  /// 持久化真实登录 userId（注册/登录成功后调用）。
  ///
  /// 写入后主动清会话缓存 —— 同一进程内先注册再建房也要立刻用新身份。
  /// 存储失败静默（best-effort）：下次 resolve 回退设备 UUID，不影响登录。
  static Future<void> persistUserId(int userId) async {
    try {
      await (debugPrefsAsync ?? SharedPreferencesAsync()).setString(
        userIdKey,
        '$userId',
      );
      _cached = null; // 身份源已变，放弃旧缓存。
    } catch (_) {
      // 静默：存储失败不阻断登录/注册流程。
    }
  }

  /// 读取持久化的登录 userId（null = 未登录 / 未持久化）。
  static Future<String?> _readUserId() async {
    final prefs = debugPrefsAsync ?? SharedPreferencesAsync();
    return prefs.getString(userIdKey);
  }

  /// 测试用：清空会话缓存 + 可选重置 SharedPreferences 假实现。
  @visibleForTesting
  static void debugReset({SharedPreferencesAsync? prefsAsync}) {
    _cached = null;
    debugPrefsAsync = prefsAsync;
  }
}
