/// 块类型枚举。
///
/// 每个类型决定 Block 的渲染方式、能否有文字（[containerOnly]）、
/// 能否有子块（[canHaveChildren]）、以及 [BlockData] 的 schema。
enum BlockType {
  /// 文档页面。容器，不可有文字，可含任意子块。
  page('page', containerOnly: true, canHaveChildren: true),

  /// 普通段落。
  paragraph('paragraph'),

  /// 标题。data: { level: 1-6 }
  heading('heading'),

  /// 待办事项。data: { checked: bool }
  todo('todo'),

  /// 折叠块。可含子块。
  toggle('toggle', canHaveChildren: true),

  /// 无序列表项。可含子列表。
  bulletListItem('bullet_list_item', canHaveChildren: true),

  /// 有序列表项。data: { number: int }，可含子列表。
  orderedListItem('ordered_list_item', canHaveChildren: true),

  /// 引用块。
  quote('quote'),

  /// 代码块。data: { language: string }
  code('code'),

  /// 分割线。容器，不可有文字。
  divider('divider', containerOnly: true),

  /// 提示框。data: { icon: string }
  callout('callout'),

  /// 图片。data: { src, caption, width, height }
  image('image'),

  /// 嵌入卡片。data: { title, subtitle, icon, sourceBlockId }
  embedCard('embed_card'),

  /// 书签链接预览。data: { url, title, description, favicon }
  bookmark('bookmark'),

  /// 数学公式。data: { latex: string }
  equation('equation'),

  /// 数据库视图。容器，子 Page 作为行。
  database('database', canHaveChildren: true),

  /// 多栏布局。容器，仅含 column 子块。
  columnList('column_list', canHaveChildren: true),

  /// 单栏。data: { ratio: double }，可含任意子块。
  column('column', canHaveChildren: true),

  /// 同步块。引用源块内容。data: { refBlockId: string }
  syncedBlock('synced_block');

  const BlockType(
    this.tag, {
    this.containerOnly = false,
    this.canHaveChildren = false,
  });

  /// 序列化/反序列化用的字符串标签。
  final String tag;

  /// 此类型是否只能作为容器（不可有文字内容）。
  final bool containerOnly;

  /// 此类型是否可以包含子块。
  final bool canHaveChildren;

  /// 从标签字符串反查枚举值。未知标签默认返回段落。
  static BlockType fromTag(String tag) =>
      BlockType.values.firstWhere((t) => t.tag == tag, orElse: () => paragraph);
}
