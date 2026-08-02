import 'dart:io';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:get_it/get_it.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../api/providers/api_providers.dart';
import '../../api/user/user_auth_service.dart';
import '../../core/storage/storage_manager.dart';
import '../../core/storage/sync/cloud_storage_sync.dart';
import '../../core/note/note_root_scope.dart';
import '../lab_container.dart';
import 'calendar/data/calendar_hive.dart';

/// 存储分析 Demo
class StorageAnalyzeDemo extends DemoPage {
  @override
  String get title => '存储分析';

  @override
  String get slug => 'storage-analyze';

  @override
  String get description => '管理应用本地存储，清理缓存数据';

  @override
  Widget buildPage(BuildContext context) {
    return const _StorageAnalyzePage();
  }
}

class _StorageAnalyzePage extends ConsumerStatefulWidget {
  const _StorageAnalyzePage();

  @override
  ConsumerState<_StorageAnalyzePage> createState() => _StorageAnalyzePageState();
}

class _StorageAnalyzePageState extends ConsumerState<_StorageAnalyzePage>
    with SingleTickerProviderStateMixin {
  final StorageManager _storage = StorageManager.instance;
  List<StorageInfo> _storageList = [];
  Map<String, List<KeyDetail>> _keyDetails = {};
  List<FileItem> _mediaFiles = [];
  bool _isLoading = true;
  late TabController _tabController;
  final Set<String> _expandedKeys = {};
  List<NoteInfo> _noteList = [];
  NoteSummary _noteSummary = const NoteSummary(noteCount: 0, totalBlocks: 0, totalSize: 0);

  // 应用配置 (SharedPreferences) —— 让 prefs 导入导出生效"看得见"
  List<MapEntry<String, Object?>> _prefsList = [];

  static const _mediaExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'mp4',
    'mov',
    'avi',
    'mkv',
    'webm',
    'mp3',
    'wav',
    'aac',
    'm4a',
    'ogg',
    'flac',
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadStorageData());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// 确保所有 typed Hive box 都注册了 adapter。
  ///
  /// main.dart 启动时只 init 了 timetable + body_records；calendar 是按需 init
  /// 的。如果用户没先进过日历 demo 就打开存储分析页，calendarEvents /
  /// calendarPeople 这类 typed box 不会进 StorageRegistry，面板看不到、导出也
  /// 拿不到（缺 adapter 时 Hive 读会抛）。所以在加载 / 导出 / 导入前统一兜底。
  Future<void> _ensureBoxesInitialized() async {
    await _storage.init().timeout(const Duration(seconds: 10));
    try {
      await CalendarHive.init();
    } catch (e) {
      debugPrint('CalendarHive.init 失败（忽略）: $e');
    }
  }

  Future<void> _loadStorageData() async {
    setState(() => _isLoading = true);

    try {
      await _ensureBoxesInitialized();
      final list = await _storage.getAllStorageInfo().timeout(const Duration(seconds: 10));

      final keyDetails = <String, List<KeyDetail>>{};
      for (final info in list) {
        // 关键：传 boxName 让 getKeyDetails 只返回该 box 的键
        // （否则 Hive 场景会把所有 box 的键都塞进当前 info.name，造成错乱）
        final details = info.type == StorageType.hive
            ? await _storage
                .getKeyDetails(info.type, boxName: info.name)
                .timeout(const Duration(seconds: 10))
            : await _storage
                .getKeyDetails(info.type)
                .timeout(const Duration(seconds: 10));
        keyDetails[info.name] = details;
      }

      final mediaFiles = await _scanMediaFiles();
      final noteRoot = NoteRootScope.of(context).noteRoot;
      final noteList = await noteRoot.listNotes().timeout(const Duration(seconds: 10));
      final noteSummary = await noteRoot.getNoteSummary().timeout(const Duration(seconds: 10));
      final prefsList = await _loadPrefs();

      setState(() {
        _storageList = list;
        _keyDetails = keyDetails;
        _mediaFiles = mediaFiles;
        _noteList = noteList;
        _noteSummary = noteSummary;
        _prefsList = prefsList;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('加载失败: $e')));
      }
    }
  }

  // ── SharedPreferences ────────────────────────────────

  Future<List<MapEntry<String, Object?>>> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getKeys().map((k) => MapEntry(k, prefs.get(k))).toList();
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  Future<void> _addPref() async {
    final added = await showDialog<_PrefEdit>(
      context: context,
      builder: (_) => const _PrefEditDialog(isNew: true),
    );
    if (added == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    switch (added.type) {
      case 'String':
        await prefs.setString(added.key, added.value);
        break;
      case 'int':
        await prefs.setInt(added.key, int.tryParse(added.value) ?? 0);
        break;
      case 'double':
        await prefs.setDouble(added.key, double.tryParse(added.value) ?? 0);
        break;
      case 'bool':
        await prefs.setBool(added.key, added.value == 'true');
        break;
      case 'List<String>':
        await prefs.setStringList(
          added.key,
          added.value.split(',').map((e) => e.trim()).toList(),
        );
        break;
    }
    final reloaded = await _loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefsList = reloaded;
    });
  }

  Future<void> _editPref(MapEntry<String, Object?> entry) async {
    final updated = await showDialog<_PrefEdit>(
      context: context,
      builder: (_) => _PrefEditDialog(
        isNew: false,
        initialKey: entry.key,
        initialType: entry.value.runtimeType.toString(),
        initialValue: entry.value?.toString() ?? '',
      ),
    );
    if (updated == null || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    // 类型可能变了，先删旧的
    await prefs.remove(entry.key);
    switch (updated.type) {
      case 'String':
        await prefs.setString(updated.key, updated.value);
        break;
      case 'int':
        await prefs.setInt(updated.key, int.tryParse(updated.value) ?? 0);
        break;
      case 'double':
        await prefs.setDouble(updated.key, double.tryParse(updated.value) ?? 0);
        break;
      case 'bool':
        await prefs.setBool(updated.key, updated.value == 'true');
        break;
      case 'List<String>':
        await prefs.setStringList(
          updated.key,
          updated.value.split(',').map((e) => e.trim()).toList(),
        );
        break;
    }
    final reloaded = await _loadPrefs();
    if (!mounted) return;
    setState(() {
      _prefsList = reloaded;
    });
  }

  Future<void> _deletePref(String key) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定删除 "$key" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
    setState(() {
      _prefsList = _prefsList.where((e) => e.key != key).toList();
    });
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

      await for (final entity in dir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          final ext = entity.path.split('.').last.toLowerCase();
          if (_mediaExtensions.contains(ext)) {
            try {
              final size = await entity.length();
              files.add(
                FileItem(
                  path: entity.path,
                  name: entity.path.split(Platform.pathSeparator).last,
                  size: size,
                  type: _getMediaType(ext),
                ),
              );
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

  bool get isImage {
    return false;
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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatItem(
                  label: '笔记文件',
                  value: '${_noteList.length}',
                  icon: Icons.article,
                ),
                _StatItem(
                  label: '存储类型',
                  value: '${_storageList.length}',
                  icon: Icons.storage,
                ),
                _StatItem(
                  label: '总数据量',
                  value: _formatSize(
                    _storageList.fold(0, (sum, info) => sum + info.size) +
                        _noteSummary.totalSize,
                  ),
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
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '存储数据'),
              Tab(text: '多媒体文件'),
              Tab(text: '应用配置'),
              Tab(text: '云同步'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildStorageTab(),
                      _buildMediaTab(),
                      _buildPrefsTab(),
                      _CloudSyncTab(onAfterChange: _loadStorageData),
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
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _loadStorageData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _storageList.isEmpty && _noteList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('暂无数据', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(12),
                  children: [
                    ..._storageList.map((info) {
                      final keys = _keyDetails[info.name] ?? [];
                      // 0 key 的 box 卡片不显示，避免冗余
                      if (info.keyCount == 0) {
                        return const SizedBox.shrink();
                      }
                      return _StorageCard(
                        info: info,
                        keys: keys,
                        expandedKeys: _expandedKeys,
                        formatSize: _formatSize,
                        getSizeColor: _getSizeColor,
                        onKeyTap: (detail) =>
                            _showKeyDetail(context, info, detail),
                        onDeleteKey: (key) => _deleteKey(info, key),
                        onClear: () => _clearStorage(info),
                        onToggleExpand: (key) {
                          setState(() {
                            if (_expandedKeys.contains(key)) {
                              _expandedKeys.remove(key);
                            } else {
                              _expandedKeys.add(key);
                            }
                          });
                        },
                      );
                    }),
                    if (_noteList.isNotEmpty)
                      _NotesGroupCard(
                        notes: _noteList,
                        noteSummary: _noteSummary,
                        isExpanded: _expandedKeys.contains('__notes__'),
                        formatSize: _formatSize,
                        onToggleExpand: () {
                          setState(() {
                            if (_expandedKeys.contains('__notes__')) {
                              _expandedKeys.remove('__notes__');
                            } else {
                              _expandedKeys.add('__notes__');
                            }
                          });
                        },
                        onNoteTap: (note) =>
                            _showNotePreview(context, note),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  void _showNotePreview(BuildContext context, NoteInfo note) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _NotePreviewSheet(
        note: note,
        formatSize: _formatSize,
        onDelete: () {
          Navigator.pop(context);
          _deleteNote(note);
        },
      ),
    );
  }

  Future<void> _deleteNote(NoteInfo note) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除笔记 "${note.title}" 吗？\n\n此操作不可撤销。'),
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
      try {
        await NoteRootScope.of(context).noteRoot.deleteNote(note.id);
        await _loadStorageData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已删除: ${note.title}')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  Widget _buildPrefsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'SharedPreferences · ${_prefsList.length} 条',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              FilledButton.icon(
                onPressed: _addPref,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('新增'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _prefsList.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('暂无配置项', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _prefsList.length,
                  itemBuilder: (context, index) {
                    final entry = _prefsList[index];
                    return _PrefCard(
                      entry: entry,
                      onEdit: () => _editPref(entry),
                      onDelete: () => _deletePref(entry.key),
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
                onTap: () => _previewFile(context, file),
                onDelete: () => _deleteFile(file),
              );
            },
          ),
        ),
      ],
    );
  }

  void _previewFile(BuildContext context, FileItem file) {
    final ext = file.name.split('.').last.toLowerCase();
    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'].contains(ext);

    if (!isImage) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('不支持预览: ${file.type}')));
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        color: Colors.black,
        child: Column(
          children: [
            SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Text(file.name, style: const TextStyle(color: Colors.white)),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Image.file(
                  File(file.path),
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stack) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.broken_image,
                          color: Colors.white54,
                          size: 64,
                        ),
                        const SizedBox(height: 16),
                        Text('图片加载失败', style: TextStyle(color: Colors.white54)),
                      ],
                    );
                  },
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Text(
                      '${file.type} · ${_formatSize(file.size)}',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _deleteFile(file);
                      },
                      icon: const Icon(
                        Icons.delete,
                        color: Colors.redAccent,
                        size: 18,
                      ),
                      label: const Text(
                        '删除',
                        style: TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showKeyDetail(
    BuildContext context,
    StorageInfo info,
    KeyDetail detail,
  ) {
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
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已删除: $key')));
        }
      }
    }
  }

  Future<void> _deleteFile(FileItem file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除 "${file.name}" 吗？\n\n路径: ${file.path}'),
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
      try {
        final f = File(file.path);
        await f.delete();
        await _loadStorageData();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('已删除: ${file.name}')));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已清空: ${info.displayName}')));
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
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
      ],
    );
  }
}
class _StorageCard extends StatelessWidget {

