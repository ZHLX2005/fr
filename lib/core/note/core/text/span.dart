import 'inline_format.dart';

/// 一段文字及其内联格式。最多一个 [InlineFormat] 附着其上。
///
/// 复合格式（如粗体+红字）需拆为相邻的多个 Span。
class Span {
  final String text;
  final InlineFormat? format;

  const Span(this.text, {this.format});

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
      identical(this, other) ||
      other is Span && text == other.text && format == other.format;

  @override
  int get hashCode => Object.hash(text, format);
}
