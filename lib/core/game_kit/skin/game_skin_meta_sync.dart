// lib/core/game_kit/skin/game_skin_meta_sync.dart
//
// Generic KV sync helper: fetch + parse + register.

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;

import 'file_resolver.dart';
import 'game_skin_bundle.dart';
import 'game_skin_localizer.dart';
import 'public_kv_reader.dart';

Future<bool> fetchAndMergeSkinsFor(
  GameSkinBundle bundle, {
  PublicKvReader? reader,
  FileResolver? resolver,
  required String defaultBaseUrl,
}) async {
  final spec = bundle.spec;
  unawaited(GameSkinLocalizer.ensureBaseDirInitFor(spec));
  final kv = reader ?? PublicKvReader(baseUrl: defaultBaseUrl, groupId: spec.groupId);
  final fileResolver = resolver ?? PublicFileResolver(baseUrl: kv.baseUrl);
  final jsonText = await kv.readString(spec.kvIndexKey);
  if (jsonText == null) {
    _log(spec.gameId, 'KV index 读取失败/缺失 → 回退本地 catalog');
    return false;
  }
  final metas = bundle.parseAndValidate(jsonText);
  if (metas == null) {
    _log(spec.gameId, 'KV index 解析失败 → 回退本地 catalog');
    return false;
  }
  bundle.registerRemoteSkins(metas, fileResolver: fileResolver);
  _log(spec.gameId, 'KV index 合入完成：${metas.length} 套（${metas.map((m) => m.id).join(', ')}）');
  return true;
}

void _log(String gameId, String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[$gameId-skin-kv] $msg');
  }
}
