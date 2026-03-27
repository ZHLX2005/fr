import 'package:flutter/material.dart';
import '../widgets/image_picker_widget.dart';

/// Banner 图片设置页面
/// 使用通用 ImagePickerWidget 组件
class BannerCropPage extends StatelessWidget {
  final String? initialImagePath;

  const BannerCropPage({
    super.key,
    this.initialImagePath,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    const bannerHeight = 200.0;
    final aspectRatio = screenWidth / bannerHeight;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置Banner'),
        centerTitle: true,
      ),
      body: ImagePickerWidget(
        config: ImagePickerConfig(
          aspectRatioX: aspectRatio,
          aspectRatioY: 1,
          cropTitle: '裁剪Banner',
          lockAspectRatio: false,
          enableCrop: true,
        ),
        initialImagePath: initialImagePath,
        emptyStateHint: '选择图片作为Banner',
        emptyStateSubHint: '可自由调整裁剪区域',
        onImageSelected: (path) {
          Navigator.pop(context, path);
        },
      ),
    );
  }
}
