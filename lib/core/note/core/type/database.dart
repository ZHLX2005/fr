part of 'type.dart';

class DatabaseType extends BlockType {
  const DatabaseType() : super(tag: 'database', canHaveChildren: true);

  @override
  Map<String, dynamic> toJson() => const {};

  @override
  bool operator ==(Object other) => other is DatabaseType;
  @override
  int get hashCode => runtimeType.hashCode;

  @override
  BlockType? get onEnterType => null;
}
