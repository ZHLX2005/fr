// Notion 图床 Demo — 拍照为核心，设置项收起到抽屉里。
//
// 架构：
//   - 主页：状态卡片（当前 db / 最新 page）+ 大拍照按钮 + 创建新 page 按钮
//   - 设置抽屉（ModalBottomSheet）：Token + 数据库选择（用 Notion API 列 db）
//   - 预览页（拍照后）：全屏图片预览 + 上传/重拍/取消 三个按钮
//
// 时区：date mention 加 +08:00 后缀（北京 UTC+8），让 Notion UI 显示成
// 当前北京时间（已通过 test/api/notion/notion_timezone_real_test.dart 验证）。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lab_container.dart';
import '../../api/api_module.dart';

/// SharedPreferences 键名常量 — 集中管理。
const String _kTokenPrefs = 'notion_token';
const String _kDbIdPrefs = 'notion_db_id';
const String _kDbNamePrefs = 'notion_db_name';

class NotionImageHostDemo extends DemoPage {
  @override
  String get title => 'Notion 图床';

  @override
  String get description => 'Notion 数据库作为图片托管';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const NotionImageHostPage();
}

void registerNotionImageHostDemo() {
  demoRegistry.register(NotionImageHostDemo());
}

/// 数据库信息模型（用于列表选择 UI）。
class _DatabaseInfo {
  final String id;
  final String title;
  const _DatabaseInfo(this.id, this.title);

  @override
  bool operator ==(Object other) =>
      other is _DatabaseInfo && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class NotionImageHostPage extends ConsumerStatefulWidget {
  const NotionImageHostPage({super.key});

  @override
  ConsumerState<NotionImageHostPage> createState() =>
      _NotionImageHostPageState();
}

class _NotionImageHostPageState extends ConsumerState<NotionImageHostPage> {
  String _token = '';
  String _dbId = '';
  String _dbName = '';

  String? _latestPageId;
  String _status = '初始化…';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenPrefs) ?? '';
    _dbId = prefs.getString(_kDbIdPrefs) ?? NotionConfig.defaultDatabaseId;
    _dbName = prefs.getString(_kDbNamePrefs) ?? 'me (默认)';

