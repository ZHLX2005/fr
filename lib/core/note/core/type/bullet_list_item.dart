part of 'type.dart';

class BulletListItemType extends BlockType {
  const BulletListItemType() : super(tag: 'bullet_list_item', canHaveChildren: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is BulletListItemType;
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  BlockType? get onEnterType => const BulletListItemType();
}
