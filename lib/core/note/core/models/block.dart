import '../type/type.dart';
import '../type/deserialize.dart';
import '../identity/identity.dart';
import '../text/rich_text.dart';

/// 文档树的基本单元。
///
/// [id] 全局唯一，[type] 决定渲染方式和 data schema，
/// [content] 为富文本，[children] 仅在序列化时携带（运行时的父子关系由 BlockTree 的双索引管理）。
///
/// 同一性由 [id] 决定（== / hashCode），不可变风格通过 [copyWith] 更新。
class Block {
  final String id;
  final BlockType type;
  final RichText content;
  final List<Block> children;
  final Map<String, dynamic> properties;
  final DateTime createdAt;
  final DateTime updatedAt;

  Block({
    required this.id,
    required this.type,
    RichText? content,
    List<Block>? children,
    Map<String, dynamic>? properties,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : content = content ?? RichText.empty(),
        children = children ?? const [],
        properties = properties ?? const {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  bool get canHaveChildren => type.canHaveChildren;
  bool get isContainerOnly => type.containerOnly;

  Block copyWith({
    BlockType? type,
    RichText? content,
    List<Block>? children,
    Map<String, dynamic>? properties,
    DateTime? updatedAt,
  }) =>
      Block(
        id: id,
        type: type ?? this.type,
        content: content ?? this.content,
        children: children ?? this.children,
        properties: properties ?? this.properties,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.tag,
        'content': content.toJson(),
        'children': children.map((c) => c.toJson()).toList(),
        'data': type.toJson(),
        'properties': Map.of(properties),
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
      };

  factory Block.fromJson(Map<String, dynamic> json) => Block(
        id: json['id'] as String? ?? BlockIdentityFactory.generateId(),
        type: deserializeBlockType(
            json['type'] as String? ?? 'paragraph',
            _castMapOrEmpty(json['data']),
          ),
        content: json['content'] != null
            ? RichText.fromJson(_castMap(json['content']!))
            : RichText.empty(),
        children: (json['children'] as List<dynamic>?)
                ?.map((c) => Block.fromJson(_castMap(c)))
                .toList() ??
            [],
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
