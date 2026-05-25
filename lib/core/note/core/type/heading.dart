part of 'type.dart';

class HeadingType extends BlockType {
  final int level;

  const HeadingType({this.level = 1}) : super(tag: 'heading');

  factory HeadingType.fromData(Map<String, dynamic> data) {
    return HeadingType(level: data['level'] as int? ?? 1);
  }

  @override
  Map<String, dynamic> toJson() => {'level': level};

  @override
  bool operator ==(Object other) =>
    other is HeadingType && other.level == level;
  @override
  int get hashCode => Object.hash(runtimeType, level);
}