    if (_token.isNotEmpty) {
      ref.read(notionTokenProvider.notifier).state = _token;
      ref.read(notionDatabaseIdProvider.notifier).state = _dbId;
      await _refreshLatestPage();
      setState(() => _status = '已加载缓存配置');
    } else {
      setState(() => _status = '点右上角 ⚙ 设置 Token 和数据库');
    }
  }

  Future<void> _openSettings() async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SettingsSheet(
        initialToken: _token,
        initialDbId: _dbId,
        initialDbName: _dbName,
      ),
    );
    if (result == true) {
      // 用户保存了设置 — 重新加载
      await _loadPrefs();
    }
  }

  Future<void> _refreshLatestPage() async {
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token + 数据库');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final db = NotionDatabaseEndpoint(token: _token);
      final page = await db.queryLatestPage(_dbId);
      if (page == null) {
        setState(() {
          _latestPageId = null;
          _isBusy = false;
          _status = '数据库里还没有 page，点下方"创建新 page"';
        });
        return;
      }
      setState(() {
        _latestPageId = page['id'] as String;
        _isBusy = false;
        _status = '已找到最新 page';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _status = '查询最新 page 失败: $e';
      });
    }
  }

  Future<void> _createNewPage() async {
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token + 数据库');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final pageEndpoint = NotionPageEndpoint(token: _token);
      final page = await pageEndpoint.createPageWithTimestamp(databaseId: _dbId);
      setState(() {
        _latestPageId = page['id'] as String;
        _isBusy = false;
        _status = '已创建新 page';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _status = '创建 page 失败: $e';
      });
    }
  }

  Future<void> _takeAndPreview() async {
    final picker = ImagePicker();
    XFile? photo;
    try {
      photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (e) {
      _setStatus('拍照失败（web 暂不支持）: $e');
      return;
    }
    if (photo == null) {
      _setStatus('已取消拍照');
      return;
    }
    if (!mounted) return;
    final capturedPath = photo.path;

    // 弹出预览页：用户可选择上传、重拍、取消
    final action = await Navigator.of(context).push<_PreviewAction>(
      MaterialPageRoute(
        builder: (_) => _PreviewPage(imagePath: capturedPath),
        fullscreenDialog: true,
      ),
    );
    if (action == _PreviewAction.upload) {
      await _uploadPhoto(File(capturedPath));
    } else if (action == _PreviewAction.retake) {
      // 递归重拍
      await _takeAndPreview();
    }
    // null（取消/返回）：什么也不做
  }

  Future<void> _uploadPhoto(File file) async {
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token + 数据库');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // 1. 确保 latestPageId 存在（如果没有，自动创建一个）
      var latestId = _latestPageId;
      if (latestId == null) {
        final pageEndpoint = NotionPageEndpoint(token: _token);
        final newPage = await pageEndpoint.createPageWithTimestamp(databaseId: _dbId);
        latestId = newPage['id'] as String;
      }

      // 2. 读文件字节
      final bytes = await file.readAsBytes();
      final filename =
          'cam_${DateTime.now().toIso8601String().replaceAll(':', '-')}.jpg';

      // 3. 3 步上传
      final fileEndpoint = NotionFileEndpoint(token: _token);
      final block = await fileEndpoint.uploadImageToPage(
        pageId: latestId,
        imageBytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      );

      setState(() {
        _latestPageId = latestId;
        _isBusy = false;
        _status = '已上传图片 (block=${(block['id'] as String).substring(0, 8)}…)';
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _status = '上传失败: $e';
      });
    }
  }

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  /// 边框强调式按钮样式 — 与 api_test_demo 风格保持一致。
  ButtonStyle _outlinedBtnStyle(Color color) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(color: color.withValues(alpha: 0.5)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notion 图床'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '设置（Token / 数据库）',
            onPressed: _isBusy ? null : _openSettings,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              // 状态卡片：当前数据库 + 最新 page
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.storage,
                              size: 18, color: theme.colorScheme.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _dbName.isEmpty ? '(未选数据库)' : _dbName,
                              style: const TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_isBusy)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                        ],
                      ),
                      const Divider(height: 16),
                      Row(
                        children: [
                          const Icon(Icons.article_outlined,
                              size: 18, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _latestPageId == null
                                  ? '最新 page: 无'
                                  : '最新 page: ${_latestPageId!.substring(0, 8)}…',
                              style: const TextStyle(fontSize: 13),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.refresh, size: 18),
                            visualDensity: VisualDensity.compact,
                            tooltip: '刷新最新 page',
                            onPressed: _isBusy ? null : _refreshLatestPage,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 主操作区：拍照 + 创建
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // 拍照按钮 — 主操作，最大最显眼
                    SizedBox(
                      width: double.infinity,
                      height: 96,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _takeAndPreview,
                        icon: const Icon(Icons.photo_camera, size: 36),
                        label: const Text(
                          '拍照',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.deepPurple,
                          side: BorderSide(
                              color: Colors.deepPurple.withValues(alpha: 0.6),
                              width: 2),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // 创建新 page — 次要操作
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _createNewPage,
                        icon: const Icon(Icons.add),
                        label: const Text('创建新 page'),
                        style: _outlinedBtnStyle(Colors.green),
                      ),
                    ),
                  ],
                ),
              ),

              // 状态栏
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _status,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontSize: 11),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 预览页 — 拍照后弹出
// ═══════════════════════════════════════════════════════════════════

enum _PreviewAction { upload, retake }

