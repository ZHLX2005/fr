import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// 图库管理服务
/// 负责访问和管理设备图库
class GalleryService {
  /// 检查并请求图库权限
  Future<bool> checkPermission() async {
    if (kIsWeb) return false;

    try {
      final PermissionState state = await PhotoManager.requestPermissionExtend();
      return state.isAuth;
    } catch (e) {
      debugPrint('请求权限失败: $e');
      return false;
    }
  }

  /// 获取所有相册/文件夹
  Future<List<AssetPathEntity>> getAlbums({
    RequestType type = RequestType.image,
  }) async {
    try {
      final List<AssetPathEntity> albums = await PhotoManager.getAssetPathList(
        type: type,
      );
      return albums;
    } catch (e) {
      debugPrint('获取相册失败: $e');
      return [];
    }
  }

  /// 获取指定相册中的图片
  Future<List<AssetEntity>> getAssets({
    required AssetPathEntity album,
    int page = 0,
    int pageSize = 60,
  }) async {
    try {
      final assets = await album.getAssetListRange(
        start: page * pageSize,
        end: (page + 1) * pageSize,
      );
      return assets;
    } catch (e) {
      debugPrint('获取图片失败: $e');
      return [];
    }
  }

  /// 获取所有图片（跨相册）
  Future<List<AssetEntity>> getAllAssets({
    int page = 0,
    int pageSize = 100,
  }) async {
    try {
      final assets = await PhotoManager.getAssetPathList(
        type: RequestType.image,
      );
      if (assets.isEmpty) return [];

      final recentAlbum = assets.first;
      return await recentAlbum.getAssetListRange(
        start: page * pageSize,
        end: (page + 1) * pageSize,
      );
    } catch (e) {
      debugPrint('获取所有图片失败: $e');
      return [];
    }
  }

  /// 获取图片缩略图数据
  Future<Uint8List?> getThumbnail(AssetEntity asset, {int size = 200}) async {
    try {
      final thumb = await asset.thumbnailDataWithSize(
        const ThumbnailSize(200, 200),
        quality: 80,
      );
      return thumb;
    } catch (e) {
      debugPrint('获取缩略图失败: $e');
      return null;
    }
  }

  /// 获取图片原始文件
  Future<File?> getImageFile(AssetEntity asset) async {
    try {
      final file = await asset.file;
      return file;
    } catch (e) {
      debugPrint('获取图片文件失败: $e');
      return null;
    }
  }

  /// 获取图片元数据
  Future<AssetEntity?> getAssetById(String id) async {
    try {
      final asset = await AssetEntity.fromId(id);
      return asset;
    } catch (e) {
      debugPrint('获取图片元数据失败: $e');
      return null;
    }
  }

  /// 获取指定相册的图片数量
  Future<int> getAssetCount(AssetPathEntity album) async {
    try {
      return await album.assetCountAsync;
    } catch (e) {
      debugPrint('获取图片数量失败: $e');
      return 0;
    }
  }

  /// 清除缓存
  Future<void> clearCache() async {
    try {
      await PhotoManager.clearFileCache();
    } catch (e) {
      debugPrint('清除缓存失败: $e');
    }
  }

  /// 复制图片到指定相册
  /// 通过读取原图数据后保存到目标相册实现
  Future<bool> copyImageToAlbum({
    required AssetEntity sourceImage,
    required AssetPathEntity targetAlbum,
  }) async {
    try {
      // 获取原图数据
      final bytes = await sourceImage.originBytes;
      if (bytes == null) {
        debugPrint('无法读取图片数据');
        return false;
      }

      // 获取原图标题
      final title = sourceImage.title ?? 'image_${DateTime.now().millisecondsSinceEpoch}';

      // 保存到目标相册
      final result = await PhotoManager.editor.saveImage(
        bytes,
        title: title,
        filename: title,
      );

      // 将图片添加到目标相册
      if (result != null) {
        // 检查是否需要将图片添加到指定相册
        // saveImage 默认保存到"最近添加"，需要额外处理
        await PhotoManager.editor.copyAssetToPath(
          asset: result,
          pathEntity: targetAlbum,
        );
      }

      return result != null;
    } catch (e) {
      debugPrint('复制图片失败: $e');
      return false;
    }
  }

  /// 移动图片到指定相册（复制后删除原图）
  Future<bool> moveImageToAlbum({
    required AssetEntity sourceImage,
    required AssetPathEntity targetAlbum,
  }) async {
    try {
      // 先复制到目标相册
      final copied = await copyImageToAlbum(
        sourceImage: sourceImage,
        targetAlbum: targetAlbum,
      );

      if (copied) {
        // 删除原图
        await deleteAsset(sourceImage);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('移动图片失败: $e');
      return false;
    }
  }

  /// 删除图片
  Future<bool> deleteAsset(AssetEntity asset) async {
    try {
      await PhotoManager.editor.deleteWithIds([asset.id]);
      return true;
    } catch (e) {
      debugPrint('删除图片失败: $e');
      return false;
    }
  }

  /// 保存图片（从文件路径）
  Future<AssetEntity?> saveImage(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return null;

      final bytes = await file.readAsBytes();
      final filename = imagePath.split('/').last;

      final entity = await PhotoManager.editor.saveImage(
        bytes,
        title: filename,
        filename: filename,
      );
      return entity;
    } catch (e) {
      debugPrint('保存图片失败: $e');
      return null;
    }
  }
}
