part of 'type.dart';

class DividerType extends BlockType {
  const DividerType() : super(tag: 'divider', containerOnly: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is DividerType;
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  BlockType? get onEnterType => null;
}
