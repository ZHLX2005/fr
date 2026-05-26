import 'type.dart';

typedef BlockTypeFactory = BlockType Function(Map<String, dynamic>);

/// BlockType 反序列化注册表。构造时接收完整工厂 Map。
class BlockTypeRegistry {
  final Map<String, BlockTypeFactory> _factories;

  BlockTypeRegistry(this._factories);

  BlockType resolve(String tag, [Map<String, dynamic> data = const {}]) {
    final factory = _factories[tag];
    if (factory == null) {
      throw ArgumentError('Unknown block type tag: "$tag".');
    }
    return factory(data);
  }
}

/// 全部 19 种 BlockType 的工厂 Map 构造器。
class BlockTypeRegistrar {
  const BlockTypeRegistrar();

  Map<String, BlockTypeFactory> createFactories() => {
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
}
