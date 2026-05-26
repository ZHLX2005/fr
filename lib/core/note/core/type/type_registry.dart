import 'type.dart';

typedef BlockTypeFactory = BlockType Function(Map<String, dynamic>);

/// BlockType 反序列化注册表。按 tag 查找对应工厂。
class BlockTypeRegistry {
  final Map<String, BlockTypeFactory> _factories = {};

  void register(String tag, BlockTypeFactory factory) {
    _factories[tag] = factory;
  }

  BlockType resolve(String tag, [Map<String, dynamic> data = const {}]) {
    final factory = _factories[tag];
    if (factory == null) {
      throw ArgumentError('Unknown block type tag: "$tag".');
    }
    return factory(data);
  }
}

/// 注册全部 19 种 BlockType。与 [type.dart] 的 [part] 指令一一对应。
class BlockTypeRegistrar {
  const BlockTypeRegistrar();

  void registerAll(BlockTypeRegistry registry) {
    registry.register('page', (_) => const PageType());
    registry.register('paragraph', (_) => const ParagraphType());
    registry.register('heading', HeadingType.fromData);
    registry.register('todo', TodoType.fromData);
    registry.register('toggle', (_) => const ToggleType());
    registry.register('bullet_list_item', (_) => const BulletListItemType());
    registry.register('ordered_list_item', OrderedListItemType.fromData);
    registry.register('quote', (_) => const QuoteType());
    registry.register('code', CodeType.fromData);
    registry.register('divider', (_) => const DividerType());
    registry.register('callout', CalloutType.fromData);
    registry.register('image', ImageType.fromData);
    registry.register('embed_card', EmbedCardType.fromData);
    registry.register('bookmark', BookmarkType.fromData);
    registry.register('equation', EquationType.fromData);
    registry.register('database', (_) => const DatabaseType());
    registry.register('column_list', (_) => const ColumnListType());
    registry.register('column', ColumnType.fromData);
    registry.register('synced_block', SyncedBlockType.fromData);
  }
}
