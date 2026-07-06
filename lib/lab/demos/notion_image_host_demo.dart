// Notion 图床 Demo — 拍照为核心，设置项收起到抽屉里。
//
// 架构（UX 升级版）：
//   - 主页：顶部状态栏（最新 page title + db 名）+ 中央预览区（大 +/图片预览）
//           + 底部操作按钮（重拍/上传/创建新 page）
//   - 设置抽屉（ModalBottomSheet）：Token + 数据库选择（一次性配置）
//
// 时区：date mention 加 +08:00 后缀（北京 UTC+8）。
// 最新 page 显示真实标题（通过 NotionPageEndpoint.extractTitle），不显示 ID。

import 'dart:convert';
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

/// 桌面 widget 入口用的 GlobalKey — main.dart 通过这个 key 拿到 demo 的
/// state 并调 [triggerCaptureFromWidget]。
final GlobalKey<State<NotionImageHostPage>> notionImageHostKey =
    GlobalKey<State<NotionImageHostPage>>();

/// 从外部（桌面 widget 入口）触发拍照。
///
/// 通过 dynamic 分发调用 state 上的 `captureFromWidget` — State 是私有类，
/// 无法在 main.dart 里 cast 出来，所以 demo 自己导出这个函数。
void triggerCaptureFromWidget() {
  final state = notionImageHostKey.currentState;
  if (state == null) return;
  // dynamic 转发：state 上的 captureFromWidget 是私有方法，静态分析看不到，
  // 但运行时会找到。用 noSuchMethod 兜底防止 demo 页面未初始化时报错。
  try {
    // ignore: avoid_dynamic_calls
    (state as dynamic).captureFromWidget();
  } on NoSuchMethodError {
    // demo 页面未挂载或未注册该方法 — 静默忽略
  } catch (_) {
    // 其他错误也忽略（拍照是非关键路径）
  }
}

class _NotionImageHostPageState extends ConsumerState<NotionImageHostPage> {
  String _token = '';
  String _dbId = '';
  String _dbName = '';

  String? _latestPageId;
  String _latestPageTitle = ''; // 用户可读的 page 标题（替代 id）
  String _status = '加载配置中…'; // 初始即占位，避免闪一下"未配置"误判
  bool _isBusy = false;
  bool _prefsLoaded = false; // _loadPrefs 完成标记，UI 据此判断 token/db 是否已就绪

  /// 当前拍到的待上传图片路径。null = 没拍照状态，显示 + 大卡片。
  String? _capturedPath;

  /// 用户输入的文字 — 左滑到文字页时用。提交后清空。
  final TextEditingController _textController = TextEditingController();

