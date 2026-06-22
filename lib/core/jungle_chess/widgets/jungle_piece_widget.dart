// lib/core/jungle_chess/widgets/jungle_piece_widget.dart
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../models/piece.dart';
import '../constants/jungle_constants.dart';

/// 圆形棋子：
/// - 底盘：象牙白填充 + 木纹棕描边 + 阴影
/// - 描边外圈：根据 playerColor 显示蓝/红强调（双层圆环）
/// - 居中：animal SVG icon（占圆盘 kPieceIconRatio）
/// - 选中：金色高亮环 + 发光阴影
/// - elevated（拖动中）：阴影更浮起
class JunglePieceWidget extends StatelessWidget {
  final Piece piece;
  final bool isSelected;
  final VoidCallback? onTap;
  final double size;
  final bool elevated;

  const JunglePieceWidget({
    super.key,
    required this.piece,
    this.isSelected = false,
    this.onTap,
    this.size = kCellSize,
    this.elevated = false,
  });

  @override
  Widget build(BuildContext context) {
    final diskSize = size * kPieceRatio;
    final accentColor =
        piece.color == PlayerColor.blue ? kBluePieceTint : kRedPieceTint;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: diskSize,
        height: diskSize,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: kPieceDiskColor,
          border: Border.all(
            color: kPieceDiskBorder,
            width: kPieceBorderWidth,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: elevated ? 0.3 : 0.18),
              blurRadius: elevated ? 12 : 4,
              offset: Offset(0, elevated ? 6 : 2),
            ),
            if (isSelected)
              BoxShadow(
                color: Colors.amber.withValues(alpha: 0.7),
                blurRadius: 12,
                spreadRadius: 1,
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: accentColor.withValues(alpha: isSelected ? 1.0 : 0.85),
                  width: 1.5,
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(diskSize * (1 - kPieceIconRatio) / 2),
              child: SvgPicture.asset(
                piece.assetPath,
                fit: BoxFit.contain,
              ),
            ),
            if (isSelected)
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.amber, width: 3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}