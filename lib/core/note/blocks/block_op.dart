import 'block.dart';
import 'block_id.dart';
import 'block_tree.dart';
import 'block_type.dart';
import 'rich_text.dart';

/// 块操作指令 —— AI 对文档树的修改原语
///
/// 每个操作可逆（通过 [reverse] 获取逆操作）
sealed class BlockOp {
  const BlockOp();

  /// 执行操作并返回逆操作
  BlockOp apply(BlockTree tree);

  /// 直接获取逆操作（不执行）
  BlockOp get reverse;

  String get opType;
}

// ──────────── InsertBlock ────────────

class InsertBlock extends BlockOp {
  final Block block;
  final String parentId;
  final String? afterId;

  const InsertBlock(this.block, {required this.parentId, this.afterId});

  @override
  BlockOp apply(BlockTree tree) {
    tree.insert(block, parentId: parentId, afterId: afterId);
    return DeleteBlock(block.id);
  }

  @override
  BlockOp get reverse => DeleteBlock(block.id);

  @override
  String get opType => 'insert_block';
}

// ──────────── UpdateBlock ────────────

class UpdateBlock extends BlockOp {
  final String id;
  final RichText? content;
  final BlockType? type;
  final BlockData? data;
  final Map<String, dynamic>? properties;

  const UpdateBlock(this.id, {this.content, this.type, this.data, this.properties});

  @override
  BlockOp apply(BlockTree tree) {
    final block = tree.get(id);
    if (block == null) return NopOp();

    tree.update(id, content: content, type: type, data: data, properties: properties);
    return UpdateBlock(id,
        content: block.content,
        type: block.type,
        data: block.data,
        properties: Map.of(block.properties));
  }

  @override
  BlockOp get reverse => UpdateBlock(id,
      content: content, type: type, data: data, properties: properties);

  @override
  String get opType => 'update_block';
}

// ──────────── DeleteBlock ────────────

class DeleteBlock extends BlockOp {
  final String id;

  const DeleteBlock(this.id);

  @override
  BlockOp apply(BlockTree tree) {
    final block = tree.get(id);
    final parentId = tree.parentIdOf(id);
    if (block == null || parentId == null) return NopOp();

    tree.remove(id);
    return InsertBlock(block, parentId: parentId);
  }

  @override
  BlockOp get reverse => InsertBlock(
        Block(id: id, type: BlockType.paragraph),
        parentId: BlockTree.rootId,
      );

  @override
  String get opType => 'delete_block';
}

// ──────────── MoveBlock ────────────

class MoveBlock extends BlockOp {
  final String id;
  final String newParentId;
  final String? afterId;

  const MoveBlock(this.id, {required this.newParentId, this.afterId});

  @override
  BlockOp apply(BlockTree tree) {
    final oldParentId = tree.parentIdOf(id);
    if (oldParentId == null) return NopOp();

    // 找到 afterId 在原 siblings 中的位置
    final oldSiblings = tree.childIdsOf(oldParentId);
    final oldIdx = oldSiblings.indexOf(id);
    final oldAfterId = oldIdx > 0 ? oldSiblings[oldIdx - 1] : null;

    tree.move(id, newParentId: newParentId, afterId: afterId);
    return MoveBlock(id, newParentId: oldParentId, afterId: oldAfterId);
  }

  @override
  BlockOp get reverse => MoveBlock(id, newParentId: newParentId, afterId: afterId);

  @override
  String get opType => 'move_block';
}

// ──────────── MergeBlocks ────────────

class MergeBlocks extends BlockOp {
  final String sourceId;
  final String targetId;

  const MergeBlocks(this.sourceId, this.targetId);

  @override
  BlockOp apply(BlockTree tree) {
    final source = tree.get(sourceId);
    final target = tree.get(targetId);
    if (source == null || target == null) return NopOp();

    final mergedContent = RichText([
      ...target.content.spans,
      ...source.content.spans,
    ]);

    tree.update(targetId, content: mergedContent);
    tree.remove(sourceId);

    return SplitBlock(targetId, target.content.spans.length, removedBlock: source);
  }

  @override
  BlockOp get reverse => SplitBlock(targetId, 0);

  @override
  String get opType => 'merge_blocks';
}

// ──────────── SplitBlock ────────────

class SplitBlock extends BlockOp {
  final String id;
  final int splitOffset;
  final Block? removedBlock; // 仅用于 reverse

  const SplitBlock(this.id, this.splitOffset, {this.removedBlock});

  @override
  BlockOp apply(BlockTree tree) {
    final block = tree.get(id);
    if (block == null) return NopOp();

    final text = block.content.toPlainText();
    if (splitOffset <= 0 || splitOffset >= text.length) return NopOp();

    // 前半段保留在原块
    final frontSpans = _splitSpans(block.content.spans, splitOffset, isFront: true);
    // 后半段放入新块
    final backSpans = _splitSpans(block.content.spans, splitOffset, isFront: false);

    tree.update(id, content: RichText(frontSpans));

    final newBlock = Block(
      id: BlockId.generate(),
      type: block.type,
      content: RichText(backSpans),
    );

    final parentId = tree.parentIdOf(id)!;
    tree.insert(newBlock, parentId: parentId, afterId: id);

    return MergeBlocks(newBlock.id, id);
  }

  @override
  BlockOp get reverse => removedBlock != null
      ? InsertBlock(removedBlock!, parentId: BlockTree.rootId)
      : NopOp();

  @override
  String get opType => 'split_block';

  List<Span> _splitSpans(List<Span> spans, int offset, {required bool isFront}) {
    final result = <Span>[];
    int accumulated = 0;

    for (final span in spans) {
      final end = accumulated + span.text.length;
      if (isFront && accumulated >= offset) break;
      if (!isFront && accumulated >= offset) {
        result.add(span);
      } else if (offset > accumulated && offset < end) {
        // 跨度跨越分割点
        final splitPos = offset - accumulated;
        if (isFront) {
          result.add(Span(span.text.substring(0, splitPos), format: span.format));
        } else {
          result.add(Span(span.text.substring(splitPos), format: span.format));
        }
      } else if (isFront) {
        result.add(span);
      }
      accumulated = end;
    }

    return result;
  }
}

// ──────────── NopOp（空操作）────────────

class NopOp extends BlockOp {
  const NopOp();

  @override
  BlockOp apply(BlockTree tree) => this;

  @override
  BlockOp get reverse => this;

  @override
  String get opType => 'nop';
}
