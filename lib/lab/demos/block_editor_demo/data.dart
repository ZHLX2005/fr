import '../../../core/note/core/models/block.dart';
import '../../../core/note/core/identity/block_id.dart';
import '../../../core/note/core/type/type.dart';
import '../../../core/note/core/text/rich_text.dart';

/// Phase 1 示例数据：覆盖 6 种常用 BlockType
List<Block> createDemoBlocks() {
  return [
    Block(
      id: BlockId.generate(),
      type: const HeadingType(level: 1),
      content: RichText.text('块编辑器 Demo'),
    ),
    Block(
      id: BlockId.generate(),
      type: const ParagraphType(),
      content: RichText.text('这是一个 paragraph 块。点击选中，右侧下拉切换类型，点击 ✕ 删除。'),
    ),
    Block(
      id: BlockId.generate(),
      type: const TodoType(checked: true),
      content: RichText.text('实现 Block → BlockCard 渲染'),
    ),
    Block(
      id: BlockId.generate(),
      type: const TodoType(),
      content: RichText.text('实现类型切换功能'),
    ),
    Block(
      id: BlockId.generate(),
      type: const TodoType(),
      content: RichText.text('实现撤销/重做'),
    ),
    Block(
      id: BlockId.generate(),
      type: const HeadingType(level: 2),
      content: RichText.text('嵌套内容'),
    ),
    Block(
      id: BlockId.generate(),
      type: const BulletListItemType(),
      content: RichText.text('无序列表项 A'),
    ),
    Block(
      id: BlockId.generate(),
      type: const BulletListItemType(),
      content: RichText.text('无序列表项 B'),
    ),
    Block(
      id: BlockId.generate(),
      type: const OrderedListItemType(number: 1),
      content: RichText.text('第一步'),
    ),
    Block(
      id: BlockId.generate(),
      type: const OrderedListItemType(number: 2),
      content: RichText.text('第二步'),
    ),
    Block(
      id: BlockId.generate(),
      type: const QuoteType(),
      content: RichText.text('这是一段引用块'),
    ),
    Block(
      id: BlockId.generate(),
      type: const CodeType(language: 'javascript'),
      content: RichText.text("console.log('hello block')"),
    ),
    Block(
      id: BlockId.generate(),
      type: const DividerType(),
    ),
    Block(
      id: BlockId.generate(),
      type: const CalloutType(icon: '💡'),
      content: RichText.text('提示：下拉切换块类型试试'),
    ),
  ];
}
