part of 'type.dart';

class ColumnListType extends BlockType {
  const ColumnListType() : super(tag: 'column_list', canHaveChildren: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is ColumnListType;
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  BlockType? get onEnterType => null;
}
