// test/core/chess/p2p/chess_identity_test.dart
//
// ChessIdentity（玩家稳定身份）单元测试：
//   · 已登录（token 存在）→ 返回 `uid-<token>`（登录 uid 优先）
//   · 未登录（无 token）→ 回退 RelayDeviceId.get()（设备级 UUID）
//   · 会话内缓存：首次解析后固定（换 token / 清 prefs 不再变）
//   · debugReset 清缓存 + 可注入假 token 存储
//
// 这是 Bug 1（房间人满）/ Bug 2（一方身份丢失→错视角）的根因修复验证：
//   · 同一账号跨会话 identity 一致 → 重连识别为同一玩家（不误判满员）
//   · 身份稳定 → 房间页 host_id/guest_id 比对正确（不错视角）

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xiaodouzi_fr/api/token/token_storage.dart';
import 'package:xiaodouzi_fr/core/chess/p2p/chess_identity.dart';

/// 假 token 存储：内存 map，模拟 SharedPrefsTokenStorage 的行为。
class FakeTokenStorage implements TokenStorage {
  String? access;
  String? refresh;
  DateTime? expires;

  @override
  Future<String?> get accessToken async => access;

  @override
  Future<String?> get refreshToken async => refresh;

  @override
  Future<DateTime?> get expiresAt async => expires;

  @override
  Future<void> save({
    required String accessToken,
    String? refreshToken,
    DateTime? expiresAt,
  }) async {
    access = accessToken;
    if (refreshToken != null) refresh = refreshToken;
    if (expiresAt != null) expires = expiresAt;
  }

  @override
  Future<void> clear() async {
    access = null;
    refresh = null;
    expires = null;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ChessIdentity.debugReset();
  });

  tearDown(() => ChessIdentity.debugReset());

  test('未登录（无 token）→ 回退设备级 UUID（RelayDeviceId.get）', () async {
    ChessIdentity.debugReset(storage: FakeTokenStorage()); // 无 token
    final id = await ChessIdentity.resolve();
    expect(id, isNotEmpty);
    expect(id, startsWith('dev-'), reason: '未登录应回退设备级稳定 id');
  });

  test('已登录（token 存在）→ 返回 uid-<token>（登录 uid 优先）', () async {
    final storage = FakeTokenStorage()..access = 'tok-abc123';
    ChessIdentity.debugReset(storage: storage);
    final id = await ChessIdentity.resolve();
    expect(id, 'uid-tok-abc123', reason: '已登录用登录 uid，而非设备 id');
    expect(id, isNot(startsWith('dev-')), reason: '不应回退设备 id');
  });

  test('同一账号 token → 跨会话 identity 稳定（重连身份不丢）', () async {
    // 会话 1：登录态。
    final s1 = FakeTokenStorage()..access = 'tok-stable';
    ChessIdentity.debugReset(storage: s1);
    final id1 = await ChessIdentity.resolve();
    expect(id1, 'uid-tok-stable');

    // 会话 2（模拟 app 重启）：同一账号 token 持久化 → 同一 identity。
    ChessIdentity.debugReset(storage: s1);
    final id2 = await ChessIdentity.resolve();
    expect(id2, id1, reason: '重连/重启后 identity 必须一致，否则满员误判+错视角');

    // 会话 3：同一账号不同设备（token 仍相同）→ 仍是同一 identity。
    final s2 = FakeTokenStorage()..access = 'tok-stable';
    ChessIdentity.debugReset(storage: s2);
    final id3 = await ChessIdentity.resolve();
    expect(id3, id1, reason: '同一账号跨设备同一身份');
  });

  test('不同账号 token → 不同 identity（互不混淆）', () async {
    final a = FakeTokenStorage()..access = 'tok-user-a';
    final b = FakeTokenStorage()..access = 'tok-user-b';
    ChessIdentity.debugReset(storage: a);
    final idA = await ChessIdentity.resolve();
    ChessIdentity.debugReset(storage: b);
    final idB = await ChessIdentity.resolve();
    expect(idA, isNot(idB));
  });

  test('会话内缓存：首次解析后固定（后续不再受 token 变化影响）', () async {
    final storage = FakeTokenStorage()..access = 'tok-first';
    ChessIdentity.debugReset(storage: storage);
    final id1 = await ChessIdentity.resolve();

    // token 变了（如重新登录），但会话内 identity 不变 —— 避免已入房身份漂移。
    storage.access = 'tok-second';
    final id2 = await ChessIdentity.resolve();
    expect(id2, id1, reason: '会话内身份固定，避免对局中身份漂移');

    // debugReset 后才重新解析。
    ChessIdentity.debugReset(storage: storage);
    final id3 = await ChessIdentity.resolve();
    expect(id3, 'uid-tok-second');
  });
}
