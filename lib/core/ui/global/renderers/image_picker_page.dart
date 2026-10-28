// 图片选择整页（自 image_picker_widget.dart 拆出，2026-10-28 N7）

import 'package:flutter/material.dart';

import 'image_picker_config.dart';
import 'image_picker_widget.dart';

/// 图片选择页面 - 完整的页面封装
class ImagePickerPage extends StatelessWidget {
  final ImagePickerConfig config;
  final String? initialImagePath;
  final String title;
  final String? emptyStateHint;
  final String? emptyStateSubHint;

  const ImagePickerPage({
    super.key,
    this.config = const ImagePickerConfig(),
    this.initialImagePath,
    this.title = '设置图片',
    this.emptyStateHint,
    this.emptyStateSubHint,
  });

  /// 导航到选择器页面，返回选中的图片路径
  static Future<String?> navigate(
    BuildContext context, {
    ImagePickerConfig config = const ImagePickerConfig(),
    String? initialImagePath,
    String title = '设置图片',
    String? emptyStateHint,
    String? emptyStateSubHint,
  }) {
    return Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) => ImagePickerPage(
          config: config,
          initialImagePath: initialImagePath,
          title: title,
          emptyStateHint: emptyStateHint,
          emptyStateSubHint: emptyStateSubHint,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title), centerTitle: true),
      body: ImagePickerWidget(
        config: config,
        initialImagePath: initialImagePath,
        emptyStateHint: emptyStateHint,
        emptyStateSubHint: emptyStateSubHint,
        onImageSelected: (path) {
          Navigator.pop(context, path);
        },
      ),
    );
  }
}
