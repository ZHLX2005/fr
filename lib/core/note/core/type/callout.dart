part of 'type.dart';

class CalloutType extends BlockType {
  final String icon;

  const CalloutType({this.icon = ''}) : super(tag: 'callout');

  factory CalloutType.fromData(Map<String, dynamic> data) {
    return CalloutType(icon: data['icon'] as String? ?? '');
  }

  @override
  Map<String, dynamic> toJson() => {'icon': icon};

  @override
  bool operator ==(Object other) =>
    other is CalloutType && other.icon == icon;
  @override
  int get hashCode => Object.hash(runtimeType, icon);
}