  /// PageView 控制器：0=图片页（默认）、1=文字页（左滑进入）。
  final PageController _previewPageController = PageController();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _textController.dispose();
    _previewPageController.dispose();
    super.dispose();
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
      setState(() {
        _prefsLoaded = true;
        _status = '已加载缓存配置';
      });
    } else {
      setState(() {
        _prefsLoaded = true;
        _status = '点右上角 ⚙ 设置 Token 和数据库';
      });
    }
  }

  Future<void> _openSettings() async {
    // 防止 _loadPrefs 还没完成就打开抽屉 — 此时 token 字段是空的，
    // 用户会误以为 token 没存上。
    if (!_prefsLoaded) {
      setState(() => _status = '配置加载中，请稍候…');
      return;
    }
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

  /// 桌面 widget 进入时调用（外部入口，不要命名为私有）。包装 _capture 但
  /// 增加 token / dbId 校验，避免没配置就跑拍照浪费相机权限。
  ///
  /// 之所以需要 token 校验：
  ///   - widget 点击后 App 冷启动，_loadPrefs 是异步的（300ms 内完成）
  ///   - main.dart addPostFrameCallback + 300ms delay 后才调到这里
  ///   - 此时 _token / _dbId 应该已经被 _loadPrefs 写好
  void captureFromWidget() {
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token 和数据库');
      // 仍然尝试打开相机 — 用户可能想先拍下来再去配置
      _capture();
      return;
    }
    _capture();
  }

  /// 拍照后用户主动选择"新 page"：强制创建新 page（不依赖 _latestPageId）
  ///
  /// 与提交分开两步 — 用户创建新 page 后仍可继续点"提交"。
  Future<void> _createNewPageWithCapture() async {
    await _createNewPage();
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

  /// 当前是否有可提交内容（图 / 文字任一）
  bool _hasAnyContent() =>
      _capturedPath != null || _textController.text.trim().isNotEmpty;

  /// 提交按钮文字：自动根据当前内容显示
  String _submitButtonLabel() {
    final hasImg = _capturedPath != null;
    final hasText = _textController.text.trim().isNotEmpty;
    if (hasImg && hasText) return '提交图+文';
    if (hasImg) return '上传';
    if (hasText) return '追加文字';
    return '提交';
  }

  /// 边框强调式按钮样式 — 与 api_test_demo 风格保持一致。
  ButtonStyle _outlinedBtnStyle(Color color, {double borderWidth = 1}) {
    return OutlinedButton.styleFrom(
      foregroundColor: color,
      side: BorderSide(
          color: color.withValues(alpha: 0.5), width: borderWidth),
    );
  }

  /// 把文字块追加到最新 page 末尾。
  ///
  /// 与 _uploadCaptured 镜像：上传图 vs 追加文字。
  /// 行为：
  ///   1. 若 _latestPageId 为 null → 先创建一个新 page
  ///   2. 调 pageEndpoint.appendParagraphBlock
  ///   3. 清空文字输入、回到图片页
  /// 一站式提交：上传图片（如果有）+ 追加文字（如果有）。
  ///
  /// 支持三种模式：
  ///   - 只拍图无文字 → 上传图
  ///   - 只输入文字无图 → 创建/复用 page + 追加文字
  ///   - 图 + 文字都有 → 先确保 page 存在，再传图，再追加文字
  ///
  /// 顺序：图先文后（用户要求）。
  /// 完成后：清空文字、保留 _capturedPath（无图时本来就 null）。
  Future<void> _submitAll() async {
    if (_token.isEmpty || _dbId.isEmpty) {
      _setStatus('请先在设置里填 Token + 数据库');
      return;
    }
    final text = _textController.text.trim();
    final imagePath = _capturedPath;
    if (text.isEmpty && imagePath == null) {
      _setStatus('没有可提交的内容（图片或文字）');
      return;
    }

    setState(() => _isBusy = true);
    try {
      // 1. 确保 _latestPageId 存在（无图无文也要 page 来放文字）
      var latestId = _latestPageId;
      if (latestId == null) {
        final pageEndpoint = NotionPageEndpoint(token: _token);
        final newPage =
            await pageEndpoint.createPageWithTimestamp(databaseId: _dbId);
        latestId = newPage['id'] as String;
        _latestPageTitle = NotionPageEndpoint.extractTitle(newPage);
      }

      // 2. 提交图（图先）
      if (imagePath != null) {
        final bytes = await File(imagePath).readAsBytes();
        final ts = DateTime.now();
        final filename =
            'cam_${ts.year}${_pad(ts.month)}${_pad(ts.day)}_${_pad(ts.hour)}${_pad(ts.minute)}${_pad(ts.second)}.jpg';
        final fileEndpoint = NotionFileEndpoint(token: _token);
        await fileEndpoint.uploadImageToPage(
          pageId: latestId,
          imageBytes: bytes,
          filename: filename,
          contentType: 'image/jpeg',
        );
      }

      // 3. 追加文字（图后）
      if (text.isNotEmpty) {
        final pageEndpoint = NotionPageEndpoint(token: _token);
        await pageEndpoint.appendParagraphBlock(
          pageId: latestId,
          text: text,
        );
      }

      // 4. 收尾
      _textController.clear();
      if (_previewPageController.hasClients) {
        await _previewPageController.animateToPage(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      if (!mounted) return;
      setState(() {
        _latestPageId = latestId;
        _latestPageTitle = _latestPageTitle;
        _isBusy = false;
        // 状态消息：分别报告
        if (imagePath != null && text.isNotEmpty) {
          _status = '已上传图片并追加文字到「$_latestPageTitle」';
        } else if (imagePath != null) {
          _status = '已上传到「$_latestPageTitle」';
        } else {
          _status = '已追加文字到「$_latestPageTitle」';
        }
        // 清空拍好的图（已上传）
        _capturedPath = null;
      });
    } catch (e) {
      setState(() {
        _isBusy = false;
        _status = '提交失败: $e';
      });
    }
  }

  /// Page 0: 图片预览页（默认）
  Widget _buildImagePage(ThemeData theme, bool hasCaptured) {
    return Stack(
      children: [
        GestureDetector(
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
                    : theme.colorScheme.outline.withValues(alpha: 0.3),
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
                        color: theme.colorScheme.primary.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '点击拍照（左滑输文字）',
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
        // 拍完照时右上角浮一个重拍 X 按钮
        if (hasCaptured)
          Positioned(
            top: 8,
            right: 8,
            child: Material(
              color: Colors.black.withValues(alpha: 0.5),
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _isBusy ? null : _retake,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.refresh, color: Colors.white, size: 20),
                ),
              ),
            ),
          ),
        // 左滑提示（小箭头，3 秒后自动消失）
        if (hasCaptured)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, color: Colors.white, size: 14),
                  Text('左滑输文字',
                      style: TextStyle(color: Colors.white, fontSize: 11)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Page 1: 文字输入页（左滑进入）
  Widget _buildTextPage(ThemeData theme) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.text_fields, color: theme.colorScheme.primary, size: 18),
              const SizedBox(width: 8),
              Text(
                '追加文字到「$_latestPageTitle」',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: theme.colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: TextField(
              controller: _textController,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: InputDecoration(
                hintText: '输入要追加到 page 末尾的文字…',
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
              style: TextStyle(
                fontSize: 15,
                color: theme.colorScheme.onSurface,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
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

              // ── 中央：预览区（PageView：0=图片、1=文字，左滑切换）──
              Expanded(
                child: PageView(
                  controller: _previewPageController,
                  physics: const BouncingScrollPhysics(),
                  children: [
                    // Page 0: 图片页（默认）
                    _buildImagePage(theme, hasCaptured),
                    // Page 1: 文字页（左滑进入）
                    _buildTextPage(theme),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // PageView 指示器（小点）
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _PageDot(active: true, theme: theme),
                  const SizedBox(width: 6),
                  _PageDot(active: false, theme: theme),
                ],
              ),
              const SizedBox(height: 8),

              // ── 底部：操作按钮（两页通用：新建 + 一站式提交）──
              // 提交按钮统一调 _submitAll：根据当前状态（有无图、有无文字）
              // 自动走"只文 / 只图 / 图+文"三种路径，图先文后。
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _createNewPageWithCapture,
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text(
                        '新页',
                        style: TextStyle(fontSize: 14),
                      ),
                      style: _outlinedBtnStyle(Colors.blue).copyWith(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: OutlinedButton.icon(
                      onPressed: _isBusy ? null : _submitAll,
                      icon: _isBusy
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.green,
                              ),
                            )
                          : Icon(
                              _hasAnyContent()
                                  ? Icons.cloud_upload_outlined
                                  : Icons.send,
                              size: 18,
                              color: Colors.green,
                            ),
                      label: Text(
                        _submitButtonLabel(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      style: _outlinedBtnStyle(Colors.green, borderWidth: 2)
                          .copyWith(
                        padding: const WidgetStatePropertyAll(
                          EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
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
  bool _loadingCache = true; // initState → _loadCachedDatabases 完成前禁用选择器

  bool _tokenVisible = false;
  bool _saving = false;

  /// SharedPreferences key — 数据库列表的 JSON 缓存。
  /// 按 token 分区（不同 token 的数据隔离）。
  static String _kDbListPrefsKey(String token) =>
      'notion_db_list_cache_${token.hashCode}';

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(text: widget.initialToken);
    _dbId = widget.initialDbId;
    _dbName = widget.initialDbName;
    _loadCachedDatabases();
  }

  /// 从 SharedPreferences 加载缓存的数据库列表。
  ///
  /// 只在用户主动刷新时更新。不自动触发网络请求。
  /// 缓存按 token 分区（不同 token 的数据隔离）。
  ///
  /// 用 [_loadingCache] 标志保护：缓存加载完成前禁用数据库选择器，避免
  /// 用户点进时 `_databases` 仍为 [] 显示空空如也的竞态。
  Future<void> _loadCachedDatabases() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      if (mounted) setState(() => _loadingCache = false);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString(_kDbListPrefsKey(token));
    try {
      if (cached != null && cached.isNotEmpty) {
        final list = jsonDecode(cached) as List<dynamic>;
        if (mounted) {
          setState(() {
            _databases = list.map((e) {
              final m = e as Map<String, dynamic>;
              return _DatabaseInfo(m['id'] as String, m['title'] as String);
            }).toList();
          });
        }
      }
    } catch (_) {
      await prefs.remove(_kDbListPrefsKey(token));
    } finally {
      if (mounted) setState(() => _loadingCache = false);
    }
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
      final infos = dbs.map((d) {
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

      // 缓存到 SharedPreferences（按 token 隔离）
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kDbListPrefsKey(token),
        jsonEncode(infos.map((e) => {'id': e.id, 'title': e.title}).toList()),
      );

      setState(() {
        _databases = infos;
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
    // 缓存还在加载 → 等待完成（避免用户看到空数据库的假状态）
    if (_loadingCache) {
      _showSnack('数据库列表加载中，请稍候…');
      // 等 _loadCachedDatabases 完成
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 简单轮询：最多等 2s
      for (int i = 0; i < 20 && _loadingCache; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      if (_loadingCache) {
        _showSnack('缓存加载超时，请刷新重试');
        return;
      }
    }
    if (!mounted) return;
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

/// PageView 指示器小点
class _PageDot extends StatelessWidget {
  final bool active;
  final ThemeData theme;
  const _PageDot({required this.active, required this.theme});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 6,
      height: 6,
      decoration: BoxDecoration(
        color: active
            ? theme.colorScheme.primary
            : theme.colorScheme.outline.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}