part 'page.dart';
part 'paragraph.dart';
part 'heading.dart';
part 'todo.dart';
part 'toggle.dart';
part 'bullet_list_item.dart';
part 'ordered_list_item.dart';
part 'quote.dart';
part 'code.dart';
part 'divider.dart';
part 'callout.dart';
part 'image.dart';
part 'embed_card.dart';
part 'bookmark.dart';
part 'equation.dart';
part 'database.dart';
part 'column_list.dart';
part 'column.dart';
part 'synced_block.dart';

/// Block 类型 sealed 基类。
///
/// 每个 Block 的具体类型继承此类，携带该类型专属数据。
sealed class BlockType {
  const BlockType({
    required this.tag,
    this.containerOnly = false,
    this.canHaveChildren = false,
  });

  /// 序列化/反序列化用的字符串标签。
  final String tag;

  /// 此类型是否只能作为容器（不可有文字内容）。
  final bool containerOnly;

  /// 此类型是否可以包含子块。
  final bool canHaveChildren;

  /// 序列化类型专属数据（不含 tag 本身）。
  Map<String, dynamic> toJson();
}

/// 运行时 tag → 构造工厂映射，与 [part] 指令一一对应。
/// 新增类型时在此相邻加两行：[part] + [typeRegistry] 条目。
typedef BlockTypeFactory = BlockType Function(Map<String, dynamic>);
final Map<String, BlockTypeFactory> typeRegistry = {
  'page': (_) => const PageType(),
  'paragraph': (_) => const ParagraphType(),
  'heading': HeadingType.fromData,
  'todo': TodoType.fromData,
  'toggle': (_) => const ToggleType(),
  'bullet_list_item': (_) => const BulletListItemType(),
  'ordered_list_item': OrderedListItemType.fromData,
  'quote': (_) => const QuoteType(),
  'code': CodeType.fromData,
  'divider': (_) => const DividerType(),
  'callout': CalloutType.fromData,
  'image': ImageType.fromData,
  'embed_card': EmbedCardType.fromData,
  'bookmark': BookmarkType.fromData,
  'equation': EquationType.fromData,
  'database': (_) => const DatabaseType(),
  'column_list': (_) => const ColumnListType(),
  'column': ColumnType.fromData,
  'synced_block': SyncedBlockType.fromData,
};
