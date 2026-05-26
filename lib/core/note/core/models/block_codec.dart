import '../type/type_registry.dart';
import '../identity/identity.dart';
import '../text/rich_text.dart';
import 'block.dart';

/// Block ↔ JSON 互转编解码器。
class BlockCodec {
  final BlockTypeRegistry _typeRegistry;
  final BlockIdentityFactory _idFactory;

  BlockCodec(this._typeRegistry, {BlockIdentityFactory? idFactory})
    : _idFactory = idFactory ?? const BlockIdentityFactory();

  /// Block → JSON Map
  Map<String, dynamic> encode(Block block) => {
    'id': block.id,
    'type': block.type.tag,
    'content': block.content.toJson(),
    'children': block.children.map(encode).toList(),
    'data': block.type.toJson(),
    'properties': Map.of(block.properties),
    'created_at': block.createdAt.millisecondsSinceEpoch,
    'updated_at': block.updatedAt.millisecondsSinceEpoch,
  };

  /// JSON Map → Block
  Block decode(Map<String, dynamic> json) => Block(
    id: json['id'] as String? ?? _idFactory.generateId(),
    type: _typeRegistry.resolve(
      json['type'] as String? ?? 'paragraph',
      _castMapOrEmpty(json['data']),
    ),
    content: json['content'] != null
        ? RichText.fromJson(_castMap(json['content']!))
        : RichText.empty(),
    children: (json['children'] as List<dynamic>?)
            ?.map((c) => decode(_castMap(c)))
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
}
