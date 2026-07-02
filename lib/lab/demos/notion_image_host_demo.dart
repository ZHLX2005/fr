// Notion 图床 Demo — 在 me 数据库里建 page、拍照上传到最新 page 末尾。
//
// 流程：
//   1. 第一次用：填 token + 数据库 ID → 保存（SharedPreferences 持久化）
//   2. 后续启动：自动加载缓存 → 显示当前最新 page
//   3. 两个按钮：
//      - "创建新 page"：在数据库下新建 page（标题=ISO 时间戳 mention.date）
//      - "拍照上传"：调 image_picker 相机 → 3 步上传到最新 page 末尾
//
// Token / 数据库 ID 走 SharedPreferences；Provider 在 initState 时加载。
// 上传路径复用 lib/api/notion/ — 已通过 test/api/notion/ 链路测试。

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lab_container.dart';
import '../../api/api_module.dart';

/// 缓存键名常量 — 集中管理便于排查。
const String _kTokenPrefs = 'notion_token';
const String _kDbIdPrefs = 'notion_db_id';

class NotionImageHostDemo extends DemoPage {
  @override
  String get title => 'Notion 图床';

  @override
  String get description => 'Notion 数据库作为图片托管（按 page 追加）';

  @override
  bool get preferFullScreen => true;

  @override
  Widget buildPage(BuildContext context) => const NotionImageHostPage();
}

void registerNotionImageHostDemo() {
  demoRegistry.register(NotionImageHostDemo());
}

class NotionImageHostPage extends ConsumerStatefulWidget {
  const NotionImageHostPage({super.key});

  @override
  ConsumerState<NotionImageHostPage> createState() =>
      _NotionImageHostPageState();
}

class _NotionImageHostPageState extends ConsumerState<NotionImageHostPage> {
  final _tokenController = TextEditingController();
  final _dbIdController = TextEditingController();
  final _picker = ImagePicker();

