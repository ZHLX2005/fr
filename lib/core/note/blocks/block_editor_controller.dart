import 'dart:async';
import 'package:flutter/foundation.dart';
import 'ai/ai_agent.dart';
import 'block.dart';
import 'block_op.dart';
import 'block_tree.dart';
import 'block_type.dart';
import 'op_history.dart';
import 'op_validator.dart';
import 'rich_text.dart';

/// 块编辑器的选择状态
class BlockSelection {
  final String blockId;
  final int cursorOffset;

  const BlockSelection(this.blockId, {this.cursorOffset = 0});
}

/// 编辑器控制器 —— 连接 BlockTree + OperationHistory + UI 的状态管理
class BlockEditorController extends ChangeNotifier {
  final BlockTree tree;
  final OperationHistory history;
  final OpValidator validator;
  late final AiAgent aiAgent;

  BlockSelection? _selection;
  BlockSelection? get selection => _selection;
  String? get selectedBlockId => _selection?.blockId;

  /// AI 输入条可见性
  bool aiBarVisible = false;

  /// 更多面板可见性
  bool morePanelVisible = false;

  StreamSubscription? _treeSub;

  BlockEditorController({
    BlockTree? tree,
  })  : tree = tree ?? BlockTree(),
        history = OperationHistory(tree ?? BlockTree()),
        validator = OpValidator(tree ?? BlockTree()) {
    _init();
    _treeSub = this.tree.changes.listen((_) => notifyListeners());
  }

  void _init() {
    aiAgent = AiAgent(
      tree: tree,
      history: history,
      validator: validator,
    );
  }

  /// 选择块
  void selectBlock(String blockId, {int cursorOffset = 0}) {
    _selection = BlockSelection(blockId, cursorOffset: cursorOffset);
    notifyListeners();
  }

  /// 清除选区
  void clearSelection() {
    _selection = null;
    notifyListeners();
  }

  /// 在当前所选块之后插入新块
  void insertBlockAfter(Block block) {
    if (_selection == null) return;
    final parentId = tree.parentIdOf(_selection!.blockId) ?? BlockTree.rootId;
    final op = InsertBlock(block, parentId: parentId, afterId: _selection!.blockId);
    _applyAndSelect(op, block.id);
  }

  /// 更新当前块的文字内容
  void updateContent(String blockId, RichText content) {
    final op = UpdateBlock(blockId, content: content);
    history.applySingle(op);
  }

  /// 切换块类型
  void toggleType(BlockType newType) {
    if (_selection == null) return;
    final op = UpdateBlock(_selection!.blockId, type: newType);
    history.applySingle(op);
  }

  /// 切换标题级别
  void setHeader(int level) {
    if (level < 0 || level > 6) return;
    if (_selection == null) return;
    if (level == 0) {
      // 切换回正文
      toggleType(BlockType.paragraph);
    } else {
      final op = UpdateBlock(_selection!.blockId,
          type: BlockType.heading, data: BlockData.fromMap({'level': level}));
      history.applySingle(op);
    }
  }

  /// 切换粗体
  void toggleBold() {
    // 内联格式修改：需要选中文字后执行
    // 当前简化实现：通知 UI 打开格式菜单
  }

  /// 删除当前块
  void deleteBlock() {
    if (_selection == null) return;
    final id = _selection!.blockId;
    final parentId = tree.parentIdOf(id);
    if (parentId == null || id == BlockTree.rootId) return;

    history.apply([DeleteBlock(id)]);

    // 选中相邻块
    final siblings = tree.childIdsOf(parentId);
    if (siblings.isNotEmpty) {
      final idx = siblings.indexOf(id);
      if (idx < 0 || idx >= siblings.length) {
        selectBlock(siblings.isNotEmpty ? siblings.last : parentId);
      } else {
        selectBlock(idx > 0 ? siblings[idx - 1] : siblings[0]);
      }
    } else {
      selectBlock(parentId);
    }
  }

  /// 移动块
  void moveBlock(String id, {required String newParentId, String? afterId}) {
    final errors = validator.validate([MoveBlock(id, newParentId: newParentId, afterId: afterId)]);
    if (errors.isEmpty) {
      history.apply([MoveBlock(id, newParentId: newParentId, afterId: afterId)]);
    }
  }

  /// 撤销
  void undo() => history.undo();
  void redo() => history.redo();
  bool get canUndo => history.canUndo;
  bool get canRedo => history.canRedo;

  /// AI 操作：验证并应用一组操作
  List<ValidationError> applyAiOps(List<BlockOp> ops) {
    final errors = validator.validate(ops);
    if (errors.isEmpty) {
      history.apply(ops);
    }
    return errors;
  }

  void _applyAndSelect(BlockOp op, String newBlockId) {
    history.apply([op]);
    selectBlock(newBlockId);
  }

  @override
  void dispose() {
    _treeSub?.cancel();
    super.dispose();
  }
}
