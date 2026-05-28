part of 'type.dart';

class ToggleType extends BlockType {
  const ToggleType() : super(tag: 'toggle', canHaveChildren: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is ToggleType;
  @override
  int get hashCode => runtimeType.hashCode;
}