  final StorageInfo info;
  final List<KeyDetail> keys;
  final Set<String> expandedKeys;
  final String Function(int) formatSize;
  final Color Function(int) getSizeColor;
  final void Function(KeyDetail) onKeyTap;
  final void Function(String) onDeleteKey;
  final VoidCallback onClear;
  final void Function(String) onToggleExpand;

  const _StorageCard({
    required this.info,
    required this.keys,
    required this.expandedKeys,
    required this.formatSize,
    required this.getSizeColor,
    required this.onKeyTap,
    required this.onDeleteKey,
    required this.onClear,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpanded = expandedKeys.contains(info.name);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          // 头部
          InkWell(
            onTap: () => onToggleExpand(info.name),
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
                      info.type == StorageType.hive
                          ? Icons.table_chart
                          : Icons.settings,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                info.typeLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${info.keyCount} 个键',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
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
                          Icon(
                            isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 20,
                            color: Colors.grey[600],
                          ),
                          IconButton(
                            icon: const Icon(Icons.cleaning_services, size: 20),
                            onPressed: onClear,
                            tooltip: '清空',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 32,
                              minHeight: 32,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // 键列表
          if (isExpanded && keys.isNotEmpty) ...[
            const Divider(height: 1),
            ListView.builder(
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
                child: const Icon(
                  Icons.data_object,
                  size: 14,
                  color: Colors.purple,
                ),
              ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    detail.key,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
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
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                info.displayName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                formatSize(detail.size),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                              if (detail.isJson) ...[
                                const SizedBox(width: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.purple.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'JSON',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.purple,
                                    ),
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
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete),
                    label: const Text('删除此项'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
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
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _MediaFileCard({
    required this.file,
    required this.formatSize,
    required this.getSizeColor,
    required this.onTap,
    required this.onDelete,
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
              IconButton(
                icon: Icon(
                  Icons.delete_outline,
                  color: Colors.red[400],
                  size: 20,
                ),
                onPressed: onDelete,
                tooltip: '删除',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotesGroupCard extends StatelessWidget {
  final List<NoteInfo> notes;
  final NoteSummary noteSummary;
  final bool isExpanded;
  final String Function(int) formatSize;
  final VoidCallback onToggleExpand;
  final void Function(NoteInfo) onNoteTap;

  const _NotesGroupCard({
    required this.notes,
    required this.noteSummary,
    required this.isExpanded,
    required this.formatSize,
    required this.onToggleExpand,
    required this.onNoteTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: onToggleExpand,
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
                      Icons.article,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '笔记文件',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '笔记',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '${noteSummary.noteCount} 篇',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                              ),
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
                        formatSize(noteSummary.totalSize),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        isExpanded ? Icons.expand_less : Icons.expand_more,
                        size: 20,
                        color: Colors.grey[600],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            ...notes.map((note) => _NoteListTile(
              note: note,
              formatSize: formatSize,
              onTap: () => onNoteTap(note),
            )),
          ],
        ],
      ),
    );
  }
}

class _NoteListTile extends StatelessWidget {
  final NoteInfo note;
  final String Function(int) formatSize;
  final VoidCallback onTap;

  const _NoteListTile({
    required this.note,
    required this.formatSize,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(
                Icons.description,
                size: 14,
                color: Colors.blue,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    note.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${note.blockCount} 块',
                    style: TextStyle(fontSize: 10, color: Colors.grey[500]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatSize(note.fileSize),
              style: const TextStyle(fontSize: 10),
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

class _NotePreviewSheet extends StatefulWidget {
  final NoteInfo note;
  final String Function(int) formatSize;
  final VoidCallback onDelete;

  const _NotePreviewSheet({
    required this.note,
    required this.formatSize,
    required this.onDelete,
  });

  @override
  State<_NotePreviewSheet> createState() => _NotePreviewSheetState();
}

class _NotePreviewSheetState extends State<_NotePreviewSheet> {
  String _content = '';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContent());
  }

  Future<void> _loadContent() async {
    try {
      final content = await NoteRootScope.of(context).noteRoot.readRawNoteContent(widget.note.filePath);
      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _content = '加载失败: $e';
          _isLoading = false;
        });
      }
    }
  }

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
                            widget.note.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                '${widget.note.blockCount} 块',
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                widget.formatSize(widget.note.fileSize),
                                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              ),
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
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : SingleChildScrollView(
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
                            _content,
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
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete),
                    label: const Text('删除笔记'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
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

/// prefs 编辑返回值
class _PrefEdit {
  final String key;
  final String type;
  final String value;
  _PrefEdit({required this.key, required this.type, required this.value});
}

/// prefs 新增 / 编辑对话框
class _PrefEditDialog extends StatefulWidget {
  final bool isNew;
  final String initialKey;
  final String initialType;
  final String initialValue;

  const _PrefEditDialog({
    required this.isNew,
    this.initialKey = '',
    this.initialType = 'String',
    this.initialValue = '',
  });

  @override
  State<_PrefEditDialog> createState() => _PrefEditDialogState();
}

class _PrefEditDialogState extends State<_PrefEditDialog> {
  late final TextEditingController _keyCtrl;
  late final TextEditingController _valCtrl;
  late String _type;

  static const _types = ['String', 'int', 'double', 'bool', 'List<String>'];

  @override
  void initState() {
    super.initState();
    _keyCtrl = TextEditingController(text: widget.initialKey);
    _valCtrl = TextEditingController(text: widget.initialValue);
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _valCtrl.dispose();
    super.dispose();
  }

  String _hintFor(String t) {
    switch (t) {
      case 'String':
        return '任意字符串';
      case 'int':
        return '整数，如 42';
      case 'double':
        return '浮点数，如 3.14';
      case 'bool':
        return 'true 或 false';
      case 'List<String>':
        return '逗号分隔，如 a, b, c';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 480),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(widget.isNew ? '新增配置' : '编辑配置',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Key', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _keyCtrl,
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: '配置 key（导出导入都用这个 key）',
              ),
            ),
            const SizedBox(height: 12),
            const Text('类型', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
              items: _types
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v ?? _type),
            ),
            const SizedBox(height: 12),
            const Text('Value', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            TextField(
              controller: _valCtrl,
              maxLines: null,
              decoration: InputDecoration(
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
                hintText: _hintFor(_type),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      if (_keyCtrl.text.trim().isEmpty) return;
                      Navigator.pop(
                        context,
                        _PrefEdit(
                          key: _keyCtrl.text.trim(),
                          type: _type,
                          value: _valCtrl.text,
                        ),
                      );
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// prefs 单条卡片
class _PrefCard extends StatelessWidget {
  final MapEntry<String, Object?> entry;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _PrefCard({
    required this.entry,
    required this.onEdit,
    required this.onDelete,
  });

  Color _typeColor(String type) {
    switch (type) {
      case 'String':
        return Colors.blue;
      case 'int':
        return Colors.green;
      case 'double':
        return Colors.teal;
      case 'bool':
        return Colors.orange;
      case 'List<String>':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = entry.value.runtimeType.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _typeColor(type).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.settings, color: _typeColor(type)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.key,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontFamily: 'monospace',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      entry.value?.toString() ?? 'null',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _typeColor(type).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  type,
                  style: TextStyle(fontSize: 10, color: _typeColor(type)),
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red[400], size: 20),
                onPressed: onDelete,
                tooltip: '删除',
              ),
            ],
          ),
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

/// 第 4 个 tab：云同步（登录闸 + 备份/恢复/删除）。
/// 复用 UserAuthService 登录 / GetIt；复用 Riverpod 拿 kvEndpoint + tokenManager。
class _CloudSyncTab extends ConsumerStatefulWidget {
  const _CloudSyncTab({required this.onAfterChange});

  /// 恢复完成后回调，用于让父页面刷新本地数据视图。
  final Future<void> Function() onAfterChange;

  @override
  ConsumerState<_CloudSyncTab> createState() => _CloudSyncTabState();
}

class _CloudSyncTabState extends ConsumerState<_CloudSyncTab> {
  final _emailCtrl = TextEditingController();
  final _pwdCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _busy = false;
  String? _identity;
  List<String> _backups = const [];
  String? _selected;

  @override
  void initState() {
    super.initState();
    _loadIdentity();
    _loadBackups();
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _pwdCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<bool> _hasToken() async {
    final t = await ref.read(tokenManagerProvider).accessToken;
    return t != null && t.isNotEmpty;
  }

  Future<void> _loadIdentity() async {
    if (!(await _hasToken())) {
      if (mounted) setState(() => _identity = null);
      return;
    }
    final r = await GetIt.instance<UserAuthService>().userInfo();
    if (!mounted) return;
    if (r.code == 401) {
      // token 失效 → 清掉、回登录闸
      await ref.read(tokenManagerProvider).clear();
      setState(() {
        _identity = null;
        _backups = const [];
      });
      return;
    }
    if (r.isSuccess) {
      setState(() {
        _identity = (r.data?['email'] ?? r.data?['nickname'] ?? '').toString();
      });
    }
  }

  Future<void> _loadBackups() async {
    if (!(await _hasToken())) {
      if (mounted) setState(() => _backups = const []);
      return;
    }
    final sync = CloudStorageSync(ref.read(kvEndpointProvider));
    final names = await sync.listBackups();
    if (mounted) setState(() => _backups = names);
  }

  Future<void> _login() async {
    final email = _emailCtrl.text.trim();
    final pwd = _pwdCtrl.text;
    if (email.isEmpty || pwd.isEmpty) return;
    setState(() => _busy = true);
    try {
      final r = await GetIt.instance<UserAuthService>().login(email, pwd);
      if (!mounted) return;
      if (r.isSuccess) {
        _pwdCtrl.clear();
        await _loadIdentity();
        await _loadBackups();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('登录成功')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('登录失败: ${r.message}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(tokenManagerProvider).clear();
    if (!mounted) return;
    setState(() {
      _identity = null;
      _backups = const [];
      _selected = null;
    });
  }

  Future<void> _doBackup() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final r = await sync.backup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(r.ok
            ? '已备份 "$name"（${r.bytes ?? 0} bytes）'
            : '备份失败: ${r.error ?? "?"}'),
      ));
      if (r.ok) {
        _nameCtrl.clear();
        await _loadBackups();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doRestore() async {
    final name = _selected;
    if (name == null) return;
    final clearFirst = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('从 "$name" 恢复'),
        content: const Text(
            '建议先备份当前数据。\n是否同时清空已有数据？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空后导入',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (clearFirst == null) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final r = await sync.restore(name, clearFirst: clearFirst);
      if (!mounted) return;
      if (!r.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败: ${r.error ?? "?"}')),
        );
        return;
      }
      final imp = r.import!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          '恢复完成: Hive ${imp.hiveCount} / 配置 ${imp.prefsCount} / 笔记 ${imp.notesCount}'
          '${imp.errorCount > 0 ? " / 错误 ${imp.errorCount}" : ""}',
        ),
      ));
      await widget.onAfterChange();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _doDelete() async {
    final name = _selected;
    if (name == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除备份 "$name"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final sync = CloudStorageSync(ref.read(kvEndpointProvider));
      final removed = await sync.deleteBackup(name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(removed ? '已删除' : '删除失败')),
      );
      await _loadBackups();
      if (mounted) setState(() => _selected = null);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _hasToken(),
      builder: (context, snap) {
        final loggedIn = snap.data == true;
        if (!loggedIn) return _buildLogin();
        return _buildSync();
      },
    );
  }

  Widget _buildLogin() {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: accent.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Icon(Icons.cloud_outlined, color: accent, size: 28),
              ),
              const SizedBox(height: 12),
              Text('云同步需要登录',
                  style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: '邮箱'),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pwdCtrl,
                decoration: const InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy ? null : _login,
                icon: _busy
                    ? SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      )
                    : const Icon(Icons.login, size: 18),
                label: const Text('登录'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: accent,
                  side: BorderSide(
                    color: accent.withValues(alpha: 0.5),
                    width: 1.5,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSync() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 登录状态指示 —— border-emphasis green
          Row(children: [
            _StatusChip(label: '已登录${_identity == null ? "" : ": $_identity"}'),
            const Spacer(),
            TextButton(
              onPressed: _busy ? null : _logout,
              child: const Text('退出'),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: '备份名（友好名）',
                ),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _doBackup,
              icon: const Icon(Icons.cloud_upload_outlined, size: 18),
              label: const Text('备份到云端'),
              style: _outlinedActionStyle(Colors.green),
            ),
          ]),
          const SizedBox(height: 12),
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('已有备份',
                style: TextStyle(fontWeight: FontWeight.w600)),
          ),
          Expanded(
            child: _backups.isEmpty
                ? const Center(child: Text('还没有云端备份'))
                : ListView.builder(
                    itemCount: _backups.length,
                    itemBuilder: (_, i) {
                      final n = _backups[i];
                      return _BackupRow(
                        name: n,
                        selected: _selected == n,
                        onTap: () => setState(() => _selected = n),
                      );
                    },
                  ),
          ),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_busy || _selected == null) ? null : _doRestore,
                icon: const Icon(Icons.cloud_download_outlined, size: 18),
                label: const Text('从云端恢复'),
                style: _outlinedActionStyle(Colors.blue),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: (_busy || _selected == null) ? null : _doDelete,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('删除备份'),
                style: _outlinedActionStyle(Colors.red),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

/// OutlinedButton 撞色编码：浅 tint 底 + 同色描边 + 同色前景。
/// 操作按钮专用（与内容型页面的"统一主题色"反向）。
ButtonStyle _outlinedActionStyle(Color color) => OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.5), width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

/// 已登录状态指示 —— border-emphasis green
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.check_circle_outline, size: 14, color: Colors.green),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: Colors.green,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

/// 单个备份条目 —— 选中态用 primary 描边+浅 tint 强提示，未选中态无边框。
class _BackupRow extends StatelessWidget {
  const _BackupRow({
    required this.name,
    required this.selected,
    required this.onTap,
  });
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: selected
            ? accent.withValues(alpha: 0.08)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.45)
                    : theme.dividerColor.withValues(alpha: 0.4),
                width: 1.2,
              ),
            ),
            child: Row(children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                size: 18,
                color: selected ? accent : theme.iconTheme.color?.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text(name)),
            ]),
          ),
        ),
      ),
    );
  }
}

void registerStorageAnalyzeDemo() {
  demoRegistry.register(StorageAnalyzeDemo());
}
