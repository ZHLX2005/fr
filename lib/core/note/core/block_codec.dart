import 'dart:math';
import 'type/type_registry.dart';
import 'text/rich_text.dart';
import 'text/rich_text_codec.dart';
import 'block.dart';

/// Block ↔ JSON 互转编解码器。
class BlockCodec {
  final BlockTypeRegistry _typeRegistry;
  final RichTextCodec _richTextCodec;

  BlockCodec(this._typeRegistry, this._richTextCodec);

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
  ///
  /// 容错：若 id 缺失，生成新 uuid；其他必填字段缺失时降级默认值。
  /// 这是因为后端 modified_toml 可能被 LLM 编辑时**丢了部分字段**（如 root 的 id），
  /// 前端不能因此整体解析失败。
  Block decode(Map<String, dynamic> json) => Block(
    id: (json['id'] as String?) ?? _genId(),
    type: _typeRegistry.resolve(
      json['type'] as String? ?? 'paragraph',
      _castMapOrEmpty(json['data']),
    ),
    content: json['content'] != null
        ? _richTextCodec.decode(_castMap(json['content']!))
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

  /// 生成 fallback id — 后端 TOML 缺 id 时用
  static String _genId() {
    final r = Random();
    final hex = List.generate(
      32,
      (_) => r.nextInt(16).toRadixString(16),
    ).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20, 32)}';
  }
}
