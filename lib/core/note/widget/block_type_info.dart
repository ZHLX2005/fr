import 'package:flutter/material.dart';
import '../core/core.dart';

/// BlockType 的分类枚举。
enum BlockTypeCategory {
  heading,
  list,
  text,
  media;

  String get label => switch (this) {
    BlockTypeCategory.heading => '标题',
    BlockTypeCategory.list => '列表',
    BlockTypeCategory.text => '文本',
    BlockTypeCategory.media => '媒体',
  };
}

/// BlockType 的 UI 元信息，供工具栏和类型面板等消费。
class BlockTypeInfo {
  final BlockType prototype;
  final IconData icon;
  final String label;
  final BlockTypeCategory category;

  const BlockTypeInfo({
    required this.prototype,
    required this.icon,
    required this.label,
    required this.category,
  });
}
