// test/core/chess/p2p/chess_identity_test.dart
//
// ChessIdentity（玩家稳定身份）单元测试：
//   · 已持久化登录 userId → 返回 `uid-<userId>`（真实登录 uid 优先）
//   · 未登录（无 userId）→ 回退设备级稳定 UUID（跨启动稳定）
//   · 会话内缓存：首次解析后固定（persistUserId 换账号才重新解析）
//   · persistUserId 后身份立即切换 + 跨"重启"（新建存储）稳定
//
// 这是 Bug 1（房间人满）/ Bug 2（一方身份丢失→错视角）的根因修复验证：
//   · 同一真实账号跨会话 identity 一致 → 重连识别为同一玩家（不误判满员）
//   · 身份稳定 → 房间页 host_id/guest_id 比对正确（不错视角）
//
// 存储说明（shared_preferences 2.5.5 双 API）：
//   · ChessIdentity 走 **async** API（SharedPreferencesAsync）→ 用
//     InMemorySharedPreferencesAsync 注入（SharedPreferencesAsyncPlatform.instance）
//   · RelayDeviceId 走 **legacy** API（SharedPreferences.getInstance）→ 用
//     SharedPreferences.setMockInitialValues 注入
//   两个存储独立，互不可见 —— 测试要分别种数据。

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_identity.dart';
import 'package:xiaodouzi_fr/core/net_engine/relay_v3/relay_device_id.dart';

/// 重置两个存储（async = ChessIdentity / legacy = RelayDeviceId）并清会话缓存。
///
/// [asyncSeed] 种 async 存储（chess_user_id）；[legacySeed] 种 legacy 存储
/// （relay_device_id）。返回 async 存储实例（供断言 / 复用）。
InMemorySharedPreferencesAsync resetStores({
  Map<String, Object> asyncSeed = const {},
  Map<String, Object> legacySeed = const {},
}) {
  SharedPreferences.setMockInitialValues(legacySeed); // legacy 存储
  RelayDeviceId.debugReset(); // 清 RelayDeviceId 会话缓存
  final store = InMemorySharedPreferencesAsync.withData(asyncSeed);
  SharedPreferencesAsyncPlatform.instance = store; // async 存储
  ChessIdentity.debugReset();
  return store;
}

void main() {
  setUp(() => resetStores());

  tearDown(() {
    ChessIdentity.debugReset();
    RelayDeviceId.debugReset();
  });

  test('未登录（无持久化 userId）→ 回退设备级稳定 UUID', () async {
    final id = await ChessIdentity.resolve();
    expect(id, isNotEmpty);
    expect(id, startsWith('dev-'), reason: '未登录应回退设备级稳定 id');
  });

  test('已持久化 userId → 返回 uid-<userId>（真实登录 uid 优先）', () async {
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '42'});
    final id = await ChessIdentity.resolve();
    expect(id, 'uid-42', reason: '已登录用真实 userId，而非设备 id');
    expect(id, isNot(startsWith('dev-')), reason: '不应回退设备 id');
  });

  test('同一真实账号 userId → 跨"重启" identity 稳定（重连身份不丢）', () async {
    // 会话 1：登录态（userId 已持久化）。
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '7'});
    final id1 = await ChessIdentity.resolve();
    expect(id1, 'uid-7');

    // 会话 2（模拟 app 重启）：同一账号 userId 持久化 → 同一 identity。
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '7'});
    final id2 = await ChessIdentity.resolve();
    expect(id2, id1, reason: '重启后 identity 必须一致，否则满员误判+错视角');

    // 会话 3：同一账号换设备（userId 相同）→ 仍是同一 identity。
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '7'});
    final id3 = await ChessIdentity.resolve();
    expect(id3, id1, reason: '同一账号跨设备同一身份');
  });

  test('不同账号 userId → 不同 identity（互不混淆）', () async {
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '1'});
    final idA = await ChessIdentity.resolve();
    expect(idA, 'uid-1');

    resetStores(asyncSeed: {ChessIdentity.userIdKey: '2'});
    final idB = await ChessIdentity.resolve();
    expect(idB, 'uid-2');
    expect(idA, isNot(idB));
  });

  test('会话内缓存：首次解析后固定（persistUserId 换账号才重新解析）', () async {
    resetStores(asyncSeed: {ChessIdentity.userIdKey: '11'});
    final id1 = await ChessIdentity.resolve();
    expect(id1, 'uid-11');

    // 对局中 token 刷新不影响身份（会话内固定）。
    final id2 = await ChessIdentity.resolve();
    expect(id2, id1, reason: '会话内身份固定，避免对局中身份漂移');

    // persistUserId 换账号（如退出登录后重新登录）→ 立即切新身份。
    await ChessIdentity.persistUserId(22);
    final id3 = await ChessIdentity.resolve();
    expect(id3, 'uid-22', reason: 'persistUserId 后身份应切换到新账号');
  });

  test('未登录 → 设备 UUID 跨"重启"稳定（持久化，不换 session 变新玩家）', () async {
    // 首次启动：legacy 存储已有设备 id（首次生成已持久化）。
    resetStores(legacySeed: {'relay_device_id': 'dev-seeded'});
    final id1 = await ChessIdentity.resolve();
    expect(id1, 'dev-seeded');

    // "重启"：同一持久化数据（设备 id 仍在）→ 同一身份。
    resetStores(legacySeed: {'relay_device_id': 'dev-seeded'});
    final id2 = await ChessIdentity.resolve();
    expect(id2, id1, reason: '未登录也应稳定：同一设备重启后不能变新玩家');
  });

  test('persistUserId 写入后可被 resolve 读取（登录→进房链路）', () async {
    await ChessIdentity.persistUserId(99);
    ChessIdentity.debugReset(); // 模拟新会话（app 重启）
    final id = await ChessIdentity.resolve();
    expect(id, 'uid-99', reason: '登录持久化的 userId 重启后仍生效');
  });

  test('resolve 幂等且极端环境（无任何持久化数据）不抛异常', () async {
    final r1 = await ChessIdentity.resolve();
    final r2 = await ChessIdentity.resolve();
    expect(r2, r1);
    expect(r1, isNotEmpty);
  });
}
