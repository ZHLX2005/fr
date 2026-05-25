part of 'type.dart';

class QuoteType extends BlockType {
  const QuoteType() : super(tag: 'quote');

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is QuoteType;
  @override
  int get hashCode => runtimeType.hashCode;
}
