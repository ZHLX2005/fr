import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/storage/storage_manager.dart';
import '../lab_container.dart';

/// 存储分析 Demo
class StorageAnalyzeDemo extends DemoPage {
  @override
  String get title => '存储分析';

  @override
  String get description => '管理应用本地存储，清理缓存数据';

  @override
  Widget buildPage(BuildContext context) {
    return const _StorageAnalyzePage();
  }
}

class _StorageAnalyzePage extends StatefulWidget {
  const _StorageAnalyzePage();

  @override
  State<_StorageAnalyzePage> createState() => _StorageAnalyzePageState();
}

class _StorageAnalyzePageState extends State<_StorageAnalyzePage>
    with SingleTickerProviderStateMixin {
  final StorageManager _storage = StorageManager.instance;
  List<StorageInfo> _storageList = [];
  Map<String, List<KeyDetail>> _keyDetails = {};
  List<FileItem> _mediaFiles = [];
  bool _isLoading = true;
  late TabController _tabController;

  // 多媒体文件扩展名
  static const _mediaExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp',
    'mp4', 'mov', 'avi', 'mkv', 'webm',
    'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadStorageData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);

    try {
      await _storage.init();
      final list = await _storage.getAllStorageInfo();

      // 加载每个存储的键详情
      final keyDetails = <String, List<KeyDetail>>{};
      for (final info in list) {
        final details = await _storage.getKeyDetails(info.type);
        keyDetails[info.name] = details;
      }

      // 扫描多媒体文件
      final mediaFiles = await _scanMediaFiles();

      setState(() {
        _storageList = list;
        _keyDetails = keyDetails;
        _mediaFiles = mediaFiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败: $e')),
        );
      }
    }
  }

  Future<List<FileItem>> _scanMediaFiles() async {
    final List<FileItem> files = [];

    try {
      final tempDir = await getTemporaryDirectory();
      await _scanDirectory(tempDir, files);

      final docDir = await getApplicationDocumentsDirectory();
      await _scanDirectory(docDir, files);
    } catch (e) {
      debugPrint('扫描文件目录失败: $e');
    }

    files.sort((a, b) => b.size.compareTo(a.size));
    return files;
  }

  Future<void> _scanDirectory(Directory dir, List<FileItem> files) async {
    try {
      if (!await dir.exists()) return;

      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (_mediaExtensions.contains(ext)) {
            try {
              final size = await entity.length();
              files.add(FileItem(
                path: entity.path,
                name: entity.path.split(Platform.pathSeparator).last,
                size: size,
                type: _getMediaType(ext),
              ));
            } catch (e) {
              // 忽略
            }
          }
        }
      }
    } catch (e) {
      debugPrint('扫描目录失败: $dir, $e');
    }
  }

  String _getMediaType(String ext) {
    const images = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'};
    const videos = {'mp4', 'mov', 'avi', 'mkv', 'webm'};
    const audios = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'flac'};

    if (images.contains(ext)) return '图片';
    if (videos.contains(ext)) return '视频';
    if (audios.contains(ext)) return '音频';
    return '文件';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Color _getSizeColor(int size) {
    if (size < 1024) return Colors.green;
    if (size < 10 * 1024) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Column(
        children: [
          // 顶部统计
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: '存储类型',
                  value: '${_storageList.length}',
                  icon: Icons.storage,
                ),
                _StatItem(
                  label: '总数据量',
                  value: _formatSize(_storageList.fold(0, (sum, info) => sum + info.size)),
                  icon: Icons.data_usage,
                ),
                _StatItem(
                  label: '媒体文件',
                  value: '${_mediaFiles.length}',
                  icon: Icons.folder,
                ),
              ],
            ),
          ),
          // Tab 栏
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '存储数据'),
              Tab(text: '多媒体文件'),
            ],
          ),
          // Tab 内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      // 存储数据
                      _buildStorageTab(),
                      // 多媒体文件
                      _buildMediaTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageTab() {
    return Column(
      children: [
        // 操作按钮
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _loadStorageData,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('刷新'),
                ),
              ),
            ],
          ),
        ),
        // 存储列表
        Expanded(
          child: _storageList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('暂无存储数据', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _storageList.length,
                  itemBuilder: (context, index) {
                    final info = _storageList[index];
                    final keys = _keyDetails[info.name] ?? [];
                    return _StorageCard(
                      info: info,
                      keys: keys,
                      formatSize: _formatSize,
                      getSizeColor: _getSizeColor,
                      onKeyTap: (detail) => _showKeyDetail(context, info, detail),
                      onDeleteKey: (key) => _deleteKey(info, key),
                      onClear: () => _clearStorage(info),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildMediaTab() {
    if (_mediaFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text('暂无多媒体文件', style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    final totalSize = _mediaFiles.fold(0, (sum, f) => sum + f.size);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('文件数: ${_mediaFiles.length}'),
              Text('总大小: ${_formatSize(totalSize)}'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _mediaFiles.length,
            itemBuilder: (context, index) {
              final file = _mediaFiles[index];
              return _MediaFileCard(
                file: file,
                formatSize: _formatSize,
                getSizeColor: _getSizeColor,
              );
            },
          ),
        ),
      ],
    );
  }

  void _showKeyDetail(BuildContext context, StorageInfo info, KeyDetail detail) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _KeyDetailSheet(
        info: info,
        detail: detail,
        formatSize: _formatSize,
        onDelete: () {
          Navigator.pop(context);
          _deleteKey(info, detail.key);
        },
      ),
    );
  }

  Future<void> _deleteKey(StorageInfo info, String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "$key" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await _storage.delete(info.type, key);

      if (success) {
        await _loadStorageData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: $key')),
          );
        }
      }
    }
  }

  Future<void> _clearStorage(StorageInfo info) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认清空'),
        content: Text('确定要清空 "${info.displayName}" 的所有数据吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      if (info.type == StorageType.hive) {
        await _storage.deleteAllHive();
      } else {
        await _storage.clear(info.type);
      }

      await _loadStorageData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已清空: ${info.displayName}')),
        );
      }
    }
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}

