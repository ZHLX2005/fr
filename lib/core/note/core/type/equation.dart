part of 'type.dart';

class EquationType extends BlockType {
  final String latex;

  const EquationType({this.latex = ''}) : super(tag: 'equation');

  factory EquationType.fromData(Map<String, dynamic> data) {
    return EquationType(latex: data['latex'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {'latex': latex};

  @override
  bool operator ==(Object other) =>
    other is EquationType && other.latex == latex;
  @override
  int get hashCode => Object.hash(runtimeType, latex);
}
