part of 'inline_format.dart';

class InlineCodeFormat extends InlineFormat {
  const InlineCodeFormat();
  @override
  Map<String, dynamic> toJson() => {'type': 'inline_code'};

  @override
  bool operator ==(Object other) => other is InlineCodeFormat;
  @override
  int get hashCode => runtimeType.hashCode;
}
