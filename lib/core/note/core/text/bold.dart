part of 'inline_format.dart';

class BoldFormat extends InlineFormat {
  const BoldFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'bold'};

  @override
  bool operator ==(Object other) => other is BoldFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}
