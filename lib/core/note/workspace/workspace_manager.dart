import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../blocks/block.dart';
import '../blocks/block_id.dart';
import '../blocks/block_editor_controller.dart';
import '../blocks/block_tree.dart';
import '../blocks/block_type.dart';
import 'page_model.dart';

/// 工作区管理器
///
/// 管理多个 Page，每个 Page 是一个独立的 BlockTree。
/// 磁盘布局：
///   [app_doc]/note_workspace/
///     workspace.json          — 页面索引
///     pages/[pageId].json     — 每个页面的 Block 树
class WorkspaceManager {
  final Map<String, PageModel> _pages = {};
  final List<String> _pageOrder = [];
  String? _activePageId;
  bool _initialized = false;

  // 自动保存
  StreamSubscription? _treeSub;
  Timer? _saveDebounce;

  // ──────────── 查询 ────────────

  List<PageModel> get pages => _pageOrder.map((id) => _pages[id]!).toList();
  PageModel? get activePage => _activePageId != null ? _pages[_activePageId!] : null;
  String? get activePageId => _activePageId;
  bool get initialized => _initialized;

  // ──────────── 初始化 / 持久化 ────────────

  /// 从磁盘加载工作区。首次使用则创建默认页面。
  Future<void> init() async {
    final dir = await _ensureStorageDir();
    final workspaceFile = File('$dir/workspace.json');

    if (await workspaceFile.exists()) {
      await _loadFromDisk(dir, workspaceFile);
    } else {
      _createDefaultPage();
    }
    _initialized = true;
    _startAutoSave();
  }

  /// 释放资源（切换页面时由 Provider 调用）
  void dispose() {
    _stopAutoSave();
  }

