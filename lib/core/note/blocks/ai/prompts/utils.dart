import '../../block.dart';
import '../../block_id.dart';
import '../../block_type.dart';
import '../../rich_text.dart';
import '../note_ai_service.dart';

/// 将一行 Markdown 文本解析为 Block
Block parseMdLine(String line) {
  final trimmed = line.trimLeft();

  // 标题 # ~ ######
  final headingMatch = RegExp(r'^(#{1,6})\s+(.*)$').firstMatch(trimmed);
  if (headingMatch != null) {
    return Block(
      id: BlockId.generate(),
      type: BlockType.heading,
      content: RichText.text(headingMatch.group(2) ?? ''),
      data: BlockData.fromMap({'level': headingMatch.group(1)!.length}),
    );
  }

  // 引用 >
  if (trimmed.startsWith('> ')) {
    return Block(
      id: BlockId.generate(),
      type: BlockType.quote,
      content: RichText.text(trimmed.substring(2)),
    );
  }

  // 无序列表 -
  if (trimmed.startsWith('- ') || trimmed.startsWith('* ')) {
    return Block(
      id: BlockId.generate(),
      type: BlockType.bulletListItem,
      content: RichText.text(trimmed.substring(2)),
    );
  }

  // 有序列表 1.
  final olMatch = RegExp(r'^(\d+)\.\s+(.*)$').firstMatch(trimmed);
  if (olMatch != null) {
    return Block(
      id: BlockId.generate(),
      type: BlockType.orderedListItem,
      content: RichText.text(olMatch.group(2) ?? ''),
      data: BlockData.fromMap({'number': int.tryParse(olMatch.group(1) ?? '') ?? 1}),
    );
  }

  // 待办 [ ] / [x]
  final todoMatch = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(trimmed);
  if (todoMatch != null) {
    final checked = todoMatch.group(1)!.toLowerCase() == 'x';
    return Block(
      id: BlockId.generate(),
      type: BlockType.todo,
      content: RichText.text(todoMatch.group(2) ?? ''),
      data: BlockData.fromMap({'checked': checked}),
    );
  }

  // 默认：段落
  return Block(
    id: BlockId.generate(),
    type: BlockType.paragraph,
    content: RichText.text(line),
  );
}

/// 判断用户消息是否为操作型请求（需要 AI 调工具）
bool isActionRequest(String text) {
  final lower = text.trim().toLowerCase();
  const actionWords = [
    '写', '创建', '插入', '添加', '修改', '删除', '更新', '移动', '合并',
    '新建', '生成', '翻译', '总结', '整理', '重构', '重命名',
    '写一', '写个', '写篇', '加入', '改为', '改成', '设为',
    'write', 'create', 'insert', 'add', 'update', 'delete', 'remove',
    'new page', 'generate', 'summarize', 'translate',
  ];
  // 排除明确说不修改的
  if (lower.contains('先不修改') || lower.contains('不要修改') || lower.contains('只读')) {
    return false;
  }
  return actionWords.any((w) => lower.contains(w));
}

/// 检查已执行的工具调用是否全部为只读
bool onlyReadTools(List<ToolCallInfo> calls) {
  if (calls.isEmpty) return false;
  const readTools = {'read_block', 'read_subtree', 'search_blocks'};
  return calls.every((c) => readTools.contains(c.name));
}