class _PreviewPage extends StatelessWidget {
  final String imagePath;
  const _PreviewPage({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('预览'),
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: InteractiveViewer(
                child: Image.file(File(imagePath), fit: BoxFit.contain),
              ),
            ),
          ),
          // 三个动作按钮
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_PreviewAction.retake),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重拍'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange,
                        side: BorderSide(
                            color: Colors.orange.withValues(alpha: 0.5)),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          Navigator.of(context).pop(_PreviewAction.upload),
                      icon: const Icon(Icons.cloud_upload_outlined),
                      label: const Text(
                        '上传',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.green,
                        side: BorderSide(
                            color: Colors.green.withValues(alpha: 0.6),
                            width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 设置抽屉 — Token + 数据库选择
// ═══════════════════════════════════════════════════════════════════

class _SettingsSheet extends StatefulWidget {
  final String initialToken;
  final String initialDbId;
  final String initialDbName;

  const _SettingsSheet({
    required this.initialToken,
    required this.initialDbId,
    required this.initialDbName,
  });

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final TextEditingController _tokenController;
  late String _dbId;
  late String _dbName;

  List<_DatabaseInfo> _databases = [];
  bool _loadingDbs = false;
  String? _dbLoadError;

  bool _tokenVisible = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
    _dbId = widget.initialDbId;
    _dbName = widget.initialDbName;
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _fetchDatabases() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() => _dbLoadError = '请先填 Token');
      return;
    }
    setState(() {
      _loadingDbs = true;
      _dbLoadError = null;
    });
    try {
      final db = NotionDatabaseEndpoint(token: token);
      final dbs = await db.listDatabases();
      setState(() {
        _databases = dbs.map((d) {
          // title 是 rich_text array
          final titleArr = d['title'] as List<dynamic>? ?? [];
          final titleText = titleArr
              .map((t) => (t['plain_text'] as String?) ?? '')
              .join()
              .trim();
          return _DatabaseInfo(
            d['id'] as String,
            titleText.isEmpty ? '(无标题)' : titleText,
          );
        }).toList();
        _loadingDbs = false;
      });
    } catch (e) {
      setState(() {
        _loadingDbs = false;
        _dbLoadError = '加载失败: $e';
      });
    }
  }

  Future<void> _save() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showSnack('Token 不能为空');
      return;
    }
    if (_dbId.isEmpty) {
      _showSnack('请选择数据库');
      return;
    }
    setState(() => _saving = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kTokenPrefs, token);
      await prefs.setString(_kDbIdPrefs, _dbId);
      await prefs.setString(_kDbNamePrefs, _dbName);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      setState(() => _saving = false);
      _showSnack('保存失败: $e');
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2)),
    );
  }

  Future<void> _pickDatabase() async {
    final picked = await showModalBottomSheet<_DatabaseInfo>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _DatabasePickerSheet(
        databases: _databases,
        loading: _loadingDbs,
        error: _dbLoadError,
        currentId: _dbId,
        onRetry: _fetchDatabases,
      ),
    );
    if (picked != null) {
      setState(() {
        _dbId = picked.id;
        _dbName = picked.title;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 标题
              Row(
                children: [
                  Icon(Icons.settings, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  const Text(
                    '设置',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: _saving ? null : () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const Divider(),

              // Token
              const Text('Token',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _tokenController,
                obscureText: !_tokenVisible,
                decoration: InputDecoration(
                  hintText: 'ntn_xxx 或 secret_xxx',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffixIcon: IconButton(
                    icon: Icon(_tokenVisible
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () =>
                        setState(() => _tokenVisible = !_tokenVisible),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // 数据库
              const Text('数据库',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.storage, color: Colors.indigo),
                  title: Text(
                    _dbName.isEmpty ? '(未选择)' : _dbName,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: _dbId.isEmpty
                      ? null
                      : Text(
                          _dbId,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDatabase,
                ),
              ),
              const SizedBox(height: 12),

              // 加载数据库按钮
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _loadingDbs ? null : _fetchDatabases,
                      icon: _loadingDbs
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_download_outlined),
                      label: const Text('加载数据库列表'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.indigo,
                        side: BorderSide(
                            color: Colors.indigo.withValues(alpha: 0.5)),
                      ),
                    ),
                  ),
                ],
              ),
              if (_dbLoadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _dbLoadError!,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),

              // 保存按钮
              SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: const Text(
                    '保存设置',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green,
                    side: BorderSide(
                        color: Colors.green.withValues(alpha: 0.6), width: 2),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Tip: Token 和数据库会保存到 SharedPreferences，下次启动自动加载',
                style: TextStyle(fontSize: 11, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// 数据库选择器 — 列表展示所有可选 db
// ═══════════════════════════════════════════════════════════════════

class _DatabasePickerSheet extends StatelessWidget {
  final List<_DatabaseInfo> databases;
  final bool loading;
  final String? error;
  final String currentId;
  final VoidCallback onRetry;

  const _DatabasePickerSheet({
    required this.databases,
    required this.loading,
    required this.error,
    required this.currentId,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.storage, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  '选择数据库',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  tooltip: '重新加载',
                  onPressed: loading ? null : onRetry,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            if (loading)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (error != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              )
            else if (databases.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Text(
                  '没有找到任何数据库。\n确认 Token 有访问权限，并先在 Notion 里把数据库分享给 integration。',
                  style: TextStyle(color: Colors.grey),
                  textAlign: TextAlign.center,
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: databases.length,
                  itemBuilder: (ctx, i) {
                    final db = databases[i];
                    final isCurrent = db.id == currentId;
                    return ListTile(
                      leading: Icon(
                        isCurrent
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: isCurrent ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        db.title,
                        style: TextStyle(
                          fontWeight: isCurrent
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        db.id,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => Navigator.of(context).pop(db),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}