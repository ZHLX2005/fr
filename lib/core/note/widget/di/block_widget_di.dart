import '../widget.dart';

/// BlockWidgetFactory 构建器。
class BlockWidgetBuilder {
  const BlockWidgetBuilder();

  BlockWidgetFactory build() {
    return BlockWidgetFactory({
      'page': PageWidgetStrategy(),
      'paragraph': ParagraphWidgetStrategy(),
      'heading': HeadingWidgetStrategy(),
      'todo': TodoWidgetStrategy(),
      'bullet_list_item': BulletListItemWidgetStrategy(),
      'ordered_list_item': OrderedListItemWidgetStrategy(),
      'quote': QuoteWidgetStrategy(),
      'code': CodeWidgetStrategy(),
      'divider': DividerWidgetStrategy(),
      'callout': CalloutWidgetStrategy(),
      'image': ImageWidgetStrategy(),
    });
  }
}
