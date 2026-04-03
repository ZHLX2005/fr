import 'package:flutter/material.dart';
import '../../core/storage/storage_manager.dart';
import '../lab_container.dart';

// Re-export for external use
export '../../core/storage/storage_manager.dart' show StorageInfo;

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

class _StorageAnalyzePageState extends State<_StorageAnalyzePage> {
  final StorageManager _storage = StorageManager.instance;
  List<StorageInfo> _storageList = [];
  Map<String, List<KeyInfo>> _keyDetails = {};
  bool _isLoading = true;
  bool _showKeys = false;

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);

    try {
      await _storage.init();
      final list = await _storage.getAllStorageInfo();

      // 加载每个存储的键详情
      final keyDetails = <String, List<KeyInfo>>{};
      for (final info in list) {
        final keys = await _storage.getKeys(info.type, boxName: info.type == StorageType.hive ? info.name : null);
        final keyInfos = <KeyInfo>[];
        for (final key in keys) {
          final value = await _storage.getValue(info.type, key, boxName: info.type == StorageType.hive ? info.name : null);
          keyInfos.add(KeyInfo(
            key: key,
            value: value?.toString() ?? 'null',
            size: (value?.toString().length ?? 0),
          ));
        }
        keyInfos.sort((a, b) => b.size.compareTo(a.size));
        keyDetails[info.name] = keyInfos;
      }

      setState(() {
        _storageList = list;
        _keyDetails = keyDetails;
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
              ],
            ),
          ),
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
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => setState(() => _showKeys = !_showKeys),
                    icon: Icon(_showKeys ? Icons.list : Icons.vpn_key, size: 18),
                    label: Text(_showKeys ? '隐藏详情' : '显示详情'),
                  ),
                ),
              ],
            ),
          ),
          // 存储列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _storageList.isEmpty
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
                          return _StorageCard(
                            info: info,
                            showKeys: _showKeys,
                            keys: _keyDetails[info.name] ?? [],
                            formatSize: _formatSize,
                            getSizeColor: _getSizeColor,
                            onDeleteKey: (key) => _deleteKey(info, key),
                            onClear: () => _clearStorage(info),
                            onDeleteBox: () => _deleteBox(info),
                          );
                        },
                      ),
          ),
        ],
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
      final success = await _storage.delete(
        info.type,
        key,
        boxName: info.type == StorageType.hive ? info.name : null,
      );

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
      final success = await _storage.clear(
        info.type,
        boxName: info.type == StorageType.hive ? info.name : null,
      );

      if (success) {
        await _loadStorageData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已清空: ${info.displayName}')),
          );
        }
      }
    }
  }

  Future<void> _deleteBox(StorageInfo info) async {
    if (info.type != StorageType.hive) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除整个 "${info.displayName}" 数据箱吗？此操作不可恢复。'),
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
      final success = await _storage.deleteBox(info.name);

      if (success) {
        await _loadStorageData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除: ${info.displayName}')),
          );
        }
      }
    }
  }
}

// KeyInfo is internal to this demo
class KeyInfo {
  final String key;
  final String value;
  final int size;

  const KeyInfo({
    required this.key,
    required this.value,
    required this.size,
  });
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
  final bool showKeys;
  final List<KeyInfo> keys;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;
  final void Function(String) onDeleteKey;
  final VoidCallback onClear;
  final VoidCallback onDeleteBox;

  const _StorageCard({
    required this.info,
    required this.showKeys,
    required this.keys,
    required this.formatSize,
    required this.getSizeColor,
    required this.onDeleteKey,
    required this.onClear,
    required this.onDeleteBox,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // 头部
          InkWell(
            onTap: () {
              // 展开/折叠
            },
            child: Padding(
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
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.cleaning_services, size: 20),
                            onPressed: onClear,
                            tooltip: '清空',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                          if (info.type == StorageType.hive)
                            IconButton(
                              icon: const Icon(Icons.delete_forever, size: 20, color: Colors.red),
                              onPressed: onDeleteBox,
                              tooltip: '删除整个数据箱',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                            ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 键详情
          if (showKeys && keys.isNotEmpty) ...[
            const Divider(height: 1),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: keys.length,
                itemBuilder: (context, index) {
                  final keyInfo = keys[index];
                  return ListTile(
                    dense: true,
                    title: Text(
                      keyInfo.key,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    subtitle: Text(
                      keyInfo.value.length > 50
                          ? '${keyInfo.value.substring(0, 50)}...'
                          : keyInfo.value,
                      style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          formatSize(keyInfo.size),
                          style: TextStyle(fontSize: 10, color: getSizeColor(keyInfo.size)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, size: 16),
                          onPressed: () => onDeleteKey(keyInfo.key),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        ),
                      ],
                    ),
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

void registerStorageAnalyzeDemo() {
  demoRegistry.register(StorageAnalyzeDemo());
}
