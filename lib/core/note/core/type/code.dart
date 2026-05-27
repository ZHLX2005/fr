part of 'type.dart';

class CodeType extends BlockType {
  final String language;

  const CodeType({this.language = ''}) : super(tag: 'code');

  factory CodeType.fromData(Map<String, dynamic> data) {
    return CodeType(language: data['language'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {'language': language};

  @override
  bool operator ==(Object other) =>
    other is CodeType && other.language == language;
  @override
  int get hashCode => Object.hash(runtimeType, language);

  @override
  BlockType? get onEnterType => null;

  @override
  bool get multiline => true;
}
