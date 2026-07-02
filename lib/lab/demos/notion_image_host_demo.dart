// Notion 图床 Demo — 拍照为核心，设置项收起到抽屉里。
//
// 架构（UX 升级版）：
//   - 主页：顶部状态栏（最新 page title + db 名）+ 中央预览区（大 +/图片预览）
//           + 底部操作按钮（重拍/上传/创建新 page）
//   - 设置抽屉（ModalBottomSheet）：Token + 数据库选择（一次性配置）
//
// 时区：date mention 加 +08:00 后缀（北京 UTC+8）。
// 最新 page 显示真实标题（通过 NotionPageEndpoint.extractTitle），不显示 ID。

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
  String _latestPageTitle = ''; // 用户可读的 page 标题（替代 id）
  String _status = '初始化…';
  bool _isBusy = false;

  /// 当前拍到的待上传图片路径。null = 没拍照状态，显示 + 大卡片。
  String? _capturedPath;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_kTokenPrefs) ?? '';
    _dbId = prefs.getString(_kDbIdPrefs) ?? NotionConfig.defaultDatabaseId;
    _dbName = prefs.getString(_kDbNamePrefs) ?? 'me';

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
          _latestPageTitle = '';
          _isBusy = false;
          _status = '数据库里还没有 page，点下方"创建新 page"';
        });
        return;
      }
      // 用真实标题替代 id — 用户可读
      final title = NotionPageEndpoint.extractTitle(page);
      setState(() {
        _latestPageId = page['id'] as String;
        _latestPageTitle = title;
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
        _latestPageTitle = NotionPageEndpoint.extractTitle(page);
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

  Future<void> _capture() async {
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
    setState(() {
      _capturedPath = photo!.path;
      _status = '已拍照，等待上传或重拍';
    });
  }

  Future<void> _uploadCaptured() async {
    final path = _capturedPath;
    if (path == null) return;
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token + 数据库');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // 1. 确保 latestPageId 存在
      var latestId = _latestPageId;
      String? latestTitle;
      if (latestId == null) {
        final pageEndpoint = NotionPageEndpoint(token: _token);
        final newPage =
            await pageEndpoint.createPageWithTimestamp(databaseId: _dbId);
        latestId = newPage['id'] as String;
        latestTitle = NotionPageEndpoint.extractTitle(newPage);
      } else {
        latestTitle = _latestPageTitle;
      }

      // 2. 读文件字节 + 生成可读文件名
      final bytes = await File(path).readAsBytes();
      // 文件名只展示给用户 — 用本地时间格式化 (不含 id/UUID 等)
      final ts = DateTime.now();
      final filename =
          'cam_${ts.year}${_pad(ts.month)}${_pad(ts.day)}_${_pad(ts.hour)}${_pad(ts.minute)}${_pad(ts.second)}.jpg';

      // 3. 3 步上传（不显示 block id — 用文件名反馈）
      final fileEndpoint = NotionFileEndpoint(token: _token);
      await fileEndpoint.uploadImageToPage(
        pageId: latestId,
        imageBytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      );

      setState(() {
        _latestPageTitle = latestTitle ?? _latestPageTitle;
        _isBusy = false;
        _status = '已上传 $filename 到「$_latestPageTitle」';
        _capturedPath = null; // 预览区回到 + 大卡片
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _status = '上传失败: $e';
      });
    }
  }

  void _retake() {
    setState(() {
      _capturedPath = null;
      _status = '已取消本次照片';
    });
  }

  void _setStatus(String s) {
    if (!mounted) return;
    setState(() => _status = s);
  }

  static String _pad(int n) => n.toString().padLeft(2, '0');

  /// 边框强调式按钮样式 — 与 api_test_demo 风格保持一致。
  ButtonStyle _outlinedBtnStyle(Color color, {double borderWidth = 1}) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(
          color: color.withValues(alpha: 0.5), width: borderWidth),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasCaptured = _capturedPath != null;

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
              // ── 顶部：当前数据库 + 最新 page (按标题) ──
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
                              _latestPageTitle.isEmpty
                                  ? '最新 page: 暂无'
                                  : _latestPageTitle,
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
              const SizedBox(height: 16),

              // ── 中央：预览区（大 + 卡片 OR 拍好的图）──
              Expanded(
                child: GestureDetector(
                  onTap: hasCaptured ? null : _capture,
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: hasCaptured
                          ? Colors.black
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: hasCaptured
                            ? Colors.transparent
                            : theme.colorScheme.outline
                                .withValues(alpha: 0.3),
                        width: 2,
                      ),
                    ),
                    child: hasCaptured
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              File(_capturedPath!),
                              fit: BoxFit.contain,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_a_photo_outlined,
                                size: 56,
                                color:
                                    theme.colorScheme.primary.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '点击拍照',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // ── 底部：操作按钮（根据状态切换）──
              if (hasCaptured) ...[
                // 拍完照：显示重拍 + 上传
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _retake,
                        icon: const Icon(Icons.refresh),
                        label: const Text('重拍'),
                        style: _outlinedBtnStyle(Colors.orange),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        onPressed: _isBusy ? null : _uploadCaptured,
                        icon: const Icon(Icons.cloud_upload_outlined),
                        label: const Text(
                          '上传',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        style: _outlinedBtnStyle(Colors.green, borderWidth: 2),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // 没拍照：显示创建新 page
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _createNewPage,
                    icon: const Icon(Icons.add),
                    label: const Text('创建新 page'),
                    style: _outlinedBtnStyle(Colors.green),
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ── 状态栏（操作反馈）──
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
              const SizedBox(height: 16),

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
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _pickDatabase,
                ),
              ),
              const SizedBox(height: 12),

              OutlinedButton.icon(
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
                  side: BorderSide(color: Colors.indigo.withValues(alpha: 0.5)),
                ),
              ),
              if (_dbLoadError != null) ...[
                const SizedBox(height: 8),
                Text(
                  _dbLoadError!,
                  style: const TextStyle(fontSize: 11, color: Colors.red),
                ),
              ],
              const SizedBox(height: 24),

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
                'Tip: Token 和数据库会保存到 SharedPreferences',
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
// 数据库选择器
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