import '../type.dart';

/// 注册所有 BlockType 的反序列化工厂。
/// 在 main() 中尽早调用，确保反序列化前注册完毕。
void registerBlockTypes() {
  BlockType.register('page', (_) => const PageType());
  BlockType.register('paragraph', (_) => const ParagraphType());
  BlockType.register('heading', HeadingType.fromData);
  BlockType.register('todo', TodoType.fromData);
  BlockType.register('toggle', (_) => const ToggleType());
  BlockType.register('bullet_list_item', (_) => const BulletListItemType());
  BlockType.register('ordered_list_item', OrderedListItemType.fromData);
  BlockType.register('quote', (_) => const QuoteType());
  BlockType.register('code', CodeType.fromData);
  BlockType.register('divider', (_) => const DividerType());
  BlockType.register('callout', CalloutType.fromData);
  BlockType.register('image', ImageType.fromData);
  BlockType.register('embed_card', EmbedCardType.fromData);
  BlockType.register('bookmark', BookmarkType.fromData);
  BlockType.register('equation', EquationType.fromData);
  BlockType.register('database', (_) => const DatabaseType());
  BlockType.register('column_list', (_) => const ColumnListType());
  BlockType.register('column', ColumnType.fromData);
  BlockType.register('synced_block', SyncedBlockType.fromData);
}
