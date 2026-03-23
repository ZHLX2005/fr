import 'package:flutter/material.dart';

/// Bookmark type enum
enum BookmarkItemType { bookmark, folder, placeholder }

/// Bookmark icon type enum
enum BookmarkIconType { icon, network, local }

/// Icon name to IconData constant mapping
class BookmarkIcons {
  static const Map<String, IconData> _iconMap = {
    'public': Icons.public,
    'search': Icons.search,
    'code': Icons.code,
    'play_circle_filled': Icons.play_circle_filled,
    'flutter_dash': Icons.flutter_dash,
    'edit': Icons.edit,
    'video_library': Icons.video_library,
    'shopping_bag': Icons.shopping_bag,
    'music_video': Icons.music_video,
    'new_releases': Icons.new_releases,
    'article': Icons.article,
    'school': Icons.school,
    'business': Icons.business,
    'gamepad': Icons.gamepad,
    'alternate_email': Icons.alternate_email,
  };

  static IconData getIcon(String name) {
    return _iconMap[name] ?? Icons.public;
  }

  static String getName(IconData icon) {
    for (final entry in _iconMap.entries) {
      if (entry.value == icon) {
        return entry.key;
      }
    }
    return 'public';
  }

  static List<String> get availableNames => _iconMap.keys.toList();
}

/// Base bookmark item
abstract class BookmarkItem {
  String get id;
  String get name;
  BookmarkItemType get type;
}

/// Single bookmark
class SingleBookmark implements BookmarkItem {
  final String id;
  final String name;
  final String url;
  final String iconName;
  final Color color;
  final BookmarkIconType iconType;
  final String? iconUrl; // 网络图标URL或本地文件路径

  SingleBookmark({
    required this.id,
    required this.name,
    required this.url,
    required this.iconName,
    required this.color,
    this.iconType = BookmarkIconType.icon,
    this.iconUrl,
  });

  IconData get icon => BookmarkIcons.getIcon(iconName);

  @override
  BookmarkItemType get type => BookmarkItemType.bookmark;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'url': url,
      'iconName': iconName,
      'colorValue': color.value,
      'iconType': iconType.name,
      'iconUrl': iconUrl,
      'type': 'bookmark',
    };
  }

  static SingleBookmark fromJson(Map<String, dynamic> json) {
    return SingleBookmark(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      iconName: json['iconName'] as String? ?? 'public',
      color: Color(json['colorValue'] as int),
      iconType: BookmarkIconType.values.firstWhere(
        (e) => e.name == json['iconType'],
        orElse: () => BookmarkIconType.icon,
      ),
      iconUrl: json['iconUrl'] as String?,
    );
  }

  SingleBookmark copyWith({
    String? id,
    String? name,
    String? url,
    String? iconName,
    Color? color,
    BookmarkIconType? iconType,
    String? iconUrl,
  }) {
    return SingleBookmark(
      id: id ?? this.id,
      name: name ?? this.name,
      url: url ?? this.url,
      iconName: iconName ?? this.iconName,
      color: color ?? this.color,
      iconType: iconType ?? this.iconType,
      iconUrl: iconUrl ?? this.iconUrl,
    );
  }
}

/// Bookmark folder
class BookmarkFolder implements BookmarkItem {
  final String id;
  @override
  final String name;
  final List<SingleBookmark> children;

  BookmarkFolder({
    required this.id,
    required this.name,
    required this.children,
  });

  @override
  BookmarkItemType get type => BookmarkItemType.folder;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'children': children.map((e) => e.toJson()).toList(),
      'type': 'folder',
    };
  }

  static BookmarkFolder fromJson(Map<String, dynamic> json) {
    return BookmarkFolder(
      id: json['id'] as String,
      name: json['name'] as String,
      children: (json['children'] as List<dynamic>?)
              ?.map((e) => SingleBookmark.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }

  BookmarkFolder copyWith({
    String? id,
    String? name,
    List<SingleBookmark>? children,
  }) {
    return BookmarkFolder(
      id: id ?? this.id,
      name: name ?? this.name,
      children: children ?? this.children,
    );
  }
}

/// Placeholder for drag preview
class BookmarkPlaceholder implements BookmarkItem {
  @override
  String get id => '__placeholder__';

  @override
  String get name => '';

  @override
  BookmarkItemType get type => BookmarkItemType.placeholder;
}
