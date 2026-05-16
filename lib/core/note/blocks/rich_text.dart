import 'block_type.dart';

/// 富文本内容 = 多个 Span 的序列
class RichText {
  final List<Span> spans;

  const RichText(this.spans);

  /// 从纯文本创建
  factory RichText.text(String text) => RichText([Span.text(text)]);

  /// 空内容
  factory RichText.empty() => const RichText([]);

  /// 纯文本拼接（用于搜索索引等）
  String toPlainText() => spans.map((s) => s.text).join();

  int get length => toPlainText().length;

  bool get isEmpty => spans.isEmpty || spans.every((s) => s.text.isEmpty);
  bool get isNotEmpty => !isEmpty;

  RichText copyWith({List<Span>? spans}) => RichText(spans ?? this.spans);

  Map<String, dynamic> toJson() => {'spans': spans.map((s) => s.toJson()).toList()};

  factory RichText.fromJson(Map<String, dynamic> json) {
    final list = json['spans'] as List<dynamic>?;
    if (list == null || list.isEmpty) return RichText.empty();
    return RichText(list.map((s) => Span.fromJson(s as Map<String, dynamic>)).toList());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RichText && _listEquals(spans, other.spans);

  @override
  int get hashCode => Object.hashAll(spans);

  static bool _listEquals(List<Span> a, List<Span> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// 文本片段 + 格式
class Span {
  final String text;
  final InlineFormat? format;

  const Span(this.text, {this.format});

  /// 纯文本 span（无格式）
  const Span.text(this.text) : format = null;

  bool get isPlain => format == null;

  Span copyWith({String? text, InlineFormat? format}) =>
      Span(text ?? this.text, format: format ?? this.format);

  Map<String, dynamic> toJson() => {
        'text': text,
        if (format != null) 'format': format!.toJson(),
      };

  factory Span.fromJson(Map<String, dynamic> json) {
    final formatJson = json['format'] as Map<String, dynamic>?;
    return Span(
      json['text'] as String? ?? '',
      format: formatJson != null ? InlineFormat.fromJson(formatJson) : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Span && text == other.text && format == other.format;

  @override
  int get hashCode => Object.hash(text, format);
}

/// 块数据（type 专属的 data 字段校验与默认值）
class BlockData {
  final Map<String, dynamic> _data;

  const BlockData._(this._data);

  factory BlockData.fromMap(Map<String, dynamic> data) => BlockData._(Map.of(data));

  factory BlockData.empty() => const BlockData._({});

  Map<String, dynamic> toMap() => Map.of(_data);

  /// 安全的取值
  T? get<T>(String key) => _data[key] as T?;
  T getOrDefault<T>(String key, T defaultValue) => (_data[key] as T?) ?? defaultValue;

  /// 合并更新
  BlockData merge(Map<String, dynamic> updates) =>
      BlockData._({..._data, ...updates});

  /// 验证与 BlockType 的 schema 是否匹配
  bool validate(BlockType type) {
    switch (type) {
      case BlockType.heading:
        final level = _data['level'];
        return level is int && level >= 1 && level <= 6;
      case BlockType.todo:
        final checked = _data['checked'];
        return checked == null || checked is bool;
      case BlockType.code:
        final lang = _data['language'];
        return lang == null || lang is String;
      case BlockType.image:
        return _data['src'] is String;
      case BlockType.column:
        final ratio = _data['ratio'];
        return ratio == null || ratio is num;
      case BlockType.orderedListItem:
        final number = _data['number'];
        return number == null || number is int;
      default:
        return true;
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BlockData && _mapEquals(_data, other._data);

  @override
  int get hashCode => Object.hashAll(_data.entries.expand((e) => [e.key, e.value]));

  static bool _mapEquals(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
