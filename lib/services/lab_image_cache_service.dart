import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

// 忽略 depend_on_referenced_packages 警告，path 是正确的依赖
// ignore: depend_on_referenced_packages

/// Lab 卡片图片缓存服务
/// 优化大图片加载性能，自动生成和缓存缩略图
class LabImageCacheService {
  static LabImageCacheService? _instance;

  factory LabImageCacheService() {
    _instance ??= LabImageCacheService._internal();
    return _instance!;
  }

  LabImageCacheService._internal();

  Directory? _cacheDir;
  final Map<String, Uint8List> _memoryCache = {};
  bool _isWeb = false;
  bool _initialized = false;

  /// 初始化缓存目录
  Future<void> init() async {
    // 防止重复初始化
    if (_initialized) return;
    _initialized = true;

    // 检测是否为 Web 平台
    try {
      _isWeb = kIsWeb || Platform.environment.containsKey('FLUTTER_TEST');
    } catch (e) {
      _isWeb = true;
    }

    // Web 平台不支持磁盘缓存
    if (_isWeb) return;

    try {
      final tempDir = await getTemporaryDirectory();
      _cacheDir = Directory('${tempDir.path}/lab_thumbnails');
      if (!await _cacheDir!.exists()) {
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('初始化缓存失败: $e');
    }
  }

  /// 获取缩略图字节数据（优先从缓存）
  Future<Uint8List?> getThumbnailBytes(String imagePath) async {
    // Web 平台不支持磁盘缓存，直接返回
    if (_isWeb) return null;

    // 1. 检查内存缓存
    if (_memoryCache.containsKey(imagePath)) {
      return _memoryCache[imagePath];
    }

    // 2. 直接从磁盘查找缩略图文件（不依赖内存 map）
    final thumbnailPath = _getCacheFilename(imagePath);
    try {
      final file = File('${_cacheDir!.path}/$thumbnailPath');
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        // 装载到内存缓存
        if (_memoryCache.length < 20) {
          _memoryCache[imagePath] = bytes;
        }
        return bytes;
      }
    } catch (e) {
      debugPrint('读取缩略图失败: $e');
    }

    // 3. 生成缩略图并缓存
    return await _generateThumbnail(imagePath);
  }

  /// 清除所有缓存
  Future<void> clearCache() async {
    _memoryCache.clear();

    if (_isWeb) return;

    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
        await _cacheDir!.create(recursive: true);
      }
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }

  /// 预加载图片缩略图
  Future<void> preload(List<String> imagePaths) async {
    for (final imagePath in imagePaths) {
      await getThumbnailBytes(imagePath);
    }
  }

  /// 生成缩略图
  Future<Uint8List?> _generateThumbnail(String imagePath) async {
    if (_isWeb) return null;

    try {
      // 读取原图
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final originalBytes = await file.readAsBytes();

      // 如果图片已经很小，直接使用
      if (originalBytes.length < 500 * 1024) {
        // 小于500KB直接缓存
        await _saveThumbnail(imagePath, originalBytes);
        if (_memoryCache.length < 20) {
          _memoryCache[imagePath] = originalBytes;
        }
        return originalBytes;
      }

      // 对于大图片，使用简化处理
      final compressedBytes = await _compressImage(originalBytes);

      // 保存缩略图
      await _saveThumbnail(imagePath, compressedBytes);

      // 装载到内存
      if (_memoryCache.length < 20) {
        _memoryCache[imagePath] = compressedBytes;
      }

      return compressedBytes;
    } catch (e) {
      debugPrint('生成缩略图失败: $e');
      return null;
    }
  }

  /// 保存缩略图到磁盘
  Future<String> _saveThumbnail(String originalPath, Uint8List bytes) async {
    final filename = _getCacheFilename(originalPath);
    final file = File('${_cacheDir!.path}/$filename');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// 生成缓存文件名
  String _getCacheFilename(String imagePath) {
    final basename = path.basename(imagePath);
    final hash = imagePath.hashCode.abs();
    return '${hash}_$basename';
  }

  /// 简单的图片压缩
  Future<Uint8List> _compressImage(Uint8List bytes) async {
    // 简单策略：如果数据太大，进行采样
    if (bytes.length > 2 * 1024 * 1024) {
      // 超过2MB，进行简单采样
      const skip = 4; // 每4个字节取1个
      final sampled = Uint8List(bytes.length ~/ skip);
      for (int i = 0; i < sampled.length; i++) {
        sampled[i] = bytes[i * skip];
      }
      return sampled;
    }
    return bytes;
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    if (_isWeb) return 0;
    if (_cacheDir == null || !await _cacheDir!.exists()) return 0;

    try {
      int size = 0;
      await for (final entity in _cacheDir!.list(recursive: true)) {
        if (entity is File) {
          size += await entity.length();
        }
      }
      return size;
    } catch (e) {
      debugPrint('获取缓存大小失败: $e');
      return 0;
    }
  }
}
