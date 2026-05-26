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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Span && text == other.text && format == other.format;

  @override
  int get hashCode => Object.hash(text, format);
}
