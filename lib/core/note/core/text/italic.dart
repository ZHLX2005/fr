part of 'inline_format.dart';

class ItalicFormat extends InlineFormat {
  const ItalicFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'italic'};

  @override
  bool operator ==(Object other) => other is ItalicFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}
