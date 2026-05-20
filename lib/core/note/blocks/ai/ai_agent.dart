import 'dart:convert';
import '../block.dart';
import '../block_id.dart';
import '../block_op.dart';
import '../block_tree.dart';
import '../block_type.dart';
import '../op_validator.dart';
import '../rich_text.dart';
import '../op_history.dart';
import 'context_builder.dart';

/// AI 操作的结果
class AiActionResult {
  final List<BlockOp> appliedOps;
  final List<ValidationError> errors;
  final String summary;

  const AiActionResult({
    this.appliedOps = const [],
    this.errors = const [],
    this.summary = '',
  });

  bool get success => errors.isEmpty;
  bool get hasChanges => appliedOps.isNotEmpty;
}

/// AI Agent —— 将自然语言指令转为 BlockOp 并执行
///
/// 目前提供 "模拟 AI" 模式（解析简单指令生成对应操作）
/// 和 "Tool Use" 模式（处理外部 AI 返回的工具调用结果）
class AiAgent {
  final BlockTree tree;
  final OperationHistory history;
  final OpValidator validator;
  final ContextBuilder contextBuilder;

  AiAgent({
    required this.tree,
    required this.history,
    OpValidator? validator,
    ContextBuilder? contextBuilder,
  })  : validator = validator ?? OpValidator(tree),
        contextBuilder = contextBuilder ?? ContextBuilder(tree);

  /// 处理 AI 返回的工具调用结果
  /// [toolCalls] 是 LLM 返回的工具调用列表
  AiActionResult processToolCalls(List<Map<String, dynamic>> toolCalls, {String? selectedId}) {
    final ops = <BlockOp>[];

    for (final call in toolCalls) {
      final name = call['name'] as String? ?? '';
      final args = call['arguments'] as Map<String, dynamic>? ?? {};
      final op = _toolCallToOp(name, args);
      if (op != null) ops.add(op);
    }

    if (ops.isEmpty) {
      return const AiActionResult(summary: '未生成有效操作');
    }

    // 验证
    final errors = validator.validate(ops);
    if (errors.isNotEmpty) {
      return AiActionResult(
        errors: errors,
        summary: '验证失败：${errors.map((e) => e.toString()).join("; ")}',
      );
    }

    // 执行
    history.apply(ops);
    return AiActionResult(
      appliedOps: ops,
      summary: _buildSummary(ops),
    );
  }

  /// 将单条工具调用转为 BlockOp
  BlockOp? _toolCallToOp(String name, Map<String, dynamic> args) {
    try {
      return switch (name) {
        'insert_block' => _buildInsertOp(args),
        'update_block' => _buildUpdateOp(args),
        'delete_block' => _buildDeleteOp(args),
        'move_block' => _buildMoveOp(args),
        'merge_blocks' => _buildMergeOp(args),
        'split_block' => _buildSplitOp(args),
        _ => null, // read/search 等只读操作不需要生成 op
      };
    } catch (_) {
      return null;
    }
  }

  InsertBlock _buildInsertOp(Map<String, dynamic> args) {
    final afterId = args['after_id'] as String? ?? '';
    final parentId = args['parent_id'] as String? ?? BlockTree.rootId;
    final type = BlockType.fromTag(args['type'] as String? ?? 'paragraph');
    final content = args['content'] as String? ?? '';

    BlockData? data;
    if (args['data'] is String && (args['data'] as String).isNotEmpty) {
      data = BlockData.fromMap(jsonDecode(args['data'] as String) as Map<String, dynamic>);
    }

    final block = Block(
      id: BlockId.generate(),
      type: type,
      content: RichText.text(content),
      data: data ?? BlockData.empty(),
    );

    return InsertBlock(block,
        parentId: tree.exists(parentId) ? parentId : BlockTree.rootId,
        afterId: tree.exists(afterId) ? afterId : null);
  }

  UpdateBlock _buildUpdateOp(Map<String, dynamic> args) {
    final id = args['id'] as String? ?? '';
    final content = args['content'] as String?;
    final typeStr = args['type'] as String?;
    BlockData? data;
    if (args['data'] is String && (args['data'] as String).isNotEmpty) {
      data = BlockData.fromMap(jsonDecode(args['data'] as String) as Map<String, dynamic>);
    }
    return UpdateBlock(
      id,
      content: content != null ? RichText.text(content) : null,
      type: typeStr != null ? BlockType.fromTag(typeStr) : null,
      data: data,
    );
  }

  DeleteBlock _buildDeleteOp(Map<String, dynamic> args) {
    return DeleteBlock(args['id'] as String? ?? '');
  }

  MoveBlock _buildMoveOp(Map<String, dynamic> args) {
    final id = args['id'] as String? ?? '';
    final parentId = args['parent_id'] as String? ?? BlockTree.rootId;
    final afterId = args['after_id'] as String?;
    return MoveBlock(id,
        newParentId: tree.exists(parentId) ? parentId : BlockTree.rootId,
        afterId: afterId != null && tree.exists(afterId) ? afterId : null);
  }

