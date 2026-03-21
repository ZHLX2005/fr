import 'package:flutter/material.dart';

/// 桌面应用类型
enum HomeItemType { app, folder, placeholder }

/// 桌面应用抽象基类
sealed class HomeItem {
  String get id;
  String get title;
  HomeItemType get type;
}

/// 普通应用图标
class AppItem implements HomeItem {
  @override
  final String id;
  @override
  final String title;
  final IconData icon;
  final Color color;

  AppItem({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
  });

  @override
  HomeItemType get type => HomeItemType.app;

  AppItem copyWith({
    String? id,
    String? title,
    IconData? icon,
    Color? color,
  }) {
    return AppItem(
      id: id ?? this.id,
      title: title ?? this.title,
      icon: icon ?? this.icon,
      color: color ?? this.color,
    );
  }
}

/// 文件夹
class FolderItem implements HomeItem {
  @override
  final String id;
  @override
  final String title;
  final List<AppItem> children;

  FolderItem({
    required this.id,
    required this.title,
    required this.children,
  });

  @override
  HomeItemType get type => HomeItemType.folder;

  FolderItem copyWith({
    String? id,
    String? title,
    List<AppItem>? children,
  }) {
    return FolderItem(
      id: id ?? this.id,
      title: title ?? this.title,
      children: children ?? this.children,
    );
  }
}

/// 占位图标（拖拽预览用）
class PlaceholderItem implements HomeItem {
  @override
  String get id => '__placeholder__';
  @override
  String get title => '';

  PlaceholderItem();

  @override
  HomeItemType get type => HomeItemType.placeholder;
}
