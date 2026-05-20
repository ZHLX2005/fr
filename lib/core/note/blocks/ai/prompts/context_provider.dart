import '../../block_tree.dart';

/// 构建当前页面所有块的文本列表（含 ID，供 AI 引用）
String buildFullBlockList(BlockTree tree) {
  final buf = StringBuffer();
  _flatBlockList(tree, BlockTree.rootId, 0, buf);
  return buf.toString();
}

void _flatBlockList(BlockTree tree, String parentId, int depth, StringBuffer buf) {
  for (final childId in tree.childIdsOf(parentId)) {
    final block = tree.get(childId);
    if (block == null) continue;
    final indent = '  ' * depth;
    final text = block.content.toPlainText();
    buf.writeln('$indent- [${block.type.tag}] id=$childId: $text');
    if (block.canHaveChildren) {
      _flatBlockList(tree, childId, depth + 1, buf);
    }
  }
}
