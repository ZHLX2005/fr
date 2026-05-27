part of 'type.dart';

class PageType extends BlockType {
  const PageType()
    : super(tag: 'page', containerOnly: true, canHaveChildren: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is PageType;
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  BlockType? get onEnterType => null;
}
