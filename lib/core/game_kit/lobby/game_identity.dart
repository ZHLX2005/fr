// lib/core/game_kit/lobby/game_identity.dart
//
// 玩家稳定身份（identity）—— 所有 relay v3 对弈房通用。
// 自 chess/p2p/chess_identity.dart 下沉（该实现本就零棋种依赖，与
// RelayConnectionStatusBadge / BoardChatOverlay 同一防腐逻辑）。
//
// 背景（原 Bug 根因）：
//   身份键（host_id / guest_id / players / rejected_join 都是它的 key）若用
//   「会话级 token / 现生成 id」，换 token / 换设备 / 重装即被服务端当成
//   「新玩家」→ 满员误判（房间人满）+ 房主身份丢失（视角判错）。
//
// 规则：
//   1. 已持久化登录 userId → `uid-<userId>`（真实登录 uid 优先：跨会话 /
//      跨 token / 跨设备同一账号稳定不变 —— 换手机 / 重装 / 重登都能拿回原座位）；
//   2. 未登录 → `RelayDeviceId.get()`（设备级持久 UUID，跨启动稳定，
//      全局唯一的本地身份，全部 Lua 游戏共用）。
//
// ⚠️ 语义提示：uid 优先意味着「同一账号的两台手机 = 同一个身份」——想用两台
// 手机自己跟自己下棋，需各登不同账号或退登（回退设备 UUID）。
//
// SharedPreferences key：'login_user_id'（新，跨游戏统一）；
// 兼容读取历史 'chess_user_id'（chess 期写入）→ 老用户身份不漂移；
// [persistUserId] 两键同写（历史读者仍可工作）。

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../../net_engine/relay_v3/relay_device_id.dart';

/// 玩家稳定身份（真实登录 userId 优先，未登录回退设备级 UUID）。
class GameIdentity {
  /// 会话内缓存：一次解析后固定，避免每次建房都走 SharedPreferences IO。
  static String? _cached;

  /// 测试用 SharedPreferences 假实现注入点（空实现 → 走真实 SharedPreferences）。
  @visibleForTesting
  static SharedPreferencesAsync? debugPrefsAsync;

  static const _loginPrefix = 'uid-';

  /// 登录 userId 的持久化 key（跨游戏统一）。
  static const String userIdKey = 'login_user_id';

  /// 历史 key：chess 期使用（`ChessIdentity.userIdKey`），只读兼容不新写。
  static const String legacyChessUserIdKey = 'chess_user_id';

  /// 返回玩家稳定身份字符串。
  ///
  /// 规则：
  ///   1. 已持久化登录 userId → `uid-<userId>`；
  ///   2. 未登录 → `RelayDeviceId.get()`（设备级稳定 UUID）。
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
      final prefs = debugPrefsAsync ?? SharedPreferencesAsync();
      // 新键为准；同时镜像历史键，保证还没迁移的读者身份不漂移。
      await prefs.setString(userIdKey, '$userId');
      await prefs.setString(legacyChessUserIdKey, '$userId');
      _cached = null; // 身份源已变，放弃旧缓存。
    } catch (_) {
      // 静默：存储失败不阻断登录/注册流程。
    }
  }

  /// 读取持久化的登录 userId（null = 未登录 / 未持久化）。
  /// 新键优先，回退历史 chess 键（只读兼容）。
  static Future<String?> _readUserId() async {
    final prefs = debugPrefsAsync ?? SharedPreferencesAsync();
    final v = await prefs.getString(userIdKey);
    if (v != null && v.isNotEmpty) return v;
    return prefs.getString(legacyChessUserIdKey);
  }

  /// 测试用：清空会话缓存 + 可选重置 SharedPreferences 假实现。
  @visibleForTesting
  static void debugReset({SharedPreferencesAsync? prefsAsync}) {
    _cached = null;
    debugPrefsAsync = prefsAsync;
  }
}
