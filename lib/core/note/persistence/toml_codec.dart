import 'package:toml/toml.dart';

/// `Map<String, dynamic>` ↔ TOML 字符串 的薄包装编解码器。
///
/// 仅在 [NoteRepository] 的 IO 边界使用，领域层（Block / BlockCodec）
/// 不感知存在 TOML 这种格式。对任意嵌套 Map 做无损 roundtrip。
class TomlCodec {
  /// Map → TOML 字符串。
  ///
  /// 输入应是 [BlockCodec.encode] 的产物：含嵌套 children 数组、
  /// content/data/properties table、snake_case 顶层键。
  String encode(Map<String, dynamic> map) {
    return TomlDocument.fromMap(map).toString();
  }

  /// TOML 字符串 → Map。
  ///
  /// 解析失败时抛 [TomlException]（由调用方决定降级策略）。
  Map<String, dynamic> decode(String toml) {
    return TomlDocument.parse(toml).toMap();
  }
}
