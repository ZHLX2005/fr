import 'block_op.dart';
import 'block_tree.dart';

/// 操作历史栈 —— 支持撤销 / 重做的 Event Sourcing
class OperationHistory {
  final BlockTree _tree;

  /// undo 栈：最近的操作在栈顶
  final List<_HistoryEntry> _undoStack = [];

  /// redo 栈
  final List<_HistoryEntry> _redoStack = [];

  /// 最大历史记录数
  static const int maxHistory = 200;

  /// 合并窗口（毫秒）：此时间内的相邻同类操作合并
  static const int mergeWindowMs = 300;

  OperationHistory(this._tree);

  /// 最近一次操作的时间戳
  DateTime? _lastOpTime;

  /// 批量应用操作指令集
  void apply(List<BlockOp> ops) {
    final reverses = <BlockOp>[];
    for (final op in ops) {
      final reverse = op.apply(_tree);
      reverses.add(reverse);
    }

    _redoStack.clear();
    _undoStack.add(_HistoryEntry(ops, reverses));
    if (_undoStack.length > maxHistory) {
      _undoStack.removeAt(0);
    }
    _lastOpTime = DateTime.now();
  }

  /// 记录单次操作（带合并）
  void applySingle(BlockOp op) {
    // 合并判断：相邻 UpdateBlock 且 id 相同
    final now = DateTime.now();
    if (_lastOpTime != null &&
        now.difference(_lastOpTime!).inMilliseconds < mergeWindowMs &&
        _undoStack.isNotEmpty) {
      final last = _undoStack.last;
      final lastOps = last.ops;
      if (lastOps.length == 1 && lastOps.first is UpdateBlock) {
        final lastUpdate = lastOps.first as UpdateBlock;
        if (op is UpdateBlock && lastUpdate.id == op.id) {
          // 替换最后一条（丢弃旧的反向操作）
          final newReverse = op.apply(_tree);
          _undoStack.last = _HistoryEntry([op], [newReverse]);
          _lastOpTime = now;
          return;
        }
      }
    }

    apply([op]);
  }

  /// 撤销
  void undo() {
    if (_undoStack.isEmpty) return;
    final entry = _undoStack.removeLast();
    final redoOps = <BlockOp>[];
    for (final reverse in entry.reverses) {
      final redoReverse = reverse.apply(_tree);
      redoOps.add(redoReverse);
    }
    _redoStack.add(_HistoryEntry(redoOps, entry.reverses));
  }

  /// 重做
  void redo() {
    if (_redoStack.isEmpty) return;
    final entry = _redoStack.removeLast();
    final undoOps = <BlockOp>[];
    for (final op in entry.ops) {
      final undoReverse = op.apply(_tree);
      undoOps.add(undoReverse);
    }
    _undoStack.add(_HistoryEntry(entry.ops, entry.reverses));
  }

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  void clear() {
    _undoStack.clear();
    _redoStack.clear();
  }
}

class _HistoryEntry {
  final List<BlockOp> ops;
  final List<BlockOp> reverses;

  const _HistoryEntry(this.ops, this.reverses);
}
