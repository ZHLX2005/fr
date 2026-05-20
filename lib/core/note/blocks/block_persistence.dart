import 'dart:convert';
import 'block.dart';
import 'block_tree.dart';

/// 块树序列化工具
///
/// 将运行时树（基于 _childrenOf 索引）序列化为嵌套 JSON，
/// 再从嵌套 JSON 恢复为 BlockTree。
class BlockTreeSerializer {
  /// 将树序列化为 JSON 字符串
  ///
  /// 序列化格式：扁平数组，每个块在其 children 字段中递归包含子块。
  /// 这样 BlockTree.fromJson / _rebuild 能正确重建索引。
  static String toJson(BlockTree tree) {
    final blocks = <Map<String, dynamic>>[];
    // 遍历根的子块
    for (final childId in tree.childIdsOf(BlockTree.rootId)) {
      final block = tree.get(childId);
      if (block == null) continue;
      blocks.add(_buildNestedJson(tree, childId));
    }
    return jsonEncode(blocks);
  }

  /// 递归构建嵌套 JSON（从索引重建 children）
  static Map<String, dynamic> _buildNestedJson(BlockTree tree, String blockId) {
    final block = tree.get(blockId)!;
    return {
      'id': block.id,
      'type': block.type.tag,
      'content': block.content.toJson(),
      'children': tree
          .childIdsOf(blockId)
          .map((cid) => _buildNestedJson(tree, cid))
          .toList(),
      'data': block.data.toMap(),
      'properties': Map.of(block.properties),
      'created_at': block.createdAt.millisecondsSinceEpoch,
      'updated_at': block.updatedAt.millisecondsSinceEpoch,
    };
  }

  /// 从 JSON 字符串恢复树
  static BlockTree fromJson(String json) {
    final list = jsonDecode(json) as List<dynamic>;
    final blocks = list.cast<Map<String, dynamic>>();
    return BlockTree.fromJson(blocks);
  }
}

/// Block 紧凑序列化（不含子块，用于存储引用）
class BlockSerializer {
  static Map<String, dynamic> compact(Block block) => {
        'id': block.id,
        'type': block.type.tag,
        'content': block.content.toJson(),
        'data': block.data.toMap(),
        'properties': Map.of(block.properties),
      };
}
