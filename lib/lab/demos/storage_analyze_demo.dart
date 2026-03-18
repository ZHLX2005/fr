import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../lab_container.dart';

/// 存储分析 Demo
class StorageAnalyzeDemo extends DemoPage {
  @override
  String get title => '存储分析';

  @override
  String get description => '分析应用本地存储占用情况';

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
  Map<String, StorageItem> _storageData = {};
  bool _isLoading = true;
  int _totalSize = 0;

  // 存储键到名称的映射
  static const Map<String, String> _keyLabels = {
    'users': '用户数据',
    'messages': '消息记录',
    'friends': '好友列表',
    'sessions': '会话列表',
    'current_user': '当前用户',
    'lab_clocks': '时钟数据',
    'lab_clock_records': '时钟记录',
    'lab_notes': '笔记数据',
  };

  @override
  void initState() {
    super.initState();
    _loadStorageData();
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final Map<String, StorageItem> data = {};
      int total = 0;

      for (final key in keys) {
        final value = prefs.get(key);
        if (value != null) {
          String displayValue;
          int itemCount = 0;
          int valueSize = 0;

          if (value is String) {
            valueSize = value.length;
            try {
              final decoded = jsonDecode(value);
              if (decoded is List) {
                itemCount = decoded.length;
                displayValue = '[$itemCount 项] ${_truncate(decoded.toString(), 100)}';
              } else if (decoded is Map) {
                itemCount = decoded.length;
                displayValue = '{$itemCount 项} ${_truncate(decoded.toString(), 100)}';
              } else {
                displayValue = _truncate(value, 150);
              }
            } catch (e) {
              displayValue = _truncate(value, 150);
            }
          } else {
            displayValue = value.toString();
            valueSize = displayValue.length;
          }

          total += valueSize;
          data[key] = StorageItem(
            key: key,
            value: displayValue,
            size: valueSize,
            itemCount: itemCount,
            type: value.runtimeType.toString(),
          );
        }
      }

      // 按大小排序
      final sortedKeys = data.keys.toList()
        ..sort((a, b) => data[b]!.size.compareTo(data[a]!.size));

      final sortedData = <String, StorageItem>{};
      for (final key in sortedKeys) {
        sortedData[key] = data[key]!;
      }

      setState(() {
        _storageData = sortedData;
        _totalSize = total;
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

  String _truncate(String str, int maxLength) {
    if (str.length <= maxLength) return str;
    return '${str.substring(0, maxLength)}...';
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
                  label: '存储键数量',
                  value: '${_storageData.length}',
                  icon: Icons.key,
                ),
                _StatItem(
                  label: '总占用空间',
                  value: _formatSize(_totalSize),
                  icon: Icons.storage,
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
                    onPressed: () => _showClearDialog(context),
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('清空存储'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 数据列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _storageData.isEmpty
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
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _storageData.length,
                        itemBuilder: (context, index) {
                          final item = _storageData.values.elementAt(index);
                          return _StorageItemCard(
                            item: item,
                            label: _keyLabels[item.key] ?? item.key,
                            formatSize: _formatSize,
                            getSizeColor: _getSizeColor,
                            onTap: () => _showDetailDialog(context, item),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  void _showDetailDialog(BuildContext context, StorageItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
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
                        child: Text(
                          _keyLabels[item.key] ?? item.key,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _DetailChip(label: '类型', value: item.type),
                      _DetailChip(label: '大小', value: _formatSize(item.size)),
                      _DetailChip(label: '项目数', value: '${item.itemCount}'),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      item.value,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showClearDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空存储'),
        content: const Text('确定要清空所有本地存储数据吗？此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final prefs = await SharedPreferences.getInstance();
              await prefs.clear();
              _loadStorageData();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('存储已清空')),
                );
              }
            },
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

class StorageItem {
  final String key;
  final String value;
  final int size;
  final int itemCount;
  final String type;

  StorageItem({
    required this.key,
    required this.value,
    required this.size,
    required this.itemCount,
    required this.type,
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

class _StorageItemCard extends StatelessWidget {
  final StorageItem item;
  final String label;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;
  final VoidCallback onTap;

  const _StorageItemCard({
    required this.item,
    required this.label,
    required this.formatSize,
    required this.getSizeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: getSizeColor(item.size).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _getIconForKey(item.key),
                  color: getSizeColor(item.size),
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.key,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    if (item.itemCount > 0)
                      Text(
                        '${item.itemCount} 项',
                        style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatSize(item.size),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: getSizeColor(item.size),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconForKey(String key) {
    if (key.contains('user')) return Icons.person;
    if (key.contains('message')) return Icons.message;
    if (key.contains('friend')) return Icons.people;
    if (key.contains('session')) return Icons.chat;
    if (key.contains('clock')) return Icons.timer;
    if (key.contains('note')) return Icons.note;
    return Icons.storage;
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;

  const _DetailChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }
}

void registerStorageAnalyzeDemo() {
  demoRegistry.register(StorageAnalyzeDemo());
}
