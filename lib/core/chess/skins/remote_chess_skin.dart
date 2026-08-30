// lib/core/chess/skins/remote_chess_skin.dart
//
// 把 ChessSkinMeta + FileResolver 组合成一个 ChessSkin：
//   · pieces 12 个 key 全部映射成 ImageProvider（**本地文件优先**，Fix B）
//   · boardBackground 可选；null 时 UI 走主题双格色
//   · 网络路径用 CachedNetworkImageProvider（内部缓存由 cached_network_image
//     自带，默认 7 天磁盘）
//
// 本地文件优先（Fix B —— 干掉"已下载皮肤仍每帧走网络"）：
//   · ChessSkinLocalizer.download() 把皮肤落盘到
//     `<documents>/chess_skins/<id>/<pieceKey>.webp` 后，本类的
//     pieces/boardBackground 立即改供 FileImage（零网络、离线可用）；
//   · 判存走 ChessSkinLocalizer.cachedPieceFile（同步 + memo，无每帧 IO）；
//   · 根目录未初始化 / 文件缺失 → 回退网络（与旧版行为一致）。
//
// 注：cached_network_image 3.x 中 `CachedNetworkImage` 是 Widget，
// ImageProvider 实现是 `CachedNetworkImageProvider(url)`（构造第一个位置参数即 url）。

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/painting.dart' show FileImage, ImageProvider;

import 'chess_skin.dart';
import 'chess_skin_localizer.dart';
import 'chess_skin_meta.dart';
import 'file_resolver.dart';
import 'local_chess_skin.dart';

class RemoteChessSkin implements ChessSkin {
  final ChessSkinMeta meta;
  final FileResolver fileResolver;

  const RemoteChessSkin({
    required this.meta,
    required this.fileResolver,
  });

  /// 皮肤 id / 显示名直接来自 metadata（spec §3.3 注册表按 meta.id 建键）
  @override
  String get id => meta.id;

  @override
  String get displayName => meta.displayName;

  /// 12 个 piece → ImageProvider（本地文件优先；未缓存回退网络）
  ///
  /// 懒计算：首次访问时构造 12 个 provider；本地判存带 memo
  /// （ChessSkinLocalizer.cachedPieceFile），不产生每帧同步 IO。
  @override
  Map<String, ImageProvider> get pieces => {
        for (final entry in meta.pieces.entries)
          entry.key: _providerFor('${entry.key}.webp', entry.value.fileId),
      };

  /// 棋盘底图（可选；本地文件优先，null 时 UI 走主题双格色）
  @override
  ImageProvider? get boardBackground {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return _providerFor(LocalChessSkin.boardBackgroundFileName(bg), bg.fileId);
  }

  /// 单个资源 → 本地文件优先的 ImageProvider。
  ///
  /// [localFileName] 是缓存目录里的叶子文件名（`wK.webp` /
  /// `boardBackground.webp`）；[fileId] 是网络回退用的 server 文件 id。
  ImageProvider _providerFor(String localFileName, String fileId) {
    final local = ChessSkinLocalizer.cachedPieceFile(meta.id, localFileName);
    if (local != null) return FileImage(local);
    return CachedNetworkImageProvider(fileResolver.url(fileId));
  }
}