class _StorageCard extends StatelessWidget {
  final StorageInfo info;
  final List<KeyDetail> keys;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;
  final void Function(KeyDetail) onKeyTap;
  final void Function(String) onDeleteKey;
  final VoidCallback onClear;

  const _StorageCard({
    required this.info,
    required this.keys,
    required this.formatSize,
    required this.getSizeColor,
    required this.onKeyTap,
    required this.onDeleteKey,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // 头部
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    info.type == StorageType.hive ? Icons.table_chart : Icons.settings,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        info.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              info.typeLabel,
                              style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${info.keyCount} 个键',
                            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      formatSize(info.size),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: getSizeColor(info.size),
                      ),
                    ),
                    const SizedBox(height: 4),
                    IconButton(
                      icon: const Icon(Icons.cleaning_services, size: 20),
                      onPressed: onClear,
                      tooltip: '清空',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 键列表
          if (keys.isNotEmpty) ...[
            const Divider(height: 1),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                physics: const ClampingScrollPhysics(),
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  final detail = keys[index];
                  return _KeyListTile(
                    detail: detail,
                    formatSize: formatSize,
                    getSizeColor: getSizeColor,
                    onTap: () => onKeyTap(detail),
                    onDelete: () => onDeleteKey(detail.key),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _KeyListTile extends StatelessWidget {
  final KeyDetail detail;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _KeyListTile({
    required this.detail,
    required this.formatSize,
    required this.getSizeColor,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            if (detail.isJson)
              Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Icon(Icons.data_object, size: 14, color: Colors.purple),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.key,
                    style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.value.length > 40
                        ? '${detail.value.substring(0, 40)}...'
                        : detail.value,
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatSize(detail.size),
              style: TextStyle(fontSize: 10, color: getSizeColor(detail.size)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 18),
              onPressed: onTap,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            ),
          ],
        ),
      ),
    );
  }
}

class _KeyDetailSheet extends StatelessWidget {
  final StorageInfo info;
  final KeyDetail detail;
  final String Function(int) formatSize;
  final VoidCallback onDelete;

  const _KeyDetailSheet({
    required this.info,
    required this.detail,
    required this.formatSize,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[400],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.key,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                info.displayName,
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                formatSize(detail.size),
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              if (detail.isJson) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'JSON',
                                    style: TextStyle(fontSize: 10, color: Colors.purple),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SelectableText(
                      detail.value,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(
                    top: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete),
                    label: const Text('删除此项'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MediaFileCard extends StatelessWidget {
  final FileItem file;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;

  const _MediaFileCard({
    required this.file,
    required this.formatSize,
    required this.getSizeColor,
  });

  IconData _getIcon() {
    switch (file.type) {
      case '图片':
        return Icons.image;
      case '视频':
        return Icons.videocam;
      case '音频':
        return Icons.audiotrack;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getColor() {
    switch (file.type) {
      case '图片':
        return Colors.green;
      case '视频':
        return Colors.red;
      case '音频':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_getIcon(), color: _getColor()),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.name,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    file.path,
                    style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatSize(file.size),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: getSizeColor(file.size),
                  ),
                ),
                Text(
                  file.type,
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class FileItem {
  final String path;
  final String name;
  final int size;
  final String type;

  const FileItem({
    required this.path,
    required this.name,
    required this.size,
    required this.type,
  });
}

void registerStorageAnalyzeDemo() {
  demoRegistry.register(StorageAnalyzeDemo());
}
