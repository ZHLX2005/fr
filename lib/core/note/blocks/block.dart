import 'block_id.dart';
import 'block_type.dart';
import 'rich_text.dart';

/// 块（Block）—— 文档树的原子单位
class Block {
  final String id;
  final BlockType type;
  final RichText content;
  final List<Block> children;
  final BlockData data;
  final Map<String, dynamic> properties;
  final DateTime createdAt;
  final DateTime updatedAt;

  Block({
    required this.id,
    required this.type,
    RichText? content,
    List<Block>? children,
    BlockData? data,
    Map<String, dynamic>? properties,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : content = content ?? RichText.empty(),
        children = children ?? const [],
        data = data ?? BlockData.empty(),
        properties = properties ?? const {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get canHaveChildren => type.canHaveChildren;
  bool get isContainerOnly => type.containerOnly;

  Block copyWith({
    BlockType? type,
    RichText? content,
    List<Block>? children,
    BlockData? data,
    Map<String, dynamic>? properties,
    DateTime? updatedAt,
  }) =>
      Block(
        id: id,
        type: type ?? this.type,
        content: content ?? this.content,
        children: children ?? this.children,
        data: data ?? this.data,
        properties: properties ?? this.properties,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.tag,
        'content': content.toJson(),
        'children': children.map((c) => c.toJson()).toList(),
        'data': data.toMap(),
        'properties': Map.of(properties),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Block.fromJson(Map<String, dynamic> json) => Block(
        id: json['id'] as String? ?? BlockId.generate(),
        type: BlockType.fromTag(json['type'] as String? ?? 'paragraph'),
        content: json['content'] != null
            ? RichText.fromJson(_castMap(json['content']!))
            : RichText.empty(),
        children: (json['children'] as List<dynamic>?)
                ?.map((c) => Block.fromJson(_castMap(c)))
                .toList() ??
            [],
        data: BlockData.fromMap(_castMapOrEmpty(json['data'])),
        properties: _castMapOrEmpty(json['properties']),
        createdAt: json['created_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int)
            : null,
        updatedAt: json['updated_at'] != null
            ? DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int)
            : null,
      );

  static Map<String, dynamic> _castMap(dynamic value) =>
      Map<String, dynamic>.from(value as Map);

  static Map<String, dynamic> _castMapOrEmpty(dynamic value) =>
      value != null ? Map<String, dynamic>.from(value as Map) : {};

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Block && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
