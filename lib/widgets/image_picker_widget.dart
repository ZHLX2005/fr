import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

/// 图片选择器配置
class ImagePickerConfig {
  /// 裁剪宽度与高度的比例
  final double aspectRatioX;
  final double aspectRatioY;

  /// 裁剪界面标题
  final String cropTitle;

  /// 是否锁定宽高比
  final bool lockAspectRatio;

  /// 初始宽高比预设
  final CropAspectRatioPreset aspectRatioPreset;

  /// 工具栏颜色
  final Color? toolbarColor;

  /// 是否显示裁剪功能
  final bool enableCrop;

  const ImagePickerConfig({
    this.aspectRatioX = 16,
    this.aspectRatioY = 9,
    this.cropTitle = '裁剪图片',
    this.lockAspectRatio = false,
    this.aspectRatioPreset = CropAspectRatioPreset.original,
    this.toolbarColor,
    this.enableCrop = true,
  });

  /// Banner 配置 (16:9)
  factory ImagePickerConfig.banner({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 16,
      aspectRatioY: 9,
      cropTitle: '裁剪Banner',
      toolbarColor: toolbarColor,
    );
  }

  /// 正方形配置 (1:1)
  factory ImagePickerConfig.square({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 1,
      aspectRatioY: 1,
      cropTitle: '裁剪图片',
      toolbarColor: toolbarColor,
    );
  }

  /// 自由裁剪配置
  factory ImagePickerConfig.free({Color? toolbarColor}) {
    return ImagePickerConfig(
      aspectRatioX: 1,
      aspectRatioY: 1,
      cropTitle: '裁剪图片',
      lockAspectRatio: false,
      toolbarColor: toolbarColor,
    );
  }

  /// 获取宽高比
  double get aspectRatio => aspectRatioX / aspectRatioY;

  /// 获取宽高比字符串
  String get aspectRatioString {
    final ratio = aspectRatio;
    if ((ratio - 16 / 9).abs() < 0.1) return '16:9';
    if ((ratio - 4 / 3).abs() < 0.1) return '4:3';
    if ((ratio - 21 / 9).abs() < 0.1) return '21:9';
    if ((ratio - 1).abs() < 0.1) return '1:1';
    return '${ratio.toStringAsFixed(1)}:1';
  }
}

/// 图片选择器 Widget - 支持选择、裁剪、预览
/// 可用于 Banner 设置、卡片背景等场景
class ImagePickerWidget extends StatefulWidget {
  /// 选择器配置
  final ImagePickerConfig config;

  /// 当前图片路径（用于编辑）
  final String? initialImagePath;

  /// 选择完成回调
  final ValueChanged<String> onImageSelected;

  /// 标题
  final String title;

  /// 空状态提示
  final String? emptyStateHint;
  final String? emptyStateSubHint;

  const ImagePickerWidget({
    super.key,
    this.config = const ImagePickerConfig(),
    this.initialImagePath,
    required this.onImageSelected,
    this.title = '设置图片',
    this.emptyStateHint,
    this.emptyStateSubHint,
  });

  @override
  State<ImagePickerWidget> createState() => _ImagePickerWidgetState();
}

class _ImagePickerWidgetState extends State<ImagePickerWidget> {
  String? _selectedPath;
  String? _croppedPath;
  bool _isLoading = false;
  bool _hasUnsavedChanges = false;

  @override
  void initState() {
    super.initState();
    _selectedPath = widget.initialImagePath;
  }

