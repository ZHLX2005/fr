import '../../../core/note/core/models/block.dart';
import '../../../core/note/core/models/block_data.dart';
import '../../../core/note/core/identity/block_id.dart';
import '../../../core/note/core/models/block_type.dart';
import '../../../core/note/core/text/rich_text.dart';

/// Phase 1 示例数据：覆盖 6 种常用 BlockType
List<Block> createDemoBlocks() {
  return [
    Block(
      id: BlockId.generate(),
      type: BlockType.heading,
      content: RichText.text('块编辑器 Demo'),
      data: BlockData.fromMap({'level': 1}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.paragraph,
      content: RichText.text('这是一个 paragraph 块。点击选中，右侧下拉切换类型，点击 ✕ 删除。'),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.todo,
      content: RichText.text('实现 Block → BlockCard 渲染'),
      data: BlockData.fromMap({'checked': true}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.todo,
      content: RichText.text('实现类型切换功能'),
      data: BlockData.fromMap({'checked': false}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.todo,
      content: RichText.text('实现撤销/重做'),
      data: BlockData.fromMap({'checked': false}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.heading,
      content: RichText.text('嵌套内容'),
      data: BlockData.fromMap({'level': 2}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.bulletListItem,
      content: RichText.text('无序列表项 A'),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.bulletListItem,
      content: RichText.text('无序列表项 B'),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.orderedListItem,
      content: RichText.text('第一步'),
      data: BlockData.fromMap({'number': 1}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.orderedListItem,
      content: RichText.text('第二步'),
      data: BlockData.fromMap({'number': 2}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.quote,
      content: RichText.text('这是一段引用块'),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.code,
      content: RichText.text("console.log('hello block')"),
      data: BlockData.fromMap({'language': 'javascript'}),
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.divider,
    ),
    Block(
      id: BlockId.generate(),
      type: BlockType.callout,
      content: RichText.text('提示：下拉切换块类型试试'),
      data: BlockData.fromMap({'icon': '💡'}),
    ),
  ];
}
