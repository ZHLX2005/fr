// lib/core/chess/skins/remote_chess_skin.dart
//
// 把 ChessSkinMeta + FileResolver 组合成一个 ChessSkin：
//   · pieces 12 个 key 全部映射成 CachedNetworkImage（fileResolver 给 URL）
//   · boardBackground 可选；null 时 UI 走主题双格色
//   · ImageProvider 缓存由 cached_network_image 自带（默认 7 天磁盘）
//
// 注：cached_network_image 3.x 中 `CachedNetworkImage` 是 Widget，
// ImageProvider 实现是 `CachedNetworkImageProvider(url)`（构造第一个位置参数即 url）。

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/widgets.dart' show ImageProvider;

import 'chess_skin.dart';
import 'chess_skin_meta.dart';
import 'file_resolver.dart';

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

  /// 12 个 piece → CachedNetworkImage（按 spec §3.2）
  ///
  /// 懒计算：首次访问时构造 12 个 CachedNetworkImage；cached_network_image 内部缓存。
  @override
  Map<String, ImageProvider> get pieces => {
        for (final entry in meta.pieces.entries)
          entry.key: CachedNetworkImageProvider(fileResolver.url(entry.value.fileId)),
      };

  /// 棋盘底图（可选，null 时 UI 走主题双格色）
  @override
  ImageProvider? get boardBackground {
    final bg = meta.boardBackground;
    if (bg == null) return null;
    return CachedNetworkImageProvider(fileResolver.url(bg.fileId));
  }
}
