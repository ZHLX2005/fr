part of 'inline_format.dart';

class StrikethroughFormat extends InlineFormat {
  const StrikethroughFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'strikethrough'};

  @override
  bool operator ==(Object other) => other is StrikethroughFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}
