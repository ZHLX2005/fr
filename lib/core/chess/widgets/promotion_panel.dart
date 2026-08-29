// lib/core/chess/widgets/promotion_panel.dart
//
// 升变选择面板 —— 悬浮在棋盘上，让玩家从 后/车/象/马 中选一个升变棋子。
//
// 设计：
//   · 输入 = (ChessSkin skin, PieceColor promotingColor, onSelected, onCancel)
//   · 用 skin.pieces 渲染 4 个棋子图像（Q/R/B/N × promotingColor），
//     点击 → onSelected(type)。背景半透明遮罩，点击遮罩 → onCancel。
//   · 颜色走 context.chessColors（v6.2.1 第 6 strategy 通道）：
//       promotionOverlay → 面板背景
//       promotionBorder  → 面板边框
//   · 图像缺 key 时（如 ChessDefaultSkin）走 unicode 字符 fallback
//     （kUnicodePieces 查表，与 chess_board 的 _unicodeFallback 一致）。
//
// 不负责：
//   · 走法应用 / 状态推进（ChessController 拿到所选 PieceType 后自己 apply + emit）

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../constants/chess_constants.dart';
import '../models/piece.dart';
import '../skins/chess_skin.dart';

/// 升变选择面板 —— 悬浮在棋盘上，让玩家从 后/车/象/马 中选一个升变棋子。
///
/// 用 [skin.pieces] 渲染 4 个棋子图像（Q/R/B/N × promotingColor），
/// 点击 → [onSelected]。背景半透明遮罩，点击遮罩 → [onCancel]。
class PromotionPanel extends StatelessWidget {
  /// 4 个升变候选（升变不能是 king 或 pawn）。
  static const List<PieceType> kCandidateTypes = [
    PieceType.queen,
    PieceType.rook,
    PieceType.bishop,
    PieceType.knight,
  ];

  /// 当前使用的皮肤（决定棋子图像）。
  final ChessSkin skin;

  /// 升变方颜色（决定用白子还是黑子图像）。
  final PieceColor promotingColor;

  /// 玩家选中某个升变类型时回调。
  final void Function(PieceType type) onSelected;

  /// 点击遮罩 / 面板外区域时回调（取消升变，可选）。
  final VoidCallback? onCancel;

  const PromotionPanel({
    super.key,
    required this.skin,
    required this.promotingColor,
    required this.onSelected,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return GestureDetector(
      // 点击遮罩（非按钮区）→ 取消升变
      behavior: HitTestBehavior.opaque,
      onTap: onCancel,
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        alignment: Alignment.center,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: colors.promotionOverlay,
            border: Border.all(color: colors.promotionBorder, width: 2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final type in kCandidateTypes)
                _PromotionButton(
                  skin: skin,
                  type: type,
                  color: promotingColor,
                  onTap: () => onSelected(type),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 单个升变候选按钮 —— 棋子图（或 unicode fallback）+ 点击区。
class _PromotionButton extends StatelessWidget {
  final ChessSkin skin;
  final PieceType type;
  final PieceColor color;
  final VoidCallback onTap;

  const _PromotionButton({
    required this.skin,
    required this.type,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const buttonSize = 56.0;
    final key = chessSkinKeyOf(color, type);
    final image = skin.pieces[key];
    final child = image == null
        // fallback：unicode 字符（key 形如 'wQ' / 'bp'；FEN char = type char，颜色决定大小写）
        ? Center(
            child: Text(
              kUnicodePieces[
                      (color == PieceColor.white
                          ? type.name[0].toUpperCase()
                          : type.name[0])] ??
                  '?',
              style: TextStyle(fontSize: buttonSize * 0.62),
            ),
          )
        : Image(
            image: image,
            fit: BoxFit.contain,
            width: buttonSize,
            height: buttonSize,
            gaplessPlayback: true,
          );
    return Padding(
      padding: const EdgeInsets.all(4),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: child,
        ),
      ),
    );
  }
}
