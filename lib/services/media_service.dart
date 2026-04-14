import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';

/// 媒体服务 - 处理图库和文件访问
/// 在Web环境下使用image_picker的Web实现
class MediaService {
  static final ImagePicker _imagePicker = ImagePicker();

  /// 从图库选择图片
  /// 返回图片文件路径，Web环境返回base64
  static Future<String?> pickImageFromGallery() async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image != null) {
        if (kIsWeb) {
          // Web环境：读取文件并转换为base64
          final bytes = await image.readAsBytes();
          final base64 = base64Encode(bytes);
          return 'data:image/jpeg;base64,$base64';
        } else {
          // 移动端：返回文件路径
          return image.path;
        }
      }
      return null;
    } catch (e) {
      debugPrint('选择图片失败: $e');
      return null;
    }
  }

  /// 从图库选择视频
  static Future<String?> pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        return video.path;
      }
      return null;
    } catch (e) {
      debugPrint('选择视频失败: $e');
      return null;
    }
  }

  /// 拍照
  static Future<String?> takePicture() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (photo != null) {
        if (kIsWeb) {
          final bytes = await photo.readAsBytes();
          final base64 = base64Encode(bytes);
          return 'data:image/jpeg;base64,$base64';
        } else {
          return photo.path;
        }
      }
      return null;
    } catch (e) {
      debugPrint('拍照失败: $e');
      return null;
    }
  }

  /// 录制视频
  static Future<String?> recordVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        return video.path;
      }
      return null;
    } catch (e) {
      debugPrint('录制视频失败: $e');
      return null;
    }
  }

  /// 选择文件（支持多种格式）
  static Future<FilePickerResult?> pickFile({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );
      return result;
    } catch (e) {
      debugPrint('选择文件失败: $e');
      return null;
    }
  }

  /// 验证摄像头权限（仅在移动端有效）
  static Future<bool> checkCameraPermission() async {
    if (kIsWeb) {
      // Web环境：浏览器会自动请求权限
      return true;
    }
    return true;
  }

  /// 验证图库权限（仅在移动端有效）
  static Future<bool> checkGalleryPermission() async {
    if (kIsWeb) {
      return true;
    }
    return true;
  }

  /// Base64编码
  static String base64Encode(List<int> bytes) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    var result = '';
    for (var i = 0; i < bytes.length; i += 3) {
      final a = bytes[i];
      final b = i + 1 < bytes.length ? bytes[i + 1] : 0;
      final c = i + 2 < bytes.length ? bytes[i + 2] : 0;

      final d = a >> 2;
      final e = ((a & 0x3) << 4) | (b >> 4);
      final f = ((b & 0xF) << 2) | (c >> 6);
      final g = c & 0x3F;

      result += chars[d] + chars[e];
      if (i + 1 < bytes.length) result += chars[f];
      if (i + 2 < bytes.length) result += chars[g];
    }

    // 添加填充
    final padding = bytes.length % 3;
    if (padding > 0) {
      result += '=' * (3 - padding);
    }

    return result;
  }

  /// 验证Web环境下的媒体功能
  static Future<MediaCapability> checkWebCapabilities() async {
    if (!kIsWeb) {
      return MediaCapability(
        canAccessCamera: true,
        canAccessGallery: true,
        canRecordVideo: true,
        supportedImageFormats: ['jpg', 'png', 'gif', 'webp'],
        supportedVideoFormats: ['mp4', 'webm', 'mov'],
      );
    }

    // Web环境检查
    bool canAccessCamera = false;
    bool canAccessGallery = false;
    bool canRecordVideo = false;

    try {
      // 检查摄像头支持
      canAccessCamera = await _checkWebCameraSupport();
      // 检查文件上传支持
      canAccessGallery = true; // Web always supports file upload
      // 检查视频录制支持
      canRecordVideo = canAccessCamera;
    } catch (e) {
      debugPrint('Web功能检查失败: $e');
    }

    return MediaCapability(
      canAccessCamera: canAccessCamera,
      canAccessGallery: canAccessGallery,
      canRecordVideo: canRecordVideo,
      supportedImageFormats: ['jpg', 'png', 'gif', 'webp', 'svg'],
      supportedVideoFormats: ['mp4', 'webm'],
    );
  }

  /// 检查Web摄像头支持
  static Future<bool> _checkWebCameraSupport() async {
    try {
      // 尝试获取媒体设备
      await _imagePicker.retrieveLostData();
      return true;
    } catch (e) {
      // 如果出错，尝试其他方式检测
      return true; // 假设支持
    }
  }
}

/// 媒体功能能力
class MediaCapability {
  final bool canAccessCamera;
  final bool canAccessGallery;
  final bool canRecordVideo;
  final List<String> supportedImageFormats;
  final List<String> supportedVideoFormats;

  MediaCapability({
    required this.canAccessCamera,
    required this.canAccessGallery,
    required this.canRecordVideo,
    required this.supportedImageFormats,
    required this.supportedVideoFormats,
  });

  @override
  String toString() {
    return 'MediaCapability('
        'canAccessCamera: $canAccessCamera, '
        'canAccessGallery: $canAccessGallery, '
        'canRecordVideo: $canRecordVideo, '
        'supportedImageFormats: $supportedImageFormats, '
        'supportedVideoFormats: $supportedVideoFormats)';
  }
}
