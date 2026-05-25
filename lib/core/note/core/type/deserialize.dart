import 'type.dart';

/// 从 [tag] 及可选 [data] 反查具体 BlockType 子类实例。
BlockType deserializeBlockType(String tag, [Map<String, dynamic> data = const {}]) {
  return switch (tag) {
    'page' => const PageType(),
    'paragraph' => const ParagraphType(),
    'heading' => HeadingType.fromData(data),
    'todo' => TodoType.fromData(data),
    'toggle' => const ToggleType(),
    'bullet_list_item' => const BulletListItemType(),
    'ordered_list_item' => OrderedListItemType.fromData(data),
    'quote' => const QuoteType(),
    'code' => CodeType.fromData(data),
    'divider' => const DividerType(),
    'callout' => CalloutType.fromData(data),
    'image' => ImageType.fromData(data),
    'embed_card' => EmbedCardType.fromData(data),
    'bookmark' => BookmarkType.fromData(data),
    'equation' => EquationType.fromData(data),
    'database' => const DatabaseType(),
    'column_list' => const ColumnListType(),
    'column' => ColumnType.fromData(data),
    'synced_block' => SyncedBlockType.fromData(data),
    _ => throw ArgumentError('Unknown block type tag: "$tag".'),
  };
}
