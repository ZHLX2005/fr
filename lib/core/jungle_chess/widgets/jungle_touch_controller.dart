// lib/core/jungle_chess/widgets/jungle_touch_controller.dart
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import '../constants/jungle_constants.dart';
import '../models/piece.dart';
import '../models/game_state.dart';
import '../engine/jungle_engine.dart';

/// 触摸状态：
/// - idle：无选子
/// - dragging：正在拖动棋子（手指未抬起）
/// - pieceSelected：选中但未拖动（点击模式备用）
/// - moveConfirmed：已确认落点，等待外部消化
enum TouchPhase { idle, dragging, pieceSelected, moveConfirmed }

class JungleTouchController extends ChangeNotifier {
  TouchPhase phase = TouchPhase.idle;
  int? selectedIndex;
  List<Coord> validTargets = [];
  int? targetIndex;

  /// 拖动中手指在棋盘局部坐标系的实时位置（用于把棋子渲染在手指下）
  /// 坐标系：左上角为 (0,0)，单位是物理像素
  Offset? dragFingerPos;

  /// 拖动中手指命中格（用于目标点高亮）
  int? dragHoverIndex;

  /// 落子回调（由 JungleBoard 设置）：(from, to) 触发后清空状态
  void Function(Coord from, Coord to)? onMoveConfirmed;

  void onCellTap(GameState state, int index) {
    final piece = state.pieces[index];

    switch (phase) {
      case TouchPhase.idle:
      case TouchPhase.pieceSelected:
        if (piece != null && piece.isAlive && piece.color == state.currentTurn) {
          selectedIndex = index;
          validTargets = JungleEngine.getValidMoves(state, CoordUtils.fromIndex(index));
          phase = TouchPhase.pieceSelected;
          notifyListeners();
        }
        break;

      case TouchPhase.moveConfirmed:
        _reset();
        break;

      case TouchPhase.dragging:
        break;
    }
  }

  /// 手指按下某格（启动拖动）
  void onDragStart(GameState state, int index, Offset fingerPos) {
    final piece = state.pieces[index];
    if (piece == null || !piece.isAlive || piece.color != state.currentTurn) {
      return;
    }
    selectedIndex = index;
    validTargets = JungleEngine.getValidMoves(state, CoordUtils.fromIndex(index));
    dragFingerPos = fingerPos;
    dragHoverIndex = index;
    phase = TouchPhase.dragging;
    notifyListeners();
  }

  /// 手指拖动中（实时更新手指位置 + 命中格）
  void onDragUpdate(GameState state, Offset fingerPos) {
    if (phase != TouchPhase.dragging) return;
    dragFingerPos = fingerPos;
    // 计算手指当前所在格（仅棋盘范围内）
    final hit = _hitFromPos(state, fingerPos);
    final int? newHover = hit == null ? null : hit.row * kBoardCols + hit.col;
    if (dragHoverIndex != newHover) {
      dragHoverIndex = newHover;
    }
    notifyListeners();
  }

  /// 手指抬起（落子）
  void onDragEnd(GameState state, Offset fingerPos) {
    if (phase != TouchPhase.dragging) return;
    final hit = _hitFromPos(state, fingerPos);
    final dropIndex = hit == null ? null : hit.row * kBoardCols + hit.col;

    if (dropIndex != null && validTargets.any((c) => c.index == dropIndex)) {
      targetIndex = dropIndex;
      phase = TouchPhase.moveConfirmed;
      dragFingerPos = null;
      dragHoverIndex = null;
      notifyListeners();

      final from = CoordUtils.fromIndex(selectedIndex!);
      final to = CoordUtils.fromIndex(targetIndex!);
      final cb = onMoveConfirmed;
      _reset();
      cb?.call(from, to);
    } else {
      // 拖到非法位置：保持 pieceSelected 状态（视觉保持选中高亮）
      dragFingerPos = null;
      dragHoverIndex = null;
      phase = TouchPhase.pieceSelected;
      notifyListeners();
    }
  }

  /// 手指位置 → 棋盘格（行, 列）。越界返回 null。
  _Hit? _hitFromPos(GameState state, Offset localPos) {
    final cellSize = _lastCellSize;
    if (cellSize == null || cellSize <= 0) return null;
    if (localPos.dx < 0 ||
        localPos.dy < 0 ||
        localPos.dx >= cellSize * 7 ||
        localPos.dy >= cellSize * 9) {
      return null;
    }
    final col = (localPos.dx / cellSize).floor().clamp(0, 6);
    final row = (localPos.dy / cellSize).floor().clamp(0, 8);
    return _Hit(row: row, col: col);
  }

  /// 由 JungleBoard 注入当前 cellSize，使 controller 可做坐标反查
  double? _lastCellSize;
  void setCellSize(double cellSize) {
    _lastCellSize = cellSize;
  }

  void clearSelection() {
    _reset();
  }

  void _reset() {
    phase = TouchPhase.idle;
    selectedIndex = null;
    validTargets = [];
    targetIndex = null;
    dragFingerPos = null;
    dragHoverIndex = null;
    notifyListeners();
  }
}

class _Hit {
  final int row;
  final int col;
  const _Hit({required this.row, required this.col});
}