import 'span.dart';

/// 富文本内容。由多个 [Span] 按顺序拼接组成。
///
/// 纯文本通过 [toPlainText] 获取，用于搜索索引等场景。
class RichText {
  final List<Span> spans;

  const RichText(this.spans);

  factory RichText.text(String text) => RichText([Span.text(text)]);

  factory RichText.empty() => const RichText([]);

  String toPlainText() => spans.map((s) => s.text).join();

  int get length => toPlainText().length;

  bool get isEmpty => spans.isEmpty || spans.every((s) => s.text.isEmpty);
  bool get isNotEmpty => !isEmpty;

  RichText copyWith({List<Span>? spans}) => RichText(spans ?? this.spans);

  Map<String, dynamic> toJson() =>
      {'spans': spans.map((s) => s.toJson()).toList()};

  factory RichText.fromJson(Map<String, dynamic> json) {
    final list = json['spans'] as List<dynamic>?;
    if (list == null || list.isEmpty) return RichText.empty();
    return RichText(
        list.map((s) => Span.fromJson(s as Map<String, dynamic>)).toList());
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RichText && _listEquals(spans, other.spans);

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
