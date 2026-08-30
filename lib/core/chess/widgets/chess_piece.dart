// lib/core/chess/widgets/chess_piece.dart
//
// 单个棋子的 Image 渲染 —— 走 [ChessSkin] 提供的 ImageProvider。
//
// 设计：
//   · 输入 = (ImageProvider image, double size)，不含业务坐标 / 颜色，
//     业务信息（"是什么棋子、什么颜色、在哪格"）由调用方（chess_board）解析后传入。
//   · 输出 = 一个透明背景的 Image（fit=contain），由父层 GridView / Stack 定位。
//   · 不依赖 context.chessColors —— 棋子本体颜色由皮肤 Image 决定（PNG 自带 alpha）。
//
// 默认 fallback：当 [ChessSkin.pieces] 不含该棋子 key 时，UI 走 unicode 字符。
// 本 widget 不管"缺 key"的 fallback —— [ChessBoard] 在 pieces 缺 key 时改走
// Text(... unicode) 渲染。本文件只负责"有图时怎么画图"。
//
// 加载失败兜底（Fix C）：传入 [pieceKey] 后，Image.errorBuilder 在网络图
// 加载失败（离线 / 404 / 解码错）时渲染 unicode 字符 —— 绝不留一个
// 永不完成的 loading 占位。

import 'package:flutter/widgets.dart';

import '../constants/chess_constants.dart';

/// 渲染单个棋子图（PNG / WebP 透明图）。
///
/// 仅持有 image + size；不含 board / state / color 等业务字段。
/// 上层 [ChessBoard] 负责把 (row, col) → size + skin lookup。
class ChessPiece extends StatelessWidget {
  /// 皮肤提供的图片 provider（[FileImage] / [CachedNetworkImageProvider] 等）。
  final ImageProvider image;

  /// 渲染尺寸（边长 px；父层按格子大小计算）。
  final double size;

  /// 皮肤 piece key（'wK' / 'bp'…）。仅供 [errorBuilder] unicode 兜底用；
  /// null 时兜底 '?'（兼容不传 key 的旧调用方 / 测试）。
  final String? pieceKey;

  const ChessPiece({
    super.key,
    required this.image,
    required this.size,
    this.pieceKey,
  });

  @override
  Widget build(BuildContext context) {
    final fallbackChar =
        pieceKey == null ? '?' : chessPieceUnicodeFallback(pieceKey!);
    return Image(
      image: image,
      width: size,
      height: size,
      fit: BoxFit.contain,
      // 透明背景：棋子 PNG 自带 alpha，棋盘两色格透过来
      gaplessPlayback: true,
      // Fix C：网络图加载失败 → unicode 字符兜底（不留 loading 占位 / 不抛错）。
      errorBuilder: (_, _, _) => Center(
        child: Text(
          fallbackChar,
          style: TextStyle(fontSize: size * 0.7),
        ),
      ),
    );
  }
}
