import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart' hide RichText;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/storage/storage_manager.dart';
import '../../core/storage/export/const_storage_export.dart';
import '../../core/storage/export/storage_exporter.dart';
import '../../core/storage/export/storage_importer.dart';
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
  final Set<String> _expandedKeys = {};
  List<NoteInfo> _noteList = [];
  NoteSummary _noteSummary = const NoteSummary(noteCount: 0, totalBlocks: 0, totalSize: 0);

  // 导出/导入状态
  bool _isExporting = false;
  bool _isImporting = false;
  ExportStage _exportStage = ExportStage.meta;
  ImportStage _importStage = ImportStage.parse;
  String _exportMessage = '';
  String _importMessage = '';
  int _exportCurrent = 0;
  int _exportTotal = 0;
  int _importCurrent = 0;
  int _importTotal = 0;

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
    _tabController = TabController(length: 2, vsync: this);
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

      setState(() {
        _storageList = list;
        _keyDetails = keyDetails;
        _mediaFiles = mediaFiles;
        _noteList = noteList;
        _noteSummary = noteSummary;
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

  Future<void> _onExport() async {
    setState(() {
      _isExporting = true;
      _exportStage = ExportStage.meta;
      _exportMessage = '准备导出';
      _exportCurrent = 0;
      _exportTotal = 0;
    });

    try {
      // 先确保所有 typed box 已注册（calendar 等），否则导出会漏掉它们
      await _ensureBoxesInitialized();

      final exporter = StorageExporter(
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _exportStage = p.stage;
              _exportMessage = p.message;
              _exportCurrent = p.current;
              _exportTotal = p.total;
            });
          }
        },
      );

      final result = await exporter.exportAll();

      if (!mounted) return;
      setState(() {
        _isExporting = false;
      });

      // 展示导出结果对话框
      await showDialog<void>(
        context: context,
        builder: (ctx) => _ExportResultDialog(
          filePath: result.filePath,
          totalKeys: result.totalKeys,
          totalSize: result.totalSize,
          timestamp: result.timestamp,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isExporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  Future<void> _onImport() async {
    // 弹文件选择器
    FilePickerResult? picked;
    try {
      picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['txt'],
        allowMultiple: false,
        withData: false,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('文件选择失败: $e')),
      );
      return;
    }
    if (picked == null || picked.files.isEmpty) return;
    final path = picked.files.single.path;
    if (path == null) return;
    final fileName = picked.files.single.name;

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认导入'),
        content: Text(
          '将解析 "$fileName" 中的全部数据并写入。\n'
          '建议先导出当前数据作为备份。\n'
          '是否同时清空已有数据？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('保留'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空后导入', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm == null || !mounted) return;

    setState(() {
      _isImporting = true;
      _importStage = ImportStage.read;
      _importMessage = '准备导入';
      _importCurrent = 0;
      _importTotal = 0;
    });

    try {
      // 先确保 typed box 已注册，导入时才能按 typed 类型写回（Event/Person 等）
      await _ensureBoxesInitialized();

      final importer = StorageImporter(
        clearBeforeImport: confirm,
        onProgress: (p) {
          if (mounted) {
            setState(() {
              _importStage = p.stage;
              _importMessage = p.message;
              _importCurrent = p.current;
              _importTotal = p.total;
            });
          }
        },
      );

      final result = await importer.importFromFile(path);

      if (!mounted) return;
      setState(() {
        _isImporting = false;
      });

      await _loadStorageData();
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '导入完成: Hive ${result.hiveCount} 条 / 配置 ${result.prefsCount} 条 / '
            '笔记 ${result.notesCount} 个'
            '${result.errorCount > 0 ? ' / 错误 ${result.errorCount} 个' : ''}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isImporting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导入失败: $e')),
      );
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
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [_buildStorageTab(), _buildMediaTab()],
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
                onPressed: _isExporting ? null : _loadStorageData,
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              FilledButton.icon(
                onPressed: _isExporting ? null : _onExport,
                icon: const Icon(Icons.upload_file, size: 18),
                label: const Text('导出到文件'),
              ),
              OutlinedButton.icon(
                onPressed: _isImporting ? null : _onImport,
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('从文件导入'),
              ),
            ],
          ),
        ),
        if (_isExporting || _isImporting)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isExporting
                      ? '导出中: ${exportStageLabel(_exportStage)} - ${_exportMessage}'
                      : '导入中: ${importStageLabel(_importStage)} - ${_importMessage}',
                  style: const TextStyle(fontSize: 12),
                ),
                if ((_isExporting && _exportTotal > 0) ||
                    (_isImporting && _importTotal > 0))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: LinearProgressIndicator(
                      value: (_isExporting
                              ? _exportCurrent / _exportTotal
                              : _importCurrent / _importTotal)
                          .clamp(0.0, 1.0),
                      minHeight: 4,
                    ),
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

/// 导出结果对话框
class _ExportResultDialog extends StatelessWidget {
  final String filePath;
  final int totalKeys;
  final int totalSize;
  final String timestamp;

  const _ExportResultDialog({
    required this.filePath,
    required this.totalKeys,
    required this.totalSize,
    required this.timestamp,
  });

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600),
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                const Text('导出成功', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _kvRow('条目数', '$totalKeys'),
            _kvRow('数据量', _formatSize(totalSize)),
            _kvRow('时间', timestamp),
            const SizedBox(height: 12),
            const Text('文件路径', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: SelectableText(
                filePath,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '文件已存到「内部存储/Android/data/小豆子/files/exports/」，'
              '可用文件管理器找到。点「分享/保存到…」可一键存到 Download 或发到另一台设备。',
              style: TextStyle(color: Colors.grey[700], fontSize: 12),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: filePath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('路径已复制')),
                      );
                    },
                    icon: const Icon(Icons.copy, size: 18),
                    label: const Text('复制路径'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      // 通过系统分享面板，用户可保存到 Download / Files / 发到另一台设备
                      Share.shareXFiles(
                        [XFile(filePath)],
                        text: '存储数据备份',
                      );
                    },
                    icon: const Icon(Icons.ios_share, size: 18),
                    label: const Text('分享/保存到…'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(k, style: TextStyle(color: Colors.grey[600]))),
          Expanded(
            child: Text(v, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

void registerStorageAnalyzeDemo() {
  demoRegistry.register(StorageAnalyzeDemo());
}
