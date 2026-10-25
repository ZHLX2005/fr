// GameCenterCatalogSync 行为测试：compare-then-write + 全路径静默。
//
// 匿名比对读用 MockClient（http/testing），鉴权写用 KvOps 替身
//（该接口本就为上游注入替身而设）。401 重铸在 ApiClient 拦截器层，
// 不在本类的职责内，这里不测。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:xiaodouzi_fr/api/api_response.dart';
import 'package:xiaodouzi_fr/api/goframe/kv/kv_endpoint.dart';
import 'package:xiaodouzi_fr/core/game_kit/game_center_catalog.dart';
import 'package:xiaodouzi_fr/core/game_kit/game_center_catalog_sync.dart';
import 'package:xiaodouzi_fr/core/game_kit/skin/public_kv_reader.dart';

const _fakeGames = [
  GameCenterCatalogEntry(
    slug: 'gomoku-lua',
    title: '五子棋（联机）',
    description: 'Gomoku 互联网双人对战',
    categories: ['multiplayer', 'board'],
    mode: '联机双人',
  ),
  GameCenterCatalogEntry(
    slug: 'snake',
    title: '贪吃蛇',
    description: '经典贪吃蛇游戏',
    categories: ['arcade'],
    mode: '单人',
  ),
];

class _SetCall {
  const _SetCall({
    required this.key,
    required this.value,
    required this.groupId,
    required this.tags,
    required this.visibility,
  });
  final String key;
  final String value;
  final int? groupId;
  final List<String>? tags;
  final String? visibility;
}

class _FakeKv implements KvOps {
  _FakeKv(this.handler);

  final ApiResponse<void> Function(_SetCall call) handler;
  final List<_SetCall> calls = [];

  @override
  Future<ApiResponse<KvItem?>> get(String key, {int? groupId}) =>
      Future.error(UnimplementedError());

  @override
  Future<ApiResponse<void>> set({
    required String key,
    required String value,
    int? ttl,
    int? groupId,
    List<String>? tags,
    String? visibility,
  }) async {
    final call = _SetCall(
      key: key,
      value: value,
      groupId: groupId,
      tags: tags,
      visibility: visibility,
    );
    calls.add(call);
    return handler(call);
  }

  @override
  Future<ApiResponse<void>> delete(String key, {int? groupId}) =>
      Future.error(UnimplementedError());

  @override
  Future<ApiResponse<KvListResult>> list({
    int limit = 50,
    int offset = 0,
    int? groupId,
  }) =>
      Future.error(UnimplementedError());
}

GameCenterCatalogSync _buildSync({
  required _FakeKv kv,
  required http.Response Function(http.Request) respondRead,
}) {
  final reader = PublicKvReader(
    baseUrl: 'http://kv-fake',
    groupId: 190,
    client: MockClient((req) async => respondRead(req)),
  );
  return GameCenterCatalogSync(kv: kv, baseUrl: 'http://kv-fake', reader: reader);
}

/// 构造 utf8 JSON 响应。必须显式带 charset：http.Response 默认按 latin1
/// 编码 body，中文会在 mock 往返中被替换成 `?`，比对永不相等。
http.Response _utf8Json(String body, [int status = 200]) => http.Response(
      body,
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  test('KV 已一致 → 不写（compare-then-write 的零写路径）', () async {
    final value = gameCenterCatalogJson(_fakeGames);
    final kv = _FakeKv((_) => throw StateError('不应发起写'));
    final sync = _buildSync(
      kv: kv,
      respondRead: (_) =>
          _utf8Json('{"code":0,"data":{"value":${jsonEncode(value)}}}'),
    );

    final wrote = await sync.sync(_fakeGames);

    expect(wrote, isFalse);
    expect(kv.calls, isEmpty);
  });

  test('KV 缺失 → 写一次，key/groupId/tags/visibility 全对', () async {
    final kv = _FakeKv((_) => const ApiResponse(code: 0, message: 'OK'));
    final sync = _buildSync(
      kv: kv,
      // 非 200 → readString 返回 null，视同「目录尚未发布」
      respondRead: (_) => _utf8Json('not found', 404),
    );

    final wrote = await sync.sync(_fakeGames);

    expect(wrote, isTrue);
    expect(kv.calls, hasLength(1));
    final call = kv.calls.single;
    expect(call.key, 'game-center_catalog:index');
    expect(call.value, gameCenterCatalogJson(_fakeGames));
    expect(call.groupId, 190);
    expect(call.tags, ['game-center-catalog']);
    expect(call.visibility, 'public');
  });

  test('KV 值过期（如缺了新游戏）→ 写一次新值', () async {
    final stale = gameCenterCatalogJson([_fakeGames.first]);
    final kv = _FakeKv((_) => const ApiResponse(code: 0, message: 'OK'));
    final sync = _buildSync(
      kv: kv,
      respondRead: (_) =>
          _utf8Json('{"code":0,"data":{"value":${jsonEncode(stale)}}}'),
    );

    final wrote = await sync.sync(_fakeGames);

    expect(wrote, isTrue);
    expect(kv.calls.single.value, gameCenterCatalogJson(_fakeGames));
  });

  test('写被拒（未登录 401 / 无权限 403）→ 静默 false，不抛', () async {
    final kv = _FakeKv(
      (_) => const ApiResponse(code: 401, message: 'unauthorized'),
    );
    final sync = _buildSync(kv: kv, respondRead: (_) => _utf8Json('', 404));

    final wrote = await sync.sync(_fakeGames);

    expect(wrote, isFalse);
    expect(kv.calls, hasLength(1));
  });

  test('网络异常（读挂→视为缺失，写抛错）→ 静默 false，不抛', () async {
    final kv = _FakeKv((_) => throw http.ClientException('boom'));
    final sync = _buildSync(
      kv: kv,
      respondRead: (_) => throw Exception('network down'),
    );

    final wrote = await sync.sync(_fakeGames);

    expect(wrote, isFalse);
  });
}
