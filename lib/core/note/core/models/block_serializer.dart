import '../type/type.dart';

/// 从 [tag] 及可选 [data] 反查具体 BlockType 子类实例。
/// 工厂注册表见 [typeRegistry]（与 type.dart 的 [part] 指令共存）。
BlockType deserializeBlockType(String tag, [Map<String, dynamic> data = const {}]) {
  final factory = typeRegistry[tag];
  if (factory == null) {
    throw ArgumentError('Unknown block type tag: "$tag".');
  }
  return factory(data);
}
