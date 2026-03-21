import 'home_item.dart';

/// 拖拽状态
class DragState {
  final String? draggingId;
  final int? hoverIndex;
  final String? hoverOverItemId;
  final bool isFolderHover;

  const DragState({
    this.draggingId,
    this.hoverIndex,
    this.hoverOverItemId,
    this.isFolderHover = false,
  });

  DragState copyWith({
    String? draggingId,
    int? hoverIndex,
    String? hoverOverItemId,
    bool? isFolderHover,
  }) {
    return DragState(
      draggingId: draggingId ?? this.draggingId,
      hoverIndex: hoverIndex ?? this.hoverIndex,
      hoverOverItemId: hoverOverItemId ?? this.hoverOverItemId,
      isFolderHover: isFolderHover ?? this.isFolderHover,
    );
  }

  static const DragState empty = DragState();
}

/// 命令抽象类
abstract class HomeCommand {
  List<HomeItem> apply(List<HomeItem> current);
  List<HomeItem> undo(List<HomeItem> current);
}

/// 排序命令
class ReorderCommand implements HomeCommand {
  final List<HomeItem> before;
  final List<HomeItem> after;

  ReorderCommand(this.before, this.after);

  @override
  List<HomeItem> apply(List<HomeItem> current) => after;
  @override
  List<HomeItem> undo(List<HomeItem> current) => before;
}

/// 合并到文件夹命令
class MergeToFolderCommand implements HomeCommand {
  final List<HomeItem> before;
  final List<HomeItem> after;

  MergeToFolderCommand(this.before, this.after);

  @override
  List<HomeItem> apply(List<HomeItem> current) => after;
  @override
  List<HomeItem> undo(List<HomeItem> current) => before;
}

/// 历史栈
class HistoryStack {
  final List<HomeCommand> _undo = [];

  void push(HomeCommand cmd) {
    _undo.add(cmd);
  }

  HomeCommand? popUndo() {
    if (_undo.isEmpty) return null;
    return _undo.removeLast();
  }

  bool get canUndo => _undo.isNotEmpty;

  int get length => _undo.length;
}
