// lib/core/gomoku/skins/gomoku_skin_meta_sync.dart
//
// 五子棋 KV 索引拉取：gomoku_skin:index（对齐 chess_skin_meta_sync.dart）

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../chess/skins/chess_skin_localizer.dart';
import '../../chess/skins/file_resolver.dart';
import '../../chess/skins/public_kv_reader.dart';
import 'gomoku_skin.dart';
import 'gomoku_skin_meta.dart';

Future<bool> fetchAndMergeGomokuSkins({
  PublicKvReader? reader,
  FileResolver? resolver,
}) async {
  unawaited(ChessSkinLocalizer.ensureBaseDirInit());
  final kv = reader ??
      PublicKvReader(
        baseUrl: kDefaultGomokuSkinBaseUrl,
        groupId: PublicKvReader.kChessSkinPublicGroupId,
      );
  final fileResolver = resolver ?? PublicFileResolver(baseUrl: kv.baseUrl);
  final jsonText = await kv.readString('gomoku_skin:index');
  if (jsonText == null) {
    _log('gomoku KV index 缺失/读取失败 → 回退空 catalog');
    return false;
  }
  final List<GomokuSkinMeta> metas;
  try {
    metas = GomokuSkinMeta.parseList(jsonText);
  } catch (e) {
    _log('gomoku KV 解析失败（${e.runtimeType}）→ 回退');
    return false;
  }
  GomokuSkinBundle.registerRemoteSkins(metas, fileResolver: fileResolver);
  _log('gomoku KV 合入完成：${metas.length} 套（${metas.map((m) => m.id).join(', ')}）');
  return true;
}

void _log(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[gomoku-skin-kv] $msg');
  }
}
