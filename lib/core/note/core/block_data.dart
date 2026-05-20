import 'block_type.dart';

/// Block 类型专属的附加数据。
///
/// 内部为 Map，提供类型安全的 getter、合并更新、
/// 以及按 [BlockType] 校验字段 schema 的能力。
///
/// 各类型 data schema：
///   heading         → { level: int (1-6) }
///   todo            → { checked: bool }
///   code            → { language: string }
///   image           → { src: string, caption?, width?, height? }
///   column          → { ratio: double }
///   orderedListItem → { number: int }
///   callout         → { icon: string }
///   bookmark        → { url, title, description, favicon }
///   embedCard       → { title, subtitle, icon, sourceBlockId }
///   equation        → { latex: string }
///   syncedBlock     → { refBlockId: string }
class BlockData {
  final Map<String, dynamic> _data;

  const BlockData._(this._data);

  factory BlockData.fromMap(Map<String, dynamic> data) =>
      BlockData._(Map.of(data));

  factory BlockData.empty() => const BlockData._({});

  Map<String, dynamic> toMap() => Map.of(_data);

  T? get<T>(String key) => _data[key] as T?;
  T getOrDefault<T>(String key, T defaultValue) =>
      (_data[key] as T?) ?? defaultValue;

  BlockData merge(Map<String, dynamic> updates) =>
      BlockData._({..._data, ...updates});

  bool validate(BlockType type) {
    return switch (type) {
      BlockType.heading => (_data['level'] is int &&
          (_data['level'] as int) >= 1 &&
          (_data['level'] as int) <= 6),
      BlockType.todo => _data['checked'] == null || _data['checked'] is bool,
      BlockType.code =>
        _data['language'] == null || _data['language'] is String,
      BlockType.image => _data['src'] is String,
      BlockType.column => _data['ratio'] == null || _data['ratio'] is num,
      BlockType.orderedListItem =>
        _data['number'] == null || _data['number'] is int,
      _ => true,
    };
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BlockData && _mapEquals(_data, other._data);

  @override
  int get hashCode =>
      Object.hashAll(_data.entries.expand((e) => [e.key, e.value]));

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
