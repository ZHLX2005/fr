import 'block.dart';
import 'block_op.dart';
import 'block_tree.dart';
import 'rich_text.dart';

/// AI 操作指令的验证层
///
/// 在 Apply 前拦截非法操作，防止 AI 产生破坏性修改
class OpValidator {
  final BlockTree tree;

  const OpValidator(this.tree);

  /// 验证一组操作，返回所有错误
  List<ValidationError> validate(List<BlockOp> ops) {
    final errors = <ValidationError>[];
    for (final op in ops) {
      errors.addAll(_validateSingle(op));
    }
    return errors;
  }

  List<ValidationError> _validateSingle(BlockOp op) {
    return switch (op) {
      InsertBlock(:final block, :final parentId, :final afterId) =>
        _validateInsert(block, parentId, afterId),
      DeleteBlock(:final id) => _validateDelete(id),
      UpdateBlock(:final id, :final data) => _validateUpdate(id, data),
      MoveBlock(:final id, :final newParentId) =>
        _validateMove(id, newParentId),
      MergeBlocks(:final sourceId, :final targetId) =>
        _validateMerge(sourceId, targetId),
      SplitBlock(:final id, :final splitOffset) =>
        _validateSplit(id, splitOffset),
      NopOp() => [],
    };
  }

  List<ValidationError> _validateInsert(Block block, String parentId, String? afterId) {
    final errors = <ValidationError>[];
    if (block.id == BlockTree.rootId) {
      errors.add(ValidationError('不能插入根节点'));
    }
    if (tree.exists(block.id)) {
      errors.add(ValidationError('块 ID 冲突: ${block.id}'));
    }
    if (!tree.exists(parentId)) {
      errors.add(ValidationError('父块不存在: $parentId'));
    }
    if (afterId != null && !tree.exists(afterId)) {
      errors.add(ValidationError('after 块不存在: $afterId'));
    }
    if (afterId != null && tree.parentIdOf(afterId) != parentId) {
      errors.add(ValidationError('afterId $afterId 不在父块 $parentId 下'));
    }
    if (block.type.containerOnly && block.content.isNotEmpty) {
      errors.add(ValidationError('${block.type.tag} 不能有文字内容'));
    }
    if (!block.type.canHaveChildren && block.children.isNotEmpty) {
      errors.add(ValidationError('${block.type.tag} 不能有子块'));
    }
    if (!block.data.validate(block.type)) {
      errors.add(ValidationError('data 字段与类型 ${block.type.tag} 不匹配'));
    }
    return errors;
  }

  List<ValidationError> _validateDelete(String id) {
    final errors = <ValidationError>[];
    if (id == BlockTree.rootId) {
      errors.add(ValidationError('不能删除根节点'));
    }
    if (!tree.exists(id)) {
      errors.add(ValidationError('块不存在: $id'));
    }
    return errors;
  }

  List<ValidationError> _validateUpdate(String id, BlockData? data) {
    final errors = <ValidationError>[];
    if (!tree.exists(id)) {
      errors.add(ValidationError('块不存在: $id'));
    }
    if (data != null) {
      final block = tree.get(id);
      if (block != null && !data.validate(block.type)) {
        errors.add(ValidationError('data 字段与类型 ${block.type.tag} 不匹配'));
      }
    }
    return errors;
  }

  List<ValidationError> _validateMove(String id, String newParentId) {
    final errors = <ValidationError>[];
    if (!tree.exists(id)) {
      errors.add(ValidationError('块不存在: $id'));
    }
    if (!tree.exists(newParentId)) {
      errors.add(ValidationError('目标父块不存在: $newParentId'));
    }
    if (_wouldCreateCycle(id, newParentId)) {
      errors.add(ValidationError('移动会产生循环引用'));
    }
    return errors;
  }

  List<ValidationError> _validateMerge(String sourceId, String targetId) {
    final errors = <ValidationError>[];
    if (!tree.exists(sourceId)) {
      errors.add(ValidationError('源块不存在: $sourceId'));
    }
    if (!tree.exists(targetId)) {
      errors.add(ValidationError('目标块不存在: $targetId'));
    }
    if (sourceId == targetId) {
      errors.add(ValidationError('不能合并同一个块'));
    }
    return errors;
  }

  List<ValidationError> _validateSplit(String id, int splitOffset) {
    final errors = <ValidationError>[];
    final block = tree.get(id);
    if (block == null) {
      errors.add(ValidationError('块不存在: $id'));
    } else {
      final text = block.content.toPlainText();
      if (splitOffset <= 0 || splitOffset >= text.length) {
        errors.add(ValidationError('分割偏移量越界: $splitOffset (长度: ${text.length})'));
      }
    }
    return errors;
  }

  bool _wouldCreateCycle(String id, String newParentId) {
    var current = newParentId;
    while (current != BlockTree.rootId) {
      if (current == id) return true;
      current = tree.parentIdOf(current) ?? BlockTree.rootId;
    }
    return false;
  }
}

/// 验证错误
class ValidationError {
  final String message;

  const ValidationError(this.message);

  @override
  String toString() => 'ValidationError: $message';
}
