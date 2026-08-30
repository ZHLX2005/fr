// lib/core/chess/skins/chess_skin_meta_sync.dart
//
// 皮肤元数据混合加载：KV public 覆盖 > 本地 hardcode catalog（"换肤免发版"）。
//
// 背景（2026-08-29）：后端 KV public 读匿名可用（GET /api/v1/kv/public/:key
// ?groupId=190，见 public_kv_reader.dart），图片走 /files/<fileId> 匿名下载
// （file_resolver.dart）。于是 dart 端保留 7 套 const catalog 作基线，
// 启动时 fire-and-forget 拉一次 KV index JSON：
//   · 成功 → 解析成 List<ChessSkinMeta> → 覆盖/扩展 ChessSkinBundle
//   · 失败 / 缺失 / 格式错 → 静默保留本地 catalog（零回归）
//
// 时序：main() 在 registerHardcoded() 之后调用 [fetchAndMergeSkins]()，
// 不 await（unawaited）—— 绝不阻塞冷启动、绝不 crash。
//
// 幂等：KV 反复拉取可重复调用；同 id 覆盖、新 id 追加、本地 id 不删。

import 'package:flutter/foundation.dart' show kDebugMode;

import 'chess_skin.dart';
import 'chess_skin_meta.dart';
import 'file_resolver.dart';
import 'public_kv_reader.dart';

/// 拉取 KV public 皮肤 meta 索引并合入 [ChessSkinBundle]。
///
/// [reader] / [resolver] 可注入（测试用 MockClient + fake resolver）；
/// 默认从 [PublicKvReader] 读索引、用 [PublicFileResolver] 拼 /files 图 URL。
///
/// 返回 true 表示成功合入 KV 皮肤；false 表示回退本地（KV 缺失/失败/解析错）。
/// 任何情况都**不抛异常** —— 这是启动期 best-effort 路径。
Future<bool> fetchAndMergeSkins({
  PublicKvReader? reader,
  FileResolver? resolver,
}) async {
  final kv = reader ?? PublicKvReader(baseUrl: kDefaultChessSkinBaseUrl);
  // KV 皮肤图的 URL 用 reader 同源 baseUrl（不要 hardcode host）
  final fileResolver =
      resolver ?? PublicFileResolver(baseUrl: kv.baseUrl);

  // 1. 读 KV index（失败返回 null → 回退本地）
  final jsonText = await kv.readString(PublicKvReader.kSkinsIndexKey);
  if (jsonText == null) {
    _log('KV 皮肤 index 读取失败/缺失 → 回退本地 catalog');
    return false;
  }

  // 2. 解析成 List<ChessSkinMeta>（duplicate / invalid id → FormatException → 回退）
  final List<ChessSkinMeta> metas;
  try {
    metas = ChessSkinMeta.parseList(jsonText);
  } catch (e) {
    _log('KV 皮肤 index 解析失败（${e.runtimeType}）→ 回退本地 catalog');
    return false;
  }

  // 3. 覆盖/扩展注册表（同 id 覆盖、新 id 追加、default 与本地 id 不动）
  ChessSkinBundle.registerRemoteSkins(metas, fileResolver: fileResolver);
  _log('KV 皮肤 index 合入完成：${metas.length} 套（${metas.map((m) => m.id).join(', ')}）');
  return true;
}

/// 调试日志 —— 不引第三方 logger（chess 模块惯例）；release 静默。
void _log(String msg) {
  if (kDebugMode) {
    // ignore: avoid_print
    print('[chess-skin-kv] $msg');
  }
}
