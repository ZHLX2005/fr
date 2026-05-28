part of 'inline_format.dart';

class ColorFormat extends InlineFormat {
  final String color;
  const ColorFormat(this.color);

  @override
  Map<String, dynamic> toJson() => {'type': 'color', 'color': color};

  @override
  bool operator ==(Object other) =>
      other is ColorFormat && other.color == color;
  @override
  int get hashCode => color.hashCode;
}
