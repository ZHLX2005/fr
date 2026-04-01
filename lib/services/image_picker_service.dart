import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';

/// 图片选择和裁剪服务
/// 提供统一的 API 来选择和裁剪图片
class ImagePickerService {
  static ImagePickerService? _instance;
  final ImagePicker _picker = ImagePicker();

  factory ImagePickerService() {
    _instance ??= ImagePickerService._internal();
    return _instance!;
  }

  ImagePickerService._internal();

  /// 选择并裁剪图片
  ///
  /// [aspectRatio] 目标宽高比，默认为 16:9
  /// [cropTitle] 裁剪界面标题
  /// 返回裁剪后的图片本地文件路径，如果用户取消则返回 null
  Future<String?> pickAndCropImage({
    double aspectRatio = 16 / 9,
    String cropTitle = '裁剪图片',
    CropAspectRatioPreset aspectRatioPreset = CropAspectRatioPreset.original,
  }) async {
    // 1. 选择图片
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;

    try {
      // 2. 裁剪图片
      // 先设置状态栏为亮色（适配深色工具栏）
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
        ),
      );

      late CroppedFile? croppedFile;
      try {
        croppedFile = await ImageCropper().cropImage(
          sourcePath: image.path,
          aspectRatio: CropAspectRatio(
            ratioX: aspectRatio,
            ratioY: 1,
          ),
          uiSettings: [
            AndroidUiSettings(
              toolbarTitle: cropTitle,
              toolbarColor: Colors.blue,
              toolbarWidgetColor: Colors.white,
              initAspectRatio: aspectRatioPreset,
              lockAspectRatio: false,
              hideBottomControls: false,
              statusBarColor: Colors.transparent,
            ),
            IOSUiSettings(
              title: cropTitle,
              cancelButtonTitle: '取消',
              doneButtonTitle: '完成',
              aspectRatioLockEnabled: false,
            ),
          ],
        );
      } finally {
        // 恢复状态栏样式
        SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ));
      }

      if (croppedFile == null) {
        // 用户取消裁剪，使用原图
        return await _saveImage(image.path);
      }

      // 3. 保存裁剪后的图片
      return await _saveImage(croppedFile.path);
    } catch (e) {
      debugPrint('图片裁剪失败: $e');
      return null;
    }
  }

  /// 仅选择图片（不裁剪）
  Future<String?> pickImage() async {
    final image = await _picker.pickImage(source: ImageSource.gallery);
    if (image == null) return null;
    return await _saveImage(image.path);
  }

  /// 保存图片到应用目录
  Future<String?> _saveImage(String sourcePath) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final savedPath = '${dir.path}/$fileName';

      // 复制文件到应用目录
      final sourceFile = File(sourcePath);
      await sourceFile.copy(savedPath);

      // 尝试删除临时文件
      try {
        if (sourcePath != savedPath) {
          await sourceFile.delete();
        }
      } catch (_) {}

      return savedPath;
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }

  /// 从本地路径加载图片
  File? loadImage(String path) {
    try {
      final file = File(path);
      if (file.existsSync()) {
        return file;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}
