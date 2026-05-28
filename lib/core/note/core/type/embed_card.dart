part of 'type.dart';

class EmbedCardType extends BlockType {
  final String title;
  final String subtitle;
  final String icon;
  final String sourceBlockId;

  const EmbedCardType({
    this.title = '',
    this.subtitle = '',
    this.icon = '',
    this.sourceBlockId = '',
  }) : super(tag: 'embed_card');

  factory EmbedCardType.fromData(Map<String, dynamic> data) {
    return EmbedCardType(
      title: data['title'] as String? ?? '',
      subtitle: data['subtitle'] as String? ?? '',
      icon: data['icon'] as String? ?? '',
      sourceBlockId: data['sourceBlockId'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'title': title,
    'subtitle': subtitle,
    'icon': icon,
    'sourceBlockId': sourceBlockId,
  };

  @override
  bool operator ==(Object other) =>
    other is EmbedCardType &&
    other.title == title &&
    other.subtitle == subtitle &&
    other.icon == icon &&
    other.sourceBlockId == sourceBlockId;
  @override
  int get hashCode =>
    Object.hash(runtimeType, title, subtitle, icon, sourceBlockId);
}
