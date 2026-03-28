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

  // 相册列表
  List<AssetPathEntity> _albums = [];
  bool _isLoading = true;
  bool _hasPermission = false;

  // 当前选中的相册
  AssetPathEntity? _selectedAlbum;

  // 图片列表
  List<AssetEntity> _images = [];
  Map<String, Uint8List> _thumbnails = {};

  // 选中的图片（用于移动）
  final Set<AssetEntity> _selectedImages = {};
  bool _isSelectMode = false;

  @override
  void initState() {
    super.initState();
    _initGallery();
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

  Future<void> _loadImages(AssetPathEntity album) async {
    setState(() => _isLoading = true);

    final images = await _galleryService.getAssets(album: album, pageSize: 100);

    // 加载缩略图
    final thumbnails = <String, Uint8List>{};
    for (final image in images) {
      final thumb = await _galleryService.getThumbnail(image);
      if (thumb != null) {
        thumbnails[image.id] = thumb;
      }
    }

    setState(() {
      _images = images;
      _thumbnails = thumbnails.cast();
      _isLoading = false;
    });
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
      padding: const EdgeInsets.all(4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
      ),
      itemCount: _images.length,
      itemBuilder: (context, index) {
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
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('正在移动图片...'),
          ],
        ),
      ),
    );

    // TODO: 实现图片移动逻辑
    // 注意：由于系统限制，实际上是在目标相册创建图片副本
    // 然后删除原图

    await Future.delayed(const Duration(seconds: 1));

    if (mounted) {
      Navigator.pop(context); // 关闭加载对话框
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('图片移动功能开发中...')),
      );
    }

    _exitSelectMode();
  }

  void _previewImage(AssetEntity image) {
    // TODO: 实现图片预览
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('预览功能开发中: ${image.title}')),
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
