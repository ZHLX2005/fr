import '../widget.dart';
import '../strategies/strategies.dart';

/// 注册所有 block widget 策略并返回工厂实例。
BlockWidgetFactory createBlockWidgetFactory() {
  final strategies = <String, BlockWidgetStrategy>{
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
  };
  return BlockWidgetFactory(strategies);
}
