import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// 图库管理服务
/// 负责访问和管理设备图库
class GalleryService {
  /// 申请 / 查询相册权限，返回原始 [PermissionState]。
  ///
  /// 只申请**图片**读权限：`RequestType.image` + `mediaLocation: false`，
  /// 不借机要视频和地理位置（Android 13+ 对应 READ_MEDIA_IMAGES）。
  /// 「有限访问」（iOS limited / Android 部分授权）也算有权限，否则
  /// 用户只授权几张图时会看到空白页却不知道原因。
  Future<PermissionState?> ensurePermission({bool request = true}) async {
    if (kIsWeb) return null;
    try {
      return request
          ? await PhotoManager.requestPermissionExtend(
              requestOption: const PermissionRequestOption(
                androidPermission: AndroidPermission(
                  type: RequestType.image,
                  mediaLocation: false,
                ),
              ),
            )
          : await PhotoManager.getPermissionState(
              requestOption: const PermissionRequestOption(
                androidPermission: AndroidPermission(
                  type: RequestType.image,
                  mediaLocation: false,
                ),
              ),
            );
    } catch (e) {
      debugPrint('请求权限失败: $e');
      return null;
    }
  }

  /// 检查并请求图库权限（含有限访问）。
  Future<bool> checkPermission() async {
    final state = await ensurePermission();
    return state?.hasAccess ?? false;
  }

  /// 跳到系统设置页（权限被永久拒绝时唯一的出路）。
  Future<void> openSettings() async {
    try {
      await PhotoManager.openSetting();
    } catch (e) {
      debugPrint('打开系统设置失败: $e');
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

  /// 取最新的 [limit] 张图片（全局相册，按创建时间倒序）。
  ///
  /// 之前用的是「`getAssetPathList()` 的第一个相册 + `getAssetListRange`」，
  /// 有两个坑：
  /// 1. 第一个相册不一定是「最近项目 / 相机胶卷」，某些机型会先返回
  ///    Screenshots 或某个自建相册，于是"最新 X 张"拿到的是一堆旧图；
  /// 2. 相册自身的排序取决于系统设置，不保证倒序。
  /// 现在显式用 `onlyAll: true` 拿全局相册，并显式下发 createDate 倒序的
  /// [FilterOptionGroup]，本地再排一次序兜底（某些 ROM 忽略 filterOption）。
  Future<List<AssetEntity>> getLatestImages({required int limit}) async {
    if (limit <= 0) return const [];
    try {
      final filter = FilterOptionGroup(
        orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
      );
      var albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: filter,
      );
      if (albums.isEmpty) {
        // 极少数 ROM 不支持 onlyAll，退回完整列表（依旧靠下方 sort 兜底）
        albums = await PhotoManager.getAssetPathList(
          type: RequestType.image,
          filterOption: filter,
        );
      }
      if (albums.isEmpty) return const [];

      final latest = await albums.first.getAssetListPaged(page: 0, size: limit);
      final sorted = [...latest]
        ..sort((a, b) => b.createDateTime.compareTo(a.createDateTime));
      return sorted.length > limit ? sorted.sublist(0, limit) : sorted;
    } catch (e) {
      debugPrint('获取最新图片失败: $e');
      return [];
    }
  }

  /// 获取所有图片（跨相册，最新的在前）。
  ///
  /// 保留旧签名给既有调用方；[page] > 0 时才走分页向后取。
  Future<List<AssetEntity>> getAllAssets({
    int page = 0,
    int pageSize = 100,
  }) async {
    if (page == 0) return getLatestImages(limit: pageSize);
    try {
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
        filterOption: FilterOptionGroup(
          orders: const [OrderOption(type: OrderOptionType.createDate, asc: false)],
        ),
      );
      if (albums.isEmpty) return [];
      return await albums.first.getAssetListPaged(page: page, size: pageSize);
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
      final title =
          sourceImage.title ?? 'image_${DateTime.now().millisecondsSinceEpoch}';

      // 保存到目标相册
      final result = await PhotoManager.editor.saveImage(
        bytes,
        title: title,
        filename: title,
      );

      // 将图片添加到目标相册
      // ignore: unnecessary_null_comparison
      if (result != null) {
        // 检查是否需要将图片添加到指定相册
        // saveImage 默认保存到"最近添加"，需要额外处理
        await PhotoManager.editor.copyAssetToPath(
          asset: result,
          pathEntity: targetAlbum,
        );
      }

      // ignore: unnecessary_null_comparison
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
    final deleted = await deleteAssets([asset.id]);
    return deleted.contains(asset.id);
  }

  /// 批量删除图片，返回系统确认真正删掉的 id。
  ///
  /// Android 11+ / iOS 会先弹系统自己的删除确认框，用户点取消时返回空列表
  /// —— 调用方必须按返回值处理，不能假定成功。
  Future<List<String>> deleteAssets(List<String> ids) async {
    if (ids.isEmpty) return const [];
    try {
      return await PhotoManager.editor.deleteWithIds(ids);
    } catch (e) {
      debugPrint('删除图片失败: $e');
      return const [];
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
