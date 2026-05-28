part of 'type.dart';

class ColumnType extends BlockType {
  final double ratio;

  const ColumnType({this.ratio = 1.0})
    : super(tag: 'column', canHaveChildren: true);

  factory ColumnType.fromData(Map<String, dynamic> data) {
    return ColumnType(ratio: (data['ratio'] as num?)?.toDouble() ?? 1.0);
  }

  @override
  Map<String, dynamic> toJson() => {'ratio': ratio};

  @override
  bool operator ==(Object other) =>
    other is ColumnType && other.ratio == ratio;
  @override
  int get hashCode => Object.hash(runtimeType, ratio);

  @override
  BlockType? get onEnterType => null;
}
