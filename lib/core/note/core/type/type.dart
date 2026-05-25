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

  /// 工厂注册表。tag → 反序列化工厂，与 [part] 指令一一对应。
  /// 新增类型时在此加一行即可（同时加 [part] 指令）。
  static final Map<String, BlockTypeFactory> _registry = {
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

  /// 从 [tag] 及可选 [data] 反查具体子类实例。
  static BlockType fromTag(String tag, [Map<String, dynamic> data = const {}]) {
    final factory = _registry[tag];
    if (factory == null) {
      throw ArgumentError('Unknown block type tag: "$tag".');
    }
    return factory(data);
  }
}

/// 反序列化工厂类型。接收 data map 返回具体 BlockType 实例。
typedef BlockTypeFactory = BlockType Function(Map<String, dynamic> data);
