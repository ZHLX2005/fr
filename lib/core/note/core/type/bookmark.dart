part of 'type.dart';

class BookmarkType extends BlockType {
  final String url;
  final String title;
  final String description;
  final String favicon;

  const BookmarkType({
    this.url = '',
    this.title = '',
    this.description = '',
    this.favicon = '',
  }) : super(tag: 'bookmark');

  factory BookmarkType.fromData(Map<String, dynamic> data) {
    return BookmarkType(
      url: data['url'] as String? ?? '',
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      favicon: data['favicon'] as String? ?? '',
    );
  }

  @override
  Map<String, dynamic> toJson() => {
    'url': url,
    'title': title,
    'description': description,
    'favicon': favicon,
  };

  @override
  bool operator ==(Object other) =>
    other is BookmarkType &&
    other.url == url &&
    other.title == title &&
    other.description == description &&
    other.favicon == favicon;
  @override
  int get hashCode =>
    Object.hash(runtimeType, url, title, description, favicon);
}
