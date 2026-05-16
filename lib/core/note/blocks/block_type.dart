/// 块类型枚举
///
/// 每种类型对应不同的渲染方式和 data schema
enum BlockType {
  /// 文档页面（容器，可含任意子块）
  page('page', containerOnly: true, canHaveChildren: true),

  /// 普通段落
  paragraph('paragraph'),

  /// 标题（data: {level: 1-6}）
  heading('heading'),

  /// 待办事项（data: {checked: bool}）
  todo('todo'),

  /// 折叠块（容器，可含子块）
  toggle('toggle', canHaveChildren: true),

  /// 无序列表项（可含子列表）
  bulletListItem('bullet_list_item', canHaveChildren: true),

  /// 有序列表项（data: {number: int}，可含子列表）
  orderedListItem('ordered_list_item', canHaveChildren: true),

  /// 引用块
  quote('quote'),

  /// 代码块（data: {language: string}）
  code('code'),

  /// 分割线
  divider('divider', containerOnly: true),

  /// 提示框（data: {icon: string}）
  callout('callout'),

  /// 图片（data: {src, caption, width, height}）
  image('image'),

  /// 嵌入卡片（data: {title, subtitle, icon, sourceBlockId}）
  embedCard('embed_card'),

  /// 书签链接预览（data: {url, title, description, favicon}）
  bookmark('bookmark'),

  /// 数学公式（data: {latex: string}）
  equation('equation'),

  /// 数据库（容器，子 Page 作为行）
  database('database', canHaveChildren: true),

  /// 多栏布局（容器，仅含 column 子块）
  columnList('column_list', canHaveChildren: true),

  /// 单栏（data: {ratio: double}，可含任意子块）
  column('column', canHaveChildren: true),

  /// 同步块（data: {refBlockId: string}，引用源块内容）
  syncedBlock('synced_block');

  const BlockType(this.tag, {this.containerOnly = false, this.canHaveChildren = false});

  /// 序列化标签
  final String tag;

  /// 此类型是否只能作为容器（不可有文字内容）
  final bool containerOnly;

  /// 此类型是否可以包含子块
  final bool canHaveChildren;

  static BlockType fromTag(String tag) =>
      BlockType.values.firstWhere((t) => t.tag == tag, orElse: () => paragraph);
}

/// 内联格式（RichText 中每个 Span 的格式）
sealed class InlineFormat {
  const InlineFormat();

  Map<String, dynamic> toJson();

  static InlineFormat fromJson(Map<String, dynamic> json) {
    return switch (json['type'] as String? ?? '') {
      'bold' => const BoldFormat(),
      'italic' => const ItalicFormat(),
      'inline_code' => const InlineCodeFormat(),
      'strikethrough' => const StrikethroughFormat(),
      'link' => LinkFormat(json['url'] as String? ?? ''),
      'mention' => MentionFormat(json['block_id'] as String? ?? ''),
      'color' => ColorFormat(json['color'] as String? ?? ''),
      _ => const BoldFormat(),
    };
  }
}

class BoldFormat extends InlineFormat {
  const BoldFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'bold'};
}

class ItalicFormat extends InlineFormat {
  const ItalicFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'italic'};
}

class InlineCodeFormat extends InlineFormat {
  const InlineCodeFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'inline_code'};
}

class StrikethroughFormat extends InlineFormat {
  const StrikethroughFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'strikethrough'};
}

class LinkFormat extends InlineFormat {
  final String url;
  const LinkFormat(this.url);
  @override
  Map<String, dynamic> toJson() => {'type': 'link', 'url': url};
}

class MentionFormat extends InlineFormat {
  final String blockId;
  const MentionFormat(this.blockId);
  @override
  Map<String, dynamic> toJson() => {'type': 'mention', 'block_id': blockId};
}

class ColorFormat extends InlineFormat {
  final String color;
  const ColorFormat(this.color);
  @override
  Map<String, dynamic> toJson() => {'type': 'color', 'color': color};
}
