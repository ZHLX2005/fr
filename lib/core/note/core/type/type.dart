import 'type_conversion_rule.dart';

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

  /// 按下 Enter 时新插⼊块的类型。null 表示不创建新块。
  BlockType? get onEnterType => const ParagraphType();

  /// 此类型是否支持块内多行（如代码块）。
  bool get multiline => false;

  /// 选中态时是否支持快捷删除（长按菜单等）。
  /// 文本块通过 TextField 的 Backspace 删除，不需要。
  /// 容器块没有 TextField，需要额外操作入口。
  /// 默认跟随 [containerOnly]；ImageType 等非 containerOnly 但无 TextField 的类型需单独覆写。
  bool get showQuickDelete => containerOnly;
}
