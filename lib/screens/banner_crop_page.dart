import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

class BannerCropPage extends StatefulWidget {
  const BannerCropPage({super.key});

  @override
  State<BannerCropPage> createState() => _BannerCropPageState();
}

class _BannerCropPageState extends State<BannerCropPage> {
  String? _selectedPath;
  String? _croppedPath;
  double _targetRatio = 16 / 9;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // 计算实际的Banner显示比例
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final screenWidth = MediaQuery.of(context).size.width;
        // Banner实际显示高度为 expandedHeight: 200
        const bannerHeight = 200.0;
        setState(() {
          _targetRatio = screenWidth / bannerHeight;
        });
      }
    });
  }

  // 选择图片并裁剪
  Future<void> _pickAndCropImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);

    if (image == null) return;

    setState(() {
      _isLoading = true;
      _selectedPath = image.path;
    });

    try {
      // 使用 image_cropper 进行裁剪
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: image.path,
        aspectRatio: CropAspectRatio(
          ratioX: _targetRatio,
          ratioY: 1,
        ),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪Banner',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '裁剪Banner',
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
            aspectRatioLockEnabled: false,
          ),
        ],
      );

      if (croppedFile != null) {
        // 将裁剪后的图片保存到应用目录
        final savedPath = await _saveCroppedImage(croppedFile.path);
        if (savedPath != null && mounted) {
          setState(() {
            _croppedPath = savedPath;
            _isLoading = false;
          });
        }
      } else {
        // 用户取消裁剪，保留原图
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('裁剪失败: $e')),
        );
      }
    }
  }

  // 保存裁剪后的图片到应用目录
  Future<String?> _saveCroppedImage(String tempPath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'banner_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${dir.path}/$fileName';

      // 复制文件到应用目录
      final tempFile = File(tempPath);
      await tempFile.copy(savedPath);

      // 删除临时文件
      try {
        await tempFile.delete();
      } catch (_) {}

      return savedPath;
    } catch (e) {
      return null;
    }
  }

  // 重新裁剪
  Future<void> _reCropImage() async {
    if (_selectedPath == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: _selectedPath!,
        aspectRatio: CropAspectRatio(
          ratioX: _targetRatio,
          ratioY: 1,
        ),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: '裁剪Banner',
            toolbarColor: Theme.of(context).colorScheme.primary,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.original,
            lockAspectRatio: false,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: '裁剪Banner',
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
            aspectRatioLockEnabled: false,
          ),
        ],
      );

      if (croppedFile != null) {
        final savedPath = await _saveCroppedImage(croppedFile.path);
        if (savedPath != null && mounted) {
          setState(() {
            _croppedPath = savedPath;
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _saveAndReturn() {
    // 优先返回裁剪后的图片，如果没有裁剪则返回原图
    final resultPath = _croppedPath ?? _selectedPath;
    if (resultPath != null) {
      Navigator.pop(context, resultPath);
    }
  }

  String _getRatioString() {
    final ratio = _targetRatio;
    if ((ratio - 16 / 9).abs() < 0.1) return '16:9';
    if ((ratio - 4 / 3).abs() < 0.1) return '4:3';
    if ((ratio - 21 / 9).abs() < 0.1) return '21:9';
    if ((ratio - 1).abs() < 0.1) return '1:1';
    return '${ratio.toStringAsFixed(1)}:1';
  }

  @override
  Widget build(BuildContext context) {
    // 显示路径优先使用裁剪后的图片
    final displayPath = _croppedPath ?? _selectedPath;

    return Scaffold(
      appBar: AppBar(
        title: const Text('设置Banner'),
        centerTitle: true,
        actions: [
          if (displayPath != null)
            TextButton(
              onPressed: _saveAndReturn,
              child: const Text('完成'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 预览区域
                Expanded(
                  child: displayPath != null
                      ? _buildPreview(displayPath)
                      : _buildEmptyState(),
                ),
                // 操作按钮
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _pickAndCropImage,
                          icon: const Icon(Icons.photo_library),
                          label: Text(
                            displayPath != null ? '重新选择' : '选择图片',
                          ),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      if (displayPath != null && _selectedPath != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: _reCropImage,
                            icon: const Icon(Icons.crop),
                            label: const Text('调整裁剪区域'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPreview(String path) {
    return Container(
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
        child: Column(
          children: [
            // 实际比例预览区域
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 使用实际显示比例
                  AspectRatio(
                    aspectRatio: _targetRatio,
                    child: Image.file(
                      File(path),
                      fit: BoxFit.cover,
                    ),
                  ),
                  // 半透明边框
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: Colors.white.withOpacity(0.5),
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  // 提示
                  if (_croppedPath == null)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '点击"调整裁剪区域"手动选择',
                            style: const TextStyle(color: Colors.white, fontSize: 12),
                          ),
                        ),
                      ),
                    ),
                  if (_croppedPath != null)
                    Positioned(
                      bottom: 8,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                '已裁剪为${_getRatioString()}',
                                style: const TextStyle(color: Colors.white, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 图片信息
            Container(
              padding: const EdgeInsets.all(12),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    _croppedPath != null ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: _croppedPath != null
                        ? Colors.green
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _croppedPath != null
                          ? '裁剪完成，点击"完成"保存'
                          : '选择图片后可手动调整裁剪区域',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 80,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '选择图片作为Banner',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.5),
                ),
          ),
          const SizedBox(height: 8),
          Text(
            '可手动调整裁剪区域',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withOpacity(0.4),
                ),
          ),
        ],
      ),
    );
  }
}
