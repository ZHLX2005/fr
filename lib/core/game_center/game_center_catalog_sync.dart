// 游戏中心目录自动同步 — compare-then-write。
//
// 打开游戏中心时调用 [sync]：派生目录与 KV public 当前值比对，一致则零写
//（绝大多数情况）；有差异才 POST 覆盖。未登录 / 非 owner·admin 时写会被
// 后端拒绝（401/403），静默返回 false —— 普通用户打开页面最多多一次匿名
// GET，无副作用。token 过期的静默重铸（SSO）由 ApiClient 的
// AuthInterceptor 负责，这里不感知。
//
// 只同步、不重试、不阻塞 UI：调用方 unawaited，失败下次打开再试。
// 调用点在 GameCenterPage.initState（每进程至多一次）。

import 'package:flutter/foundation.dart';

import '../../api/goframe/kv/kv_endpoint.dart';
import 'game_center_catalog.dart';
import '../game_kit/skin/public_kv_reader.dart';

class GameCenterCatalogSync {
  GameCenterCatalogSync({
    required KvOps kv,
    required String baseUrl,
    PublicKvReader? reader,
  })  : _kv = kv,
        _reader =
            reader ?? PublicKvReader(baseUrl: baseUrl, groupId: kCatalogGroupId);

  /// 与 ve CoversListView / 历史 tool 脚本保持同一 key/tag/组。
  static const String kvKey = 'game-center_catalog:index';
  static const String tag = 'game-center-catalog';
  static const int kCatalogGroupId = PublicKvReader.kPublicGroupId; // 190

  final KvOps _kv;
  final PublicKvReader _reader;

  /// 派生目录与 KV 比对，有差异才写回。返回是否发生了写。
  /// 任何失败（网络/未登录/无权限）都不抛，静默 false。
  Future<bool> sync(List<GameCenterCatalogEntry> entries) async {
    final value = gameCenterCatalogJson(entries);
    try {
      final current = await _reader.readString(kvKey);
      if (current == value) {
        _log('KV 已一致，跳过写（${entries.length} games）');
        return false;
      }
      final resp = await _kv.set(
        key: kvKey,
        value: value,
        groupId: kCatalogGroupId,
        tags: const [tag],
        visibility: 'public',
      );
      if (!resp.isSuccess) {
        _log('写回被拒 code=${resp.code} ${resp.message}'
            '（未登录或非 owner/admin 属预期，静默）');
        return false;
      }
      _log('目录已同步：${entries.length} games');
      return true;
    } catch (e) {
      _log('同步失败（下次打开重试）: $e');
      return false;
    }
  }

  void _log(String msg) {
    if (kDebugMode) {
      // ignore: avoid_print
      print('[game-center-catalog] $msg');
    }
  }
}
