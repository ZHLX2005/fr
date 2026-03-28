import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import '../../core/services/gallery_service.dart';

/// 图库管理页面
/// 展示所有图片和相册分组，支持图片移动
class GalleryManagePage extends StatefulWidget {
  const GalleryManagePage({super.key});

  @override
  State<GalleryManagePage> createState() => _GalleryManagePageState();
}

class _GalleryManagePageState extends State<GalleryManagePage> {
  final GalleryService _galleryService = GalleryService();
  final ScrollController _scrollController = ScrollController();

  // 相册列表
  List<AssetPathEntity> _albums = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  // 当前选中的相册
  AssetPathEntity? _selectedAlbum;

  // 图片列表（分页）
  List<AssetEntity> _images = [];
  Map<String, Uint8List> _thumbnails = {};
  int _currentPage = 0;
  final int _pageSize = 60;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  // 选中的图片（用于移动）
  final Set<AssetEntity> _selectedImages = {};
  bool _isSelectMode = false;

  @override
  void initState() {
    super.initState();
    _initGallery();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isLoadingMore || !_hasMore) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;
    final delta = 200; // 距离底部200px时开始加载

    if (maxScroll - currentScroll < delta) {
      _loadMoreImages();
    }
  }

  Future<void> _initGallery() async {
    setState(() => _isLoading = true);

    // 请求权限
    final hasPermission = await _galleryService.checkPermission();
    if (!hasPermission) {
      setState(() {
        _isLoading = false;
        _hasPermission = false;
      });
      _showPermissionDialog();
      return;
    }

    setState(() => _hasPermission = true);

    // 加载相册
    await _loadAlbums();
  }

  Future<void> _loadAlbums() async {
    final albums = await _galleryService.getAlbums();
    setState(() {
      _albums = albums;
      _isLoading = false;
      // 默认选择第一个相册（通常是"最近添加"）
      if (albums.isNotEmpty && _selectedAlbum == null) {
        _selectedAlbum = albums.first;
        _loadImages(albums.first);
      }
    });
  }

  Future<void> _loadImages(AssetPathEntity album, {bool reset = true}) async {
    if (reset) {
      setState(() {
        _currentPage = 0;
        _hasMore = true;
        _images.clear();
        _thumbnails.clear();
        _isLoading = true;
      });
    } else {
      setState(() => _isLoadingMore = true);
    }

    final images = await _galleryService.getAssets(
      album: album,
      page: _currentPage,
      pageSize: _pageSize,
    );

    // 加载缩略图
    final thumbnails = <String, Uint8List>{};
    for (final image in images) {
      final thumb = await _galleryService.getThumbnail(image);
      if (thumb != null) {
        thumbnails[image.id] = thumb;
      }
    }

    setState(() {
      _images.addAll(images);
      _thumbnails.addAll(thumbnails);
      _hasMore = images.length >= _pageSize;
      _currentPage++;
      _isLoading = false;
      _isLoadingMore = false;
    });
  }

  Future<void> _loadMoreImages() async {
    if (_selectedAlbum == null || _isLoadingMore || !_hasMore) return;
    await _loadImages(_selectedAlbum!, reset: false);
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('需要图库权限'),
        content: const Text(
          '请授予图库访问权限以查看和管理您的图片。\n\n'
          '您可以在设置中手动开启权限后重试。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _initGallery();
            },
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('图库管理'),
        actions: [
          if (_isSelectMode)
            TextButton.icon(
              onPressed: _selectedImages.isEmpty ? null : _showMoveDialog,
              icon: const Icon(Icons.drive_file_move),
              label: const Text('移动'),
            ),
          if (_isSelectMode)
            TextButton.icon(
              onPressed: _exitSelectMode,
              icon: const Icon(Icons.close),
              label: const Text('取消'),
            )
          else
            IconButton(
              icon: const Icon(Icons.check_circle_outline),
              onPressed: _enterSelectMode,
              tooltip: '选择图片',
            ),
        ],
      ),
      body: _hasPermission
          ? Column(
              children: [
                // 相册选择器
                _buildAlbumSelector(theme),
                // 图片网格
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _images.isEmpty
                          ? _buildEmptyState()
                          : _buildImageGrid(theme),
                ),
                // 选择状态栏
                if (_isSelectMode)
                  _buildSelectBar(theme),
              ],
            )
          : _buildPermissionRequired(),
    );
  }

  Widget _buildPermissionRequired() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          const Text('需要图库权限'),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _initGallery,
            child: const Text('请求权限'),
          ),
        ],
      ),
    );
  }

  Widget _buildAlbumSelector(ThemeData theme) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.folder_outlined),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButton<AssetPathEntity>(
              value: _selectedAlbum,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              hint: const Text('选择相册'),
              items: _albums.map((album) {
                return DropdownMenuItem<AssetPathEntity>(
                  value: album,
                  child: Row(
                    children: [
                      Expanded(child: Text(album.name)),
                      const SizedBox(width: 8),
                      FutureBuilder<int>(
                        future: _galleryService.getAssetCount(album),
                        builder: (context, count) {
                          return Text(
                            '${count.data ?? 0}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (album) async {
                if (album != null) {
                  setState(() => _selectedAlbum = album);
                  await _loadImages(album);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.photo_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '此相册为空',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildImageGrid(ThemeData theme) {
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _images.length + (_isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        // 显示加载更多指示器
        if (index == _images.length) {
          return Container(
            color: theme.colorScheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        final image = _images[index];
        final isSelected = _selectedImages.contains(image);
        final thumbnail = _thumbnails[image.id];

        return GestureDetector(
          onTap: () => _isSelectMode ? _toggleImageSelection(image) : _previewImage(image),
          onLongPress: () {
            if (!_isSelectMode) {
              _enterSelectMode();
              _toggleImageSelection(image);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Container(
                decoration: BoxDecoration(
                  border: Border.all(
                    color: isSelected ? theme.colorScheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: thumbnail != null
                    ? Image.memory(
                        thumbnail,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        color: theme.colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
              ),
              if (isSelected)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSelectBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Text(
            '已选择 ${_selectedImages.length} 张图片',
            style: theme.textTheme.titleSmall,
          ),
          const Spacer(),
          TextButton(
            onPressed: _selectedImages.isEmpty ? null : _selectAll,
            child: const Text('全选'),
          ),
        ],
      ),
    );
  }

  void _toggleImageSelection(AssetEntity image) {
    setState(() {
      if (_selectedImages.contains(image)) {
        _selectedImages.remove(image);
      } else {
        _selectedImages.add(image);
      }
    });
  }

  void _enterSelectMode() {
    setState(() => _isSelectMode = true);
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedImages.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedImages.clear();
      _selectedImages.addAll(_images);
    });
  }

  void _showMoveDialog() {
    showDialog(
      context: context,
      builder: (context) => _MoveImageDialog(
        albums: _albums,
        currentAlbum: _selectedAlbum,
        onMove: (targetAlbum) => _moveImages(targetAlbum),
      ),
    );
  }

  Future<void> _moveImages(AssetPathEntity targetAlbum) async {
    Navigator.pop(context);

    // 显示加载对话框
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在移动 ${_selectedImages.length} 张图片...'),
            const SizedBox(height: 8),
            Text(
              '目标: ${targetAlbum.name}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );

    int successCount = 0;
    int failCount = 0;
    final List<String> errorMessages = [];

    try {
      // 逐个移动图片
      for (final image in _selectedImages) {
        try {
          debugPrint('开始移动图片: ${image.title} 到 ${targetAlbum.name}');

          // 获取原图数据并保存到目标相册
          final bytes = await image.originBytes;
          if (bytes == null) {
            debugPrint('无法读取图片数据: ${image.title}');
            failCount++;
            errorMessages.add('${image.title}: 无法读取图片数据');
            continue;
          }

          final title = image.title ?? 'image_${DateTime.now().millisecondsSinceEpoch}';

          // 保存图片到系统图库（会进入"最近添加"）
          final result = await PhotoManager.editor.saveImage(
            bytes,
            title: title,
            filename: title,
          );

          if (result == null) {
            debugPrint('保存图片失败: ${image.title}');
            failCount++;
            errorMessages.add('${image.title}: 保存失败');
            continue;
          }

          debugPrint('图片已保存到图库: ${result.id}, 尝试添加到相册...');

          // 将图片添加到目标相册
          await PhotoManager.editor.copyAssetToPath(
            asset: result,
            pathEntity: targetAlbum,
          );

          // 删除原图
          await PhotoManager.editor.deleteWithIds([image.id]);

          successCount++;
          debugPrint('成功移动图片: ${image.title}');
        } catch (e) {
          debugPrint('移动单张图片失败: $e');
          failCount++;
          errorMessages.add('${image.title}: ${e.toString()}');
        }
      }
    } catch (e) {
      debugPrint('批量移动图片失败: $e');
    }

    if (mounted) {
      Navigator.pop(context); // 关闭加载对话框

      // 显示结果
      String message;
      if (failCount == 0) {
        message = '✅ 成功移动 $successCount 张图片到 ${targetAlbum.name}';
      } else if (successCount == 0) {
        message = '❌ 移动失败';
        if (errorMessages.isNotEmpty) {
          message += '\n${errorMessages.first}';
        }
      } else {
        message = '⚠️ 部分成功：$successCount 张成功，$failCount 张失败';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
          action: failCount > 0
              ? SnackBarAction(
                  label: '查看详情',
                  textColor: Theme.of(context).colorScheme.inverseSurface,
                  onPressed: () => _showMoveErrors(context, errorMessages),
                )
              : null,
        ),
      );

      // 重新加载当前相册
      if (_selectedAlbum != null) {
        await _loadImages(_selectedAlbum!, reset: true);
      }
    }

    _exitSelectMode();
  }

  void _showMoveErrors(BuildContext context, List<String> errors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移动错误详情'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: errors.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('• ${errors[index]}'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  void _previewImage(AssetEntity image) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => _ImagePreviewPage(image: image),
      ),
    );
  }
}

/// 移动图片对话框
class _MoveImageDialog extends StatefulWidget {
  final List<AssetPathEntity> albums;
  final AssetPathEntity? currentAlbum;
  final Future<void> Function(AssetPathEntity) onMove;

  const _MoveImageDialog({
    required this.albums,
    required this.currentAlbum,
    required this.onMove,
  });

  @override
  State<_MoveImageDialog> createState() => _MoveImageDialogState();
}

class _MoveImageDialogState extends State<_MoveImageDialog> {
  AssetPathEntity? _selectedAlbum;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('移动到...'),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: widget.albums.length,
          itemBuilder: (context, index) {
            final album = widget.albums[index];
            final isCurrent = widget.currentAlbum?.id == album.id;
            final isSelected = _selectedAlbum?.id == album.id;

            return ListTile(
              leading: const Icon(Icons.folder),
              title: Text(album.name),
              trailing: Text(
                isCurrent ? '当前' : '',
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                ),
              ),
              selected: isSelected,
              onTap: () {
                setState(() => _selectedAlbum = album);
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _selectedAlbum != null && _selectedAlbum != widget.currentAlbum
              ? () => widget.onMove(_selectedAlbum!)
              : null,
          child: const Text('移动'),
        ),
      ],
    );
  }
}

/// 图片预览页面（显示元信息）
class _ImagePreviewPage extends StatefulWidget {
  final AssetEntity image;

  const _ImagePreviewPage({required this.image});

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  Uint8List? _imageData;

  @override
  void initState() {
    super.initState();
    _loadImageData();
  }

  Future<void> _loadImageData() async {
    final data = await widget.image.originBytes;
    setState(() {
      _imageData = data;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final image = widget.image;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图片详情'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => _showMetadataSheet(context, theme, image),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _imageData != null
                  ? Image.memory(
                      _imageData!,
                      fit: BoxFit.contain,
                    )
                  : const CircularProgressIndicator(),
            ),
          ),
          _buildBasicInfo(theme, image),
        ],
      ),
    );
  }

  Widget _buildBasicInfo(ThemeData theme, AssetEntity image) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            image.title ?? '未知',
            style: theme.textTheme.titleMedium,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              _buildInfoChip(
                theme,
                Icons.photo_size_select_large,
                '${image.width}×${image.height}',
              ),
              _buildInfoChip(
                theme,
                Icons.access_time,
                _formatDate(image.createDateTime),
              ),
              if (image.latitude != null && image.longitude != null)
                _buildInfoChip(
                  theme,
                  Icons.location_on,
                  '${image.latitude!.toStringAsFixed(4)}, ${image.longitude!.toStringAsFixed(4)}',
                ),
              _buildInfoChip(
                theme,
                Icons.image,
                image.mimeType ?? 'image',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(ThemeData theme, IconData icon, String label) {
    return Chip(
      avatar: Icon(icon, size: 16),
      label: Text(label, style: theme.textTheme.bodySmall),
      visualDensity: VisualDensity.compact,
    );
  }

  void _showMetadataSheet(BuildContext context, ThemeData theme, AssetEntity image) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline),
                    const SizedBox(width: 8),
                    Text('图片元信息', style: theme.textTheme.titleMedium),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildMetadataSection('基本信息', [
                      _buildMetadataItem('文件名', image.title ?? '未知'),
                      _buildMetadataItem('ID', image.id),
                      _buildMetadataItem('类型', image.type.toString()),
                      _buildMetadataItem('MIME', image.mimeType ?? '未知'),
                      _buildMetadataItem('宽度', '${image.width} px'),
                      _buildMetadataItem('高度', '${image.height} px'),
                      _buildMetadataItem('方向', '${image.orientation}°'),
                    ]),
                    const SizedBox(height: 16),
                    _buildMetadataSection('时间信息', [
                      _buildMetadataItem('创建时间', _formatDate(image.createDateTime)),
                      _buildMetadataItem('修改时间', _formatDate(image.modifiedDateTime)),
                    ]),
                    const SizedBox(height: 16),
                    _buildMetadataSection('地理信息', [
                      _buildMetadataItem('纬度', image.latitude?.toStringAsFixed(8) ?? '无'),
                      _buildMetadataItem('经度', image.longitude?.toStringAsFixed(8) ?? '无'),
                    ]),
                    const SizedBox(height: 16),
                    _buildMetadataSection('相册信息', [
                      _buildMetadataItem('相对路径', image.relativePath ?? '未知'),
                      _buildMetadataItem('视频时长', image.type == AssetType.video ? '${image.duration} ms' : '不适用'),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetadataSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildMetadataItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
