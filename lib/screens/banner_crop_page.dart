import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

class BannerCropPage extends StatefulWidget {
  const BannerCropPage({super.key});

  @override
  State<BannerCropPage> createState() => _BannerCropPageState();
}

class _BannerCropPageState extends State<BannerCropPage> {
  String? _croppedPath;

  Future<void> _pickAndCrop() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: image.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: '裁剪Banner',
          toolbarColor: Theme.of(context).colorScheme.primary,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: false,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: '裁剪Banner',
          aspectRatioLockEnabled: false,
          resetAspectRatioEnabled: true,
          aspectRatioPickerButtonHidden: false,
          rotateButtonsHidden: false,
          rotateClockwiseButtonHidden: true,
        ),
      ],
    );

    if (croppedFile != null) {
      setState(() {
        _croppedPath = croppedFile.path;
      });
    }
  }

  void _saveAndReturn() {
    if (_croppedPath != null) {
      Navigator.pop(context, _croppedPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置Banner'),
        centerTitle: true,
        actions: [
          if (_croppedPath != null)
            TextButton(
              onPressed: _saveAndReturn,
              child: const Text('保存'),
            ),
        ],
      ),
      body: Column(
        children: [
          // 预览区域
          Expanded(
            child: _croppedPath != null
                ? Container(
                    margin: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        File(_croppedPath!),
                        fit: BoxFit.cover,
                        width: double.infinity,
                      ),
                    ),
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.image,
                          size: 80,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withOpacity(0.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '选择图片并裁剪',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.5),
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '推荐比例 16:9',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurface
                                    .withOpacity(0.4),
                              ),
                        ),
                      ],
                    ),
                  ),
          ),
          // 操作按钮
          Padding(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _pickAndCrop,
                icon: const Icon(Icons.crop),
                label: Text(_croppedPath != null ? '重新选择图片' : '选择图片'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