  /// 选择并裁剪图片
  Future<void> _pickAndCropImage() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.gallery);
    if (image == null) return;

    setState(() {
      _isLoading = true;
      _selectedPath = image.path;
      _croppedPath = null;
    });

    try {
      String? finalPath = image.path;

      // 如果启用裁剪
      if (widget.config.enableCrop) {
        final croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: CropAspectRatio(
            ratioX: widget.config.aspectRatioX,
            ratioY: widget.config.aspectRatioY,
          ),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: widget.config.cropTitle,
              toolbarColor: widget.config.toolbarColor ?? Colors.blue,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: widget.config.aspectRatioPreset,
              lockAspectRatio: widget.config.lockAspectRatio,
              hideBottomControls: false,
            ),
            IOSUiSettings(
              title: widget.config.cropTitle,
              cancelButtonTitle: '取消',
              doneButtonTitle: '完成',
              aspectRatioLockEnabled: widget.config.lockAspectRatio,
            ),
          ],
        );

        if (croppedFile != null) {
          finalPath = await _saveImage(croppedFile.path);
        }
      } else {
        // 不裁剪，直接保存原图
        finalPath = await _saveImage(image.path);
      }

      if (finalPath != null && mounted) {
        setState(() {
          _croppedPath = finalPath;
          _selectedPath = finalPath;
          _isLoading = false;
          _hasUnsavedChanges = true;
        });
        // 不立即触发回调，让用户预览后手动确认
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e')),
        );
      }
    }
  }

  /// 重新裁剪
  Future<void> _reCropImage() async {
    if (_selectedPath == null || !widget.config.enableCrop) return;

    setState(() => _isLoading = true);

    try {
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: _selectedPath!,
        aspectRatio: CropAspectRatio(
          ratioX: widget.config.aspectRatioX,
          ratioY: widget.config.aspectRatioY,
        ),
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: widget.config.cropTitle,
            toolbarColor: widget.config.toolbarColor ?? Colors.blue,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: widget.config.aspectRatioPreset,
            lockAspectRatio: widget.config.lockAspectRatio,
            hideBottomControls: false,
          ),
          IOSUiSettings(
            title: widget.config.cropTitle,
            cancelButtonTitle: '取消',
            doneButtonTitle: '完成',
            aspectRatioLockEnabled: widget.config.lockAspectRatio,
          ),
        ],
      );

      if (croppedFile != null) {
        final savedPath = await _saveImage(croppedFile.path);
        if (savedPath != null && mounted) {
          setState(() {
            _croppedPath = savedPath;
            _selectedPath = savedPath;
            _isLoading = false;
            _hasUnsavedChanges = true;
          });
          // 不立即触发回调，让用户预览后手动确认
        } else if (mounted) {
          setState(() => _isLoading = false);
        }
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// 保存图片到应用目录
  Future<String?> _saveImage(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${dir.path}/$fileName';

      final sourceFile = File(sourcePath);
      await sourceFile.copy(savedPath);

      // 删除临时文件
      try {
        if (sourcePath != savedPath) {
          await sourceFile.delete();
        }
      } catch (_) {}

      return savedPath;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayPath = _croppedPath ?? _selectedPath;
    final hasChanges = _hasUnsavedChanges || (widget.initialImagePath != null && widget.initialImagePath != displayPath);

    return Column(
      children: [
        // 预览区域
        Expanded(
          child: displayPath != null
              ? _buildPreview(displayPath, theme)
              : _buildEmptyState(theme),
        ),
        // 操作按钮
        Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // 确认按钮（有未保存更改时显示）
              if (hasChanges && displayPath != null) ...[
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isLoading ? null : () => _confirmSelection(displayPath),
                        icon: _isLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check),
                        label: const Text('确认使用'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.green,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isLoading ? null : _cancelChanges,
                        icon: const Icon(Icons.close),
                        label: const Text('取消'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
              // 选择图片按钮
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _isLoading ? null : _pickAndCropImage,
                  icon: const Icon(Icons.photo_library),
                  label: Text(
                    displayPath != null ? '重新选择' : '选择图片',
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
              if (displayPath != null &&
                  _selectedPath != null &&
                  widget.config.enableCrop) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading ? null : _reCropImage,
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
    );
  }

  /// 确认选择
  void _confirmSelection(String path) {
    setState(() {
      _hasUnsavedChanges = false;
    });
    widget.onImageSelected(path);
  }

  /// 取消更改
  void _cancelChanges() {
    setState(() {
      _selectedPath = widget.initialImagePath;
      _croppedPath = null;
      _hasUnsavedChanges = false;
    });
  }

  Widget _buildPreview(String path, ThemeData theme) {
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
            Expanded(
              child: Center(
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: Image.file(
                    File(path),
                    width: 800,
                    height: 800 / widget.config.aspectRatio,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(12),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Row(
                children: [
                  Icon(
                    _croppedPath != null ? Icons.check_circle : Icons.info_outline,
                    size: 16,
                    color: _croppedPath != null
                        ? Colors.green
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _croppedPath != null
                          ? '已选择 (${widget.config.aspectRatioString})'
                          : '选择图片后可调整裁剪区域',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.add_photo_alternate,
            size: 80,
            color: theme.colorScheme.primary.withOpacity(0.3),
          ),
          const SizedBox(height: 16),
          Text(
            widget.emptyStateHint ?? '选择图片',
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.5),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.emptyStateSubHint ??
                (widget.config.enableCrop ? '可自由调整裁剪区域' : ''),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withOpacity(0.4),
            ),
          ),
        ],
      ),
    );
  }
}

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
      appBar: AppBar(
        title: Text(title),
        centerTitle: true,
      ),
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
