// Demo 封面图 —— Lab 卡片与游戏中心封面共用的图片加载件。
//
// 之前 DemoCard（demo_grid）与 GameArtwork（game_center）各有一份
// Image.file / Image.network + 错误兜底实现，且只有 DemoCard 走了缩略图缓存。
// 合并后两处行为对齐：本地图优先用 LabImageCacheService 的缩略图（大图列表
// 滚动不再解码原图），miss 时回退 Image.file；网络图直接 Image.network。
//
// 占位风格由使用方决定：
//   - Lab 卡片（surfaceFallback）：加载中/失败显示 surfaceContainerHighest 底，
//     失败附 broken_image 图标 —— 卡片没有别的底色，需要占位提示
//   - 游戏中心（transparentFallback: true）：加载中/失败显示透明 ——
//     下层本来就有专属渐变封面，露出渐变即是最佳兜底

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../services/lab_image_cache_service.dart';

class DemoCoverImage extends StatefulWidget {
  const DemoCoverImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.transparentFallback = false,
  });

  /// 本地绝对路径或 http(s) URL，非空。
  final String path;

  final BoxFit fit;

  /// true = 加载中/失败显示透明（下层自带底色时用）；
  /// false = 显示 surfaceContainerHighest 占位底。
  final bool transparentFallback;

  /// 与 LabCardProvider.isLocalFile 同一规则：判定 path 是否本地文件。
  static bool isLocalPath(String path) =>
      path.startsWith('/') || path.contains('applicationDocuments');

  @override
  State<DemoCoverImage> createState() => _DemoCoverImageState();
}

class _DemoCoverImageState extends State<DemoCoverImage> {
  final _cacheService = LabImageCacheService();
  Uint8List? _thumbnailBytes;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(covariant DemoCoverImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _thumbnailBytes = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (!DemoCoverImage.isLocalPath(widget.path)) return;
    final path = widget.path;
    await _cacheService.init();
    final bytes = await _cacheService.getThumbnailBytes(path);
    // 异步期间 path 可能已切换，丢弃过期结果
    if (bytes != null && mounted && widget.path == path) {
      setState(() => _thumbnailBytes = bytes);
    }
  }

  Widget _errorWidget(ThemeData theme) {
    if (widget.transparentFallback) return const SizedBox.shrink();
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.broken_image),
    );
  }

  Widget _loadingWidget(ThemeData theme) {
    if (widget.transparentFallback) return const SizedBox.shrink();
    return Container(color: theme.colorScheme.surfaceContainerHighest);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!DemoCoverImage.isLocalPath(widget.path)) {
      return Image.network(
        widget.path,
        fit: widget.fit,
        errorBuilder: (_, _, _) => _errorWidget(theme),
        loadingBuilder: (_, child, progress) =>
            progress == null ? child : _loadingWidget(theme),
      );
    }

    if (_thumbnailBytes != null) {
      return Image.memory(
        _thumbnailBytes!,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => _errorWidget(theme),
      );
    }

    return Image.file(
      File(widget.path),
      fit: widget.fit,
      gaplessPlayback: true,
      errorBuilder: (_, _, _) => _errorWidget(theme),
      frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
        if (wasSynchronouslyLoaded) return child;
        return AnimatedOpacity(
          opacity: frame == null ? 0 : 1,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          child: child,
        );
      },
    );
  }
}
