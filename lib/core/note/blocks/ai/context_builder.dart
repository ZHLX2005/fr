import '../block.dart';
import '../block_tree.dart';

/// 滑动窗口上下文构建器
///
/// 为 AI 构建当前选中块周围的上下文，而不是发送整棵文档树。
class ContextBuilder {
  final BlockTree tree;
  final int windowSize;

  const ContextBuilder(this.tree, {this.windowSize = 30});

  /// 以 selectedId 为中心构建上下文文本
  String build(String selectedId) {
    final flat = _flattenFlat(tree.childIdsOf(BlockTree.rootId), 0);
    final idx = flat.indexWhere((f) => f.block.id == selectedId);
    if (idx < 0) return _buildEmptyContext();

    final half = windowSize ~/ 2;
    final start = (idx - half).clamp(0, flat.length);
    final end = (idx + half).clamp(0, flat.length);

    final buf = StringBuffer();
    buf.writeln('## 文档上下文（选中块附近 $windowSize 个块）\n');

    for (int i = start; i < end; i++) {
      final entry = flat[i];
      final indent = '  ' * entry.depth;
      final isSelected = entry.block.id == selectedId ? ' ← **选中**' : '';
      final parentHint = isSelected.isNotEmpty
          ? ' [路径: ${tree.pathToRoot(entry.block.id).join(" > ")}]'
          : '';

      buf.writeln('$indent- [${entry.block.type.tag}] id=${entry.block.id}: ${entry.block.content.toPlainText()}$isSelected$parentHint');
    }

    return buf.toString();
  }

  /// 构建当前文档的概要（标题层级结构）
  String buildOutline() {
    final buf = StringBuffer();
    buf.writeln('## 文档大纲\n');
    _buildOutlineRecursive(BlockTree.rootId, 0, buf);
    return buf.toString();
  }

  void _buildOutlineRecursive(String parentId, int depth, StringBuffer buf) {
    for (final childId in tree.childIdsOf(parentId)) {
      final block = tree.get(childId);
      if (block == null) continue;
      final indent = '  ' * depth;
      if (block.type.tag == 'heading') {
        final level = block.data.get<int>('level') ?? 1;
        buf.writeln('$indent${"#" * level} ${block.content.toPlainText()}');
      }
      _buildOutlineRecursive(childId, depth + 1, buf);
    }
  }

  /// 构建完整文档文本（纯文本格式，用于全文搜索等）
  String buildFullText() {
    final buf = StringBuffer();
    _fullTextRecursive(BlockTree.rootId, buf);
    return buf.toString();
  }

  void _fullTextRecursive(String parentId, StringBuffer buf) {
    for (final childId in tree.childIdsOf(parentId)) {
      final block = tree.get(childId);
      if (block == null) continue;
      final text = block.content.toPlainText().trim();
      if (text.isNotEmpty) {
        buf.writeln(text);
      }
      _fullTextRecursive(childId, buf);
    }
  }

  String _buildEmptyContext() {
    return '## 文档上下文\n\n（空文档，尚无内容）\n';
  }

  List<_FlatEntry> _flattenFlat(List<String> childIds, int depth) {
    final result = <_FlatEntry>[];
    for (final childId in childIds) {
      final block = tree.get(childId);
      if (block == null) continue;
      result.add(_FlatEntry(block, depth));
      if (block.canHaveChildren) {
        result.addAll(_flattenFlat(tree.childIdsOf(childId), depth + 1));
      }
    }
    return result;
  }
}

class _FlatEntry {
  final Block block;
  final int depth;
  const _FlatEntry(this.block, this.depth);
}
