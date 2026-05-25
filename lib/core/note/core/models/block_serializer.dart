import '../type/type.dart';

/// BlockType 反序列化工厂注册表。tag → 构造工厂。
final Map<String, BlockType Function(Map<String, dynamic>)> _typeRegistry = {
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

/// 从 [tag] 及可选 [data] 反查具体 BlockType 子类实例。
BlockType deserializeBlockType(String tag, [Map<String, dynamic> data = const {}]) {
  final factory = _typeRegistry[tag];
  if (factory == null) {
    throw ArgumentError('Unknown block type tag: "$tag".');
  }
  return factory(data);
}
