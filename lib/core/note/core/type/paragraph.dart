part of 'type.dart';

class ParagraphType extends BlockType {
  const ParagraphType() : super(tag: 'paragraph');

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is ParagraphType;
  @override
  int get hashCode => runtimeType.hashCode;
}