  MergeBlocks _buildMergeOp(Map<String, dynamic> args) {
    return MergeBlocks(
      args['source_id'] as String? ?? '',
      args['target_id'] as String? ?? '',
    );
  }

  SplitBlock _buildSplitOp(Map<String, dynamic> args) {
    return SplitBlock(
      args['id'] as String? ?? '',
      args['split_offset'] as int? ?? 0,
    );
  }

  /// 模拟 AI：解析自然语言指令，生成对应的操作
  AiActionResult simulateCommand(String command, {String? selectedId}) {
    final lower = command.trim().toLowerCase();

    if (lower.startsWith('插入标题') || lower.startsWith('add heading')) {
      final text = _extractText(command);
      final level = lower.contains('h1') || lower.contains('一级') ? 1 :
                    lower.contains('h2') || lower.contains('二级') ? 2 :
                    lower.contains('h3') || lower.contains('三级') ? 3 : 2;
      return _insertAfter(selectedId,
        Block(id: BlockId.generate(), type: BlockType.heading,
          content: RichText.text(text),
          data: BlockData.fromMap({'level': level})),
      );
    }

    if (lower.startsWith('插入待办') || lower.startsWith('add todo')) {
      final text = _extractText(command);
      return _insertAfter(selectedId,
        Block(id: BlockId.generate(), type: BlockType.todo,
          content: RichText.text(text),
          data: BlockData.fromMap({'checked': false})),
      );
    }

    if (lower.startsWith('插入') || lower.startsWith('add')) {
      final text = _extractText(command);
      return _insertAfter(selectedId,
        Block(id: BlockId.generate(), type: BlockType.paragraph,
          content: RichText.text(text)),
      );
    }

    if (lower.startsWith('删除') || lower.startsWith('delete') || lower.startsWith('remove')) {
      if (selectedId != null) {
        final op = DeleteBlock(selectedId);
        final errors = validator.validate([op]);
        if (errors.isEmpty) {
          history.apply([op]);
          return AiActionResult(
            appliedOps: [op],
            summary: '已删除块 $selectedId',
          );
        }
        return AiActionResult(errors: errors, summary: '删除失败');
      }
      return const AiActionResult(summary: '未选中任何块');
    }

    if (lower.startsWith('设置标题') || lower.startsWith('heading')) {
      if (selectedId != null) {
        final level = lower.contains('h3') || lower.contains('三级') ? 3 :
                      lower.contains('h1') || lower.contains('一级') ? 1 : 2;
        final op = UpdateBlock(selectedId,
          type: BlockType.heading,
          data: BlockData.fromMap({'level': level}),
        );
        final errors = validator.validate([op]);
        if (errors.isEmpty) {
          history.apply([op]);
          return AiActionResult(appliedOps: [op], summary: '已设置为 H$level');
        }
        return AiActionResult(errors: errors, summary: '设置失败');
      }
      return const AiActionResult(summary: '未选中任何块');
    }

    if (lower.startsWith('总结') || lower.startsWith('summarize')) {
      // 实际应调用 LLM，contextBuilder.build 提供上下文
      final summary = '【AI 摘要】基于上下文的模拟摘要…';
      return _insertAfter(selectedId,
        Block(id: BlockId.generate(), type: BlockType.callout,
          content: RichText.text(summary),
          data: BlockData.fromMap({'icon': '📝'})),
      );
    }

    return const AiActionResult(summary: '无法识别指令。支持的命令：插入、删除、设置标题、总结');
  }

  AiActionResult _insertAfter(String? afterId, Block block) {
    final parentId = afterId != null
        ? (tree.parentIdOf(afterId) ?? BlockTree.rootId)
        : BlockTree.rootId;
    final op = InsertBlock(block, parentId: parentId, afterId: afterId);
    final errors = validator.validate([op]);
    if (errors.isEmpty) {
      history.apply([op]);
      return AiActionResult(appliedOps: [op], summary: '已插入 ${block.type.tag} 块');
    }
    return AiActionResult(errors: errors, summary: '插入失败');
  }

  String _extractText(String command) {
    // 去掉命令前缀，取剩下的文字
    final cleaned = command.replaceFirst(RegExp(r'^(插入标题|插入待办|插入|add heading|add todo|add|delete|删除|remove)\s*', caseSensitive: false), '');
    return cleaned.isNotEmpty ? cleaned : '新内容';
  }

  String _buildSummary(List<BlockOp> ops) {
    int insert = 0, update = 0, delete = 0, move = 0;
    for (final op in ops) {
      switch (op) {
        case InsertBlock(): insert++;
        case UpdateBlock(): update++;
        case DeleteBlock(): delete++;
        case MoveBlock(): move++;
        default: break;
      }
    }
    final parts = <String>[];
    if (insert > 0) parts.add('insert: $insert');
    if (update > 0) parts.add('update: $update');
    if (delete > 0) parts.add('delete: $delete');
    if (move > 0) parts.add('move: $move');
    return '✅ 已完成，共修改 ${ops.length} 个块 [${parts.join(", ")}]';
  }
}
