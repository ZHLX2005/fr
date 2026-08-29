// lib/core/chess/p2p/chess_identity.dart
//
// 国际象棋玩家身份的稳定标识（identity）—— 替代"会话级 deviceId"。
//
// 背景（Bug 根因）：
//   国际象棋用 transport.deviceId 作为玩家身份键（host_id / guest_id /
//   players / rejected_join 都以它为 key）。而 RelayDeviceId 是**会话级**的
//   （每次 App 冷启动重新生成）——于是：
//   · 断线重连/重新进房 → 新 deviceId ≠ 原 host_id/guest_id → 一方身份丢失
//     → _resolveMyColor 判错 → 显示对方视角棋盘（Bug 2）
//   · 同一真实用户换 session 再进同一房间 → 被当作"新玩家" → 满员判断错乱
//     （Bug 1）
//
// 修复（Option A：只改 chess 侧，不动 RelayV3Transport / 服务端契约）：
//   让 chess 传给 transport 的 deviceId = **稳定的登录 uid 优先**，
//   未登录回退设备级 UUID：
//     chessIdentity() = 已登录 ? 登录 uid : RelayDeviceId.get()
//   其它 7 个 Lua 游戏仍用会话级 RelayDeviceId，不受影响。
//
// 登录 uid 的来源：当前 App 只有 token（api_access_token）被持久化，userId
// 没有被持久化。所以这里"已登录"判定 = 存在有效 token（SharedPrefsTokenStorage），
// 登录 uid 直接取 token 字符串本身作为稳定身份（同一账号 token 稳定不变，
// 换设备 token 仍相同 → 跨设备同一身份，正是社交对弈想要的）。
//
// 设计：会话内缓存（identity 一旦解析就固定），避免每次建房都走 IO。

import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../../api/token/token_storage.dart';
import '../../net_engine/relay_v3/relay_device_id.dart';

/// 国际象棋玩家稳定身份（登录 uid 优先，未登录回退设备级 UUID）。
class ChessIdentity {
  /// 会话内缓存：一次解析后固定，避免每次建房都走 SharedPreferences IO。
  static String? _cached;

  /// token 存储：与 AuthInterceptor / UserAuthService 共用同一 key，保证"已登录"
  /// 判定一致。可通过 [debugOverride] 注入假存储（测试用）。
  @visibleForTesting
  static TokenStorage? debugStorage;

  static const _loginPrefix = 'uid-';

  /// 返回国际象棋玩家稳定身份字符串。
  ///
  /// 规则：
  ///   1. 已登录（存在 accessToken）→ `uid-<token>`（登录 uid 优先）；
  ///   2. 未登录 → `RelayDeviceId.get()`（设备级稳定 UUID，会话内不变）。
  ///
  /// 幂等 + 会话内缓存。拿不到任何稳定源时回退设备 UUID（兜底）。
  static Future<String> resolve() async {
    final cached = _cached;
    if (cached != null) return cached;

    String id;
    final storage = debugStorage ?? SharedPrefsTokenStorage();
    final token = await storage.accessToken;
    if (token != null && token.isNotEmpty) {
      // 已登录：用登录 uid（token）作为稳定身份 —— 同一账号跨设备/跨会话一致。
      id = '$_loginPrefix$token';
    } else {
      id = await RelayDeviceId.get();
    }
    _cached = id;
    return id;
  }

  /// 测试用：清空会话缓存 + 可选注入假 token 存储。
  @visibleForTesting
  static void debugReset({TokenStorage? storage}) {
    _cached = null;
    debugStorage = storage;
  }
}