  Future<String> _ensureStorageDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/note_workspace/pages');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.parent.path;
  }

  Future<void> _loadFromDisk(String dir, File workspaceFile) async {
    try {
      final json = jsonDecode(await workspaceFile.readAsString()) as Map<String, dynamic>;
      final order = List<String>.from(json['page_order'] ?? []);
      _activePageId = json['active_page_id'] as String?;

      for (final pageId in order) {
        final pageFile = File('$dir/pages/$pageId.json');
        if (await pageFile.exists()) {
          final pageJson = jsonDecode(await pageFile.readAsString()) as Map<String, dynamic>;
          final page = _pageFromJson(pageJson);
          _pages[pageId] = page;
          _pageOrder.add(pageId);
        }
      }

      // 如果没有成功加载任何页面，创建默认页
      if (_pageOrder.isEmpty) {
        _createDefaultPage();
      }
    } catch (e) {
      _createDefaultPage();
    }
  }

  // ──────────── 页面 CRUD ────────────

  /// 创建新页面并切换过去
  PageModel createPage({String? title}) {
    final id = BlockId.generate();
    final controller = BlockEditorController();
    controller.tree.insert(
      Block(id: BlockId.generate(), type: BlockType.paragraph),
      parentId: BlockTree.rootId,
    );
    final page = PageModel(id: id, title: title ?? '未命名笔记', controller: controller);
    _pages[id] = page;
    _pageOrder.add(id);
    _activePageId = id;
    _rebindAutoSave();
    _persist();
    _persistPage(page);
    return page;
  }

  /// 切换到指定页面
  void switchPage(String id) {
    if (_pages.containsKey(id)) {
      _activePageId = id;
      _rebindAutoSave();
    }
  }

  /// 删除页面
  void deletePage(String id) {
    if (!_pages.containsKey(id)) return;
    final wasActive = _activePageId == id;
    _pages.remove(id);
    _pageOrder.remove(id);
    if (wasActive) {
      _activePageId = _pageOrder.isNotEmpty ? _pageOrder.last : null;
      if (_activePageId != null) _rebindAutoSave();
    }
    _persist();
    _deletePageFile(id);
  }

  // ──────────── 工作区概览（供 AI 上下文使用）────────────

  /// 构建工作区页面列表概览
  String buildWorkspaceOverview() {
    final buf = StringBuffer();
    buf.writeln('工作区共有 ${_pageOrder.length} 个页面：');
    for (final id in _pageOrder) {
      final page = _pages[id]!;
      final isActive = id == _activePageId ? ' ← 当前页面' : '';
      buf.writeln('- ${page.title} (id: $id)$isActive');
    }
    return buf.toString();
  }

  // ──────────── AI 命令（已弃用，保留向后兼容）────────────

  /// 处理自然语言 AI 命令（统一入口）
  ///
  /// 先匹配工作区级命令（创建页面等），
  /// 再回退到当前页面的 AiAgent 处理块级操作。
  Future<String> processAiCommand(String command, {String? selectedBlockId}) async {
    final lower = command.trim().toLowerCase();

    if (lower.startsWith('创建页面') || lower.startsWith('新建页面') || lower.startsWith('create page')) {
      final title = command.replaceFirst(RegExp(r'^(创建页面|新建页面|create page)\s*', caseSensitive: false), '').trim();
      final page = createPage(title: title.isNotEmpty ? title : '未命名笔记');
      return '✅ 已创建页面「${page.title}」';
    }

    if (activePage != null) {
      final result = activePage!.controller.aiAgent.simulateCommand(
        command,
        selectedId: selectedBlockId,
      );
      return result.summary.isNotEmpty ? result.summary : '已完成';
    }

    return '没有打开的页面';
  }

  // ──────────── 自动保存 ────────────

  void _startAutoSave() {
    _rebindAutoSave();
  }

  void _stopAutoSave() {
    _saveDebounce?.cancel();
    _saveDebounce = null;
    _treeSub?.cancel();
    _treeSub = null;
  }

  /// 重新绑定自动保存监听器（切换页面时调用）
  void _rebindAutoSave() {
    _treeSub?.cancel();
    _treeSub = null;

    final page = activePage;
    if (page == null) return;

    _treeSub = page.controller.tree.changes.listen((_) => _debounceSave());
  }

  void _debounceSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(seconds: 2), () {
      final page = activePage;
      if (page != null) {
        page.updatedAt = DateTime.now();
        _persistPage(page);
      }
    });
  }

  // ──────────── 持久化 I/O ────────────

  void _persist() {
    _saveWorkspaceFile();
  }

  void _persistPage(PageModel page) {
    _savePageFile(page);
  }

  void _saveWorkspaceFile() async {
    try {
      final dir = await _ensureStorageDir();
      final file = File('$dir/workspace.json');
      await file.writeAsString(jsonEncode({
        'page_order': _pageOrder,
        'active_page_id': _activePageId,
      }));
    } catch (_) {}
  }

  void _savePageFile(PageModel page) async {
    try {
      final dir = await _ensureStorageDir();
      final file = File('$dir/pages/${page.id}.json');
      await file.writeAsString(jsonEncode(_pageToJson(page)));
    } catch (_) {}
  }

  void _deletePageFile(String pageId) async {
    try {
      final dir = await _ensureStorageDir();
      final file = File('$dir/pages/$pageId.json');
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  Map<String, dynamic> _pageToJson(PageModel page) {
    return {
      'id': page.id,
      'title': page.title,
      'created_at': page.createdAt.millisecondsSinceEpoch,
      'updated_at': page.updatedAt.millisecondsSinceEpoch,
      'blocks': _serializeBlocks(page.controller.tree),
    };
  }

  List<Map<String, dynamic>> _serializeBlocks(BlockTree tree) {
    final blocks = <Map<String, dynamic>>[];
    for (final childId in tree.childIdsOf(BlockTree.rootId)) {
      blocks.add(_buildNestedJson(tree, childId));
    }
    return blocks;
  }

  Map<String, dynamic> _buildNestedJson(BlockTree tree, String blockId) {
    final block = tree.get(blockId)!;
    return {
      'id': block.id,
      'type': block.type.tag,
      'content': block.content.toJson(),
      'children': tree.childIdsOf(blockId).map((cid) => _buildNestedJson(tree, cid)).toList(),
      'data': block.data.toMap(),
      'properties': Map.of(block.properties),
      'created_at': block.createdAt.millisecondsSinceEpoch,
      'updated_at': block.updatedAt.millisecondsSinceEpoch,
    };
  }

  PageModel _pageFromJson(Map<String, dynamic> json) {
    final id = json['id'] as String;
    final title = json['title'] as String? ?? '未命名笔记';
    final controller = BlockEditorController();
    final blocks = json['blocks'] as List<dynamic>? ?? [];

    final blockList = blocks.cast<Map<String, dynamic>>();
    for (final blockJson in blockList) {
      final block = Block.fromJson(blockJson);
      _insertBlockTree(controller.tree, block, BlockTree.rootId);
    }

    if (controller.tree.size <= 1) {
      controller.tree.insert(
        Block(id: BlockId.generate(), type: BlockType.paragraph),
        parentId: BlockTree.rootId,
      );
    }

    return PageModel(
      id: id,
      title: title,
      controller: controller,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['created_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch),
    );
  }

  void _insertBlockTree(BlockTree tree, Block block, String parentId) {
    tree.insert(block, parentId: parentId);
    for (final child in block.children) {
      _insertBlockTree(tree, child, block.id);
    }
  }

  void _createDefaultPage() {
    createPage(title: '未命名笔记');
  }
}
