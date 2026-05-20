import 'block.dart';

/// 扁平化树节点。AI Context Builder 将 BlockTree 深度优先展开为此结构。
///
/// [depth] 记录在树中的缩进层级，[parentId] 记录父块 ID，
/// 供 AI 理解文档的嵌套结构。
class FlatBlock {
  final Block block;
  final int depth;
  final String parentId;

  const FlatBlock(this.block, this.depth, this.parentId);
}
