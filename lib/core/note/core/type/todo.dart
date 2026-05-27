part of 'type.dart';

class TodoType extends BlockType {
  final bool checked;

  const TodoType({this.checked = false}) : super(tag: 'todo');

  factory TodoType.fromData(Map<String, dynamic> data) {
    return TodoType(checked: data['checked'] as bool? ?? false);
  }

  @override
  Map<String, dynamic> toJson() => {'checked': checked};

  @override
  bool operator ==(Object other) =>
    other is TodoType && other.checked == checked;
  @override
  int get hashCode => Object.hash(runtimeType, checked);

  @override
  BlockType? get onEnterType => const TodoType(checked: false);
}