  String? _latestPageId;
  String? _latestPageUrl;
  String _status = '初始化…';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _tokenController.dispose();
    _dbIdController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_kTokenPrefs);
    final dbId = prefs.getString(_kDbIdPrefs) ?? NotionConfig.defaultDatabaseId;

    _tokenController.text = token ?? '';
    _dbIdController.text = dbId;

    if (token != null && token.isNotEmpty) {
      // 推送到 Riverpod，让 endpoint 立刻可用
      ref.read(notionTokenProvider.notifier).state = token;
      ref.read(notionDatabaseIdProvider.notifier).state = dbId;
      await _refreshLatestPage();
      setState(() => _status = '已加载缓存配置');
    } else {
      setState(() => _status = '请输入 Token 和数据库 ID');
    }
  }

  Future<void> _saveToken() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _setStatus('Token 不能为空');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTokenPrefs, token);
    ref.read(notionTokenProvider.notifier).state = token;
    setState(() => _status = 'Token 已保存');
  }

  Future<void> _saveDbId() async {
    final dbId = _dbIdController.text.trim();
    if (dbId.isEmpty) {
      _setStatus('数据库 ID 不能为空');
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDbIdPrefs, dbId);
    ref.read(notionDatabaseIdProvider.notifier).state = dbId;
    setState(() => _status = '数据库 ID 已保存');
  }

  Future<void> _refreshLatestPage() async {
    final dbId = _dbIdController.text.trim();
    final token = _tokenController.text.trim();
    if (token.isEmpty || dbId.isEmpty) {
      _setStatus('请先填 Token + 数据库 ID');
      return;
    }
    setState(() => _isBusy = true);
    try {
      // 临时拿一次 endpoint — 用完后不需要 dispose
      final db = NotionDatabaseEndpoint(token: token);
      final page = await db.queryLatestPage(dbId);
      if (page == null) {
        setState(() {
          _latestPageId = null;
          _latestPageUrl = null;
          _isBusy = false;
          _status = '数据库里还没有 page，请先创建';
        });
        return;
      }
      setState(() {
        _latestPageId = page['id'] as String;
        _latestPageUrl = page['url'] as String?;
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
    final dbId = _dbIdController.text.trim();
    final token = _tokenController.text.trim();
    if (token.isEmpty || dbId.isEmpty) {
      _setStatus('请先填 Token + 数据库 ID');
      return;
    }
    setState(() => _isBusy = true);
    try {
      final pageEndpoint = NotionPageEndpoint(token: token);
      final page = await pageEndpoint.createPageWithTimestamp(databaseId: dbId);
      setState(() {
        _latestPageId = page['id'] as String;
        _latestPageUrl = page['url'] as String?;
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

  Future<void> _takeAndUpload() async {
    // 拍照 — 用 image_picker 的 camera 模式，直接返回 XFile.path。
    // MediaService.takePicture() 内部会读 bytes 转 base64（web 场景），但
    // 这里我们需要在移动端直接拿到文件路径上传，避免 web-only 分支。
    XFile? photo;
    try {
      photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );
    } catch (e) {
      // image_picker 在 web 上会抛 — 提示用户
      _setStatus('拍照失败（web 暂不支持）: $e');
      return;
    }
    if (photo == null) {
      _setStatus('已取消拍照');
      return;
    }

    final token = _tokenController.text.trim();
    final dbId = _dbIdController.text.trim();
    if (token.isEmpty || dbId.isEmpty) {
      _setStatus('请先填 Token + 数据库 ID');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // 1. 确保 latestPageId 存在（如果没有，自动创建一个）
      var latestId = _latestPageId;
      if (latestId == null) {
        final pageEndpoint = NotionPageEndpoint(token: token);
        final newPage =
            await pageEndpoint.createPageWithTimestamp(databaseId: dbId);
        latestId = newPage['id'] as String;
      }

      // 2. 读文件字节
      final bytes = await File(photo.path).readAsBytes();
      final filename =
          'cam_${DateTime.now().toIso8601String().replaceAll(':', '-')}.jpg';

      // 3. 3 步上传
      final fileEndpoint = NotionFileEndpoint(token: token);
      final block = await fileEndpoint.uploadImageToPage(
        pageId: latestId,
        imageBytes: bytes,
        filename: filename,
        contentType: 'image/jpeg',
      );

      setState(() {
        _isBusy = false;
        _status = '已上传图片到 page (block=${(block['id'] as String).substring(0, 8)}…)';
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.image, size: 28, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'Notion 图床',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                if (_isBusy)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // Token 配置卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Token',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        hintText: 'ntn_xxx 或 secret_xxx',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _isBusy ? null : _saveToken,
                      icon: const Icon(Icons.save),
                      label: const Text('保存 Token'),
                      style: _outlinedBtnStyle(Colors.blue),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 数据库 ID 配置卡片
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '数据库 ID',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _dbIdController,
                      decoration: InputDecoration(
                        hintText: NotionConfig.defaultDatabaseId,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        helperText: '默认填充 me 数据库',
                        helperStyle:
                            TextStyle(fontSize: 11, color: theme.hintColor),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBusy ? null : _saveDbId,
                            icon: const Icon(Icons.save),
                            label: const Text('保存'),
                            style: _outlinedBtnStyle(Colors.blue),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isBusy ? null : _refreshLatestPage,
                            icon: const Icon(Icons.refresh),
                            label: const Text('刷新最新'),
                            style: _outlinedBtnStyle(Colors.indigo),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 当前最新 page 信息
            Card(
              child: ListTile(
                leading: const Icon(Icons.article_outlined, color: Colors.teal),
                title: Text(
                  _latestPageId == null
                      ? '当前最新 page: 无'
                      : '当前最新 page: ${_latestPageId!.substring(0, 8)}…',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: _latestPageUrl == null
                    ? null
                    : Text(
                        _latestPageUrl!,
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
              ),
            ),
            const SizedBox(height: 16),

            // 两个主操作按钮
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _createNewPage,
                    icon: const Icon(Icons.add),
                    label: const Text('创建新 page'),
                    style: _outlinedBtnStyle(Colors.green),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isBusy ? null : _takeAndUpload,
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('拍照并上传'),
                    style: _outlinedBtnStyle(Colors.deepPurple),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 状态栏
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _status,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}