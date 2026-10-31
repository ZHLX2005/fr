import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/ui/global/notification/main.dart';
import '../../services/gallery_service.dart';
import '../../screens/profile/lab/reveal_item.dart';
import '../lab_container.dart';
import 'ai_gallery/ai_gallery_detail_page.dart';
import 'ai_gallery/ai_gallery_log.dart';
import 'ai_gallery/ai_gallery_log_page.dart';
import 'ai_gallery/ai_gallery_models.dart';
import 'ai_gallery/ai_gallery_scanner.dart';
import 'ai_gallery/ai_gallery_settings.dart';
import 'ai_gallery/ai_gallery_settings_page.dart';
import 'ai_gallery/ai_gallery_store.dart';

// ============================================================================
// Demo 注册
// ============================================================================

/// AI 自动图库 —— 最新 X 张图片按自定义提示词自动分析，
/// 列表页显示分组网格，详情页完全由 AI 返回的结构化 JSON 驱动。
class AiGalleryDemo extends DemoPage {
  @override
  String get title => 'AI 图库';

  @override
  String get slug => 'ai-gallery';

  @override
  String get description => '最新 X 张图片按提示词自动分析 · AI JSON 驱动详情';

  @override
  bool get preferFullScreen => true;

  @override
  IconData? get navIcon => Icons.auto_awesome_motion_outlined;

  @override
  Widget buildPage(BuildContext context) => const AiGalleryPage();
}

void registerAiGalleryDemo() {
  demoRegistry.register(AiGalleryDemo());
}

// ============================================================================
// 画廊主页
// ============================================================================

class AiGalleryPage extends StatefulWidget {
  const AiGalleryPage({super.key});

  @override
  State<AiGalleryPage> createState() => _AiGalleryPageState();
}

class _AiGalleryPageState extends State<AiGalleryPage>
    with SingleTickerProviderStateMixin {
  final GalleryService _galleryService = GalleryService();
  late final AiGalleryScanner _scanner = AiGalleryScanner();
  final AiGallerySettingsStore _settingsStore = AiGallerySettingsStore();
  final AiGalleryResultStore _resultStore = AiGalleryResultStore();

  AiGallerySettings _settings = const AiGallerySettings();
  Map<String, AiScanResult> _cachedResults = {};
  List<AiScanItem> _items = [];
  String _selectedGroup = '全部';

  bool _loadingSettings = true;
  bool _hasPermission = false;
  bool _permissionBlocked = false; // 被拒绝且不再弹框 → 只能去系统设置
  bool _scanning = false;
  bool _deleting = false;

  /// 多选模式：长按任意格子或点「多选」进入。
  bool _selectionMode = false;
  final Set<String> _selectedIds = <String>{};

  late final AnimationController _revealController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // load() 里会顺带把日志配置同步到运行期缓冲
    final settings = await _settingsStore.load();
    final cached = await _resultStore.loadAll();
    final state = await _galleryService.ensurePermission();
    if (!mounted) return;
    final granted = state?.hasAccess ?? false;
    setState(() {
      _settings = settings;
      _cachedResults = cached;
      _loadingSettings = false;
      _hasPermission = granted;
      _permissionBlocked =
          state == PermissionState.denied || state == PermissionState.restricted;
    });
    if (granted && settings.autoScan && settings.isConfigured) {
      unawaited(_startScan());
    }
  }

  // ── 扫描 ────────────────────────────────────────────────────

  Future<void> _startScan() async {
    if (_scanning || _deleting) return;
    if (!_settings.isConfigured) {
      await _requireConfig();
      return;
    }
    if (!_hasPermission) {
      await _retryPermission();
      if (!_hasPermission) return;
    }
    setState(() {
      _scanning = true;
      _selectionMode = false;
      _selectedIds.clear();
    });
    try {
      final items = await _scanner.scan(
        settings: _settings,
        cachedResults: _cachedResults,
        onItem: _onItem,
      );
      if (!mounted) return;
      if (items.isNotEmpty) {
        setState(() => _items = _sorted(items));
      }
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  /// 只重跑失败项（不重新取图、不动已完成的）。
  Future<void> _retryFailed() async {
    if (_scanning || _deleting) return;
    final failed = _items
        .where((it) => it.state == AiScanItemState.failed)
        .toList();
    if (failed.isEmpty) return;
    setState(() => _scanning = true);
    try {
      final concurrency = _settings.maxConcurrency.clamp(1, 8);
      var next = 0;
      Future<void> worker() async {
        while (true) {
          final i = next++;
          if (i >= failed.length) return;
          await _scanner.processItem(
            item: failed[i],
            settings: _settings,
            onItem: _onItem,
            index: i + 1,
            total: failed.length,
          );
        }
      }

      await Future.wait([for (var w = 0; w < concurrency; w++) worker()]);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _onItem(AiScanItem item) {
    if (!mounted) return;
    setState(() {
      final i = _items.indexWhere((it) => it.asset.id == item.asset.id);
      if (i >= 0) {
        _items[i] = item;
      } else {
        _items.add(item);
      }
      if (item.state == AiScanItemState.done && item.result != null) {
        _cachedResults[item.asset.id] = item.result!;
      }
    });
  }

  /// 服务层已按 createDate 倒序取图，这里再兜一层：任何来源的 item 列表
  /// 展示时都保证「最新的在最前面」。
  List<AiScanItem> _sorted(List<AiScanItem> items) {
    final copy = [...items];
    copy.sort((a, b) => b.asset.createDateTime.compareTo(a.asset.createDateTime));
    return copy;
  }

  void _stopScan() => _scanner.cancel();

  Future<void> _requireConfig() async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('还没配置 LLM'),
        content: const Text('需要填写服务地址 / API Key / 模型名称才能分析图片。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('去配置'),
          ),
        ],
      ),
    );
    if (go == true) await _openSettings();
  }

  Future<void> _retryPermission() async {
    final state = await _galleryService.ensurePermission();
    if (!mounted) return;
    setState(() {
      _hasPermission = state?.hasAccess ?? false;
      _permissionBlocked =
          state == PermissionState.denied || state == PermissionState.restricted;
    });
  }

  // ── 配置 / 日志 ─────────────────────────────────────────────

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AiGallerySettings>(
      MaterialPageRoute(
        // 关键：把当前配置带进去，否则设置页是空白默认值，一保存就把 key 清空
        builder: (_) => AiGallerySettingsPage(initial: _settings),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _settings = updated);
    if (_settings.autoScan && _settings.isConfigured && !_scanning) {
      unawaited(_startScan());
    }
  }

  Future<void> _openLog() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AiGalleryLogPage()));
  }

  Future<void> _openDetail(AiScanItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AiGalleryDetailPage(item: item)),
    );
  }

  /// 失败格子的详情：错误原文 + 重试 / 看日志。
  Future<void> _showFailure(AiScanItem item) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('这张没分析成功'),
        content: SingleChildScrollView(
          child: SelectableText(
            item.error ?? '未知错误',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('log'),
            child: const Text('查看日志'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('retry'),
            child: const Text('重试这张'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'log') {
      await _openLog();
    } else if (action == 'retry') {
      await _retryOne(item);
    }
  }

  Future<void> _retryOne(AiScanItem item) async {
    if (_scanning) return;
    setState(() => _scanning = true);
    try {
      await _scanner.processItem(
        item: item,
        settings: _settings,
        onItem: _onItem,
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  // ── 多选 / 删除 ─────────────────────────────────────────────

  void _enterSelection([String? assetId]) {
    setState(() {
      _selectionMode = true;
      if (assetId != null) _selectedIds.add(assetId);
    });
  }

  void _exitSelection() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String assetId) {
    setState(() {
      if (!_selectedIds.remove(assetId)) _selectedIds.add(assetId);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _selectAllVisible() {
    setState(() {
      final visible = _filtered.map((it) => it.asset.id).toSet();
      if (_selectedIds.containsAll(visible) && visible.isNotEmpty) {
        _selectedIds.removeAll(visible);
        if (_selectedIds.isEmpty) _selectionMode = false;
      } else {
        _selectedIds.addAll(visible);
      }
    });
  }

  /// 删除入口：先问「删记录还是连照片一起删」。
  Future<void> _deleteSelected() async {
    if (_selectedIds.isEmpty || _deleting) return;
    final count = _selectedIds.length;
    final deletePhotos = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Row(
                  children: [
                    Text(
                      '已选 $count 项',
                      style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              ListTile(
                leading: const Icon(Icons.layers_clear_outlined),
                title: const Text('只清除分析记录'),
                subtitle: const Text('照片留在相册里，下次扫描会重新分析'),
                onTap: () => Navigator.of(ctx).pop(false),
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: scheme.error,
                ),
                title: Text(
                  '从相册删除照片',
                  style: TextStyle(color: scheme.error),
                ),
                subtitle: const Text('同时清除分析记录，系统会再确认一次'),
                onTap: () => Navigator.of(ctx).pop(true),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
    if (deletePhotos == null || !mounted) return;

    if (deletePhotos) {
      final ok = await _confirmDeletePhotos(count);
      if (ok != true || !mounted) return;
    }

    var ids = _selectedIds.toList();
    setState(() => _deleting = true);
    try {
      var photoDeleted = 0;
      if (deletePhotos) {
        final deleted = await _galleryService.deleteAssets(ids);
        photoDeleted = deleted.length;
        // 用户可能在系统弹框里取消了：只处理真的删掉的那些
        ids = deleted;
      }
      final removed = await _resultStore.removeAll(ids);
      for (final id in removed) {
        _cachedResults.remove(id);
      }
      if (!mounted) return;
      // 一张都没删（系统弹框里取消了）：保留选中，让用户直接再试一次
      if (deletePhotos && ids.isEmpty) {
        _toast('没有删除照片（可能已在系统弹框里取消了）');
        return;
      }
      setState(() {
        for (final id in ids) {
          final i = _items.indexWhere((it) => it.asset.id == id);
          if (i < 0) continue;
          if (deletePhotos) {
            _items.removeAt(i);
          } else {
            _items[i] = _items[i].copyWith(
              state: AiScanItemState.pending,
              attempts: 0,
              clearError: true,
            );
          }
        }
        _selectionMode = false;
        _selectedIds.clear();
      });
      AiGalleryLog.instance.info(
        '删除',
        deletePhotos
            ? '从相册删除 $photoDeleted 张 · 清除记录 ${removed.length} 条'
            : '清除记录 ${removed.length} 条（照片保留）',
      );
      _toast(
        deletePhotos ? '已删除 $photoDeleted 张照片' : '已清除 ${removed.length} 条记录',
      );
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  Future<bool?> _confirmDeletePhotos(int count) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从相册删除？'),
        content: Text('将删除选中的 $count 张照片，这个操作不可撤销，系统随后还会再确认一次。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('继续删除'),
          ),
        ],
      ),
    );
  }

  void _toast(
    String message, {
    AppNotificationType type = AppNotificationType.info,
  }) {
    if (!mounted) return;
    AppNotification.show(context, message, type: type);
  }

  // ── 派生数据 ────────────────────────────────────────────────

  List<String> get _groups {
    final groups = <String>{'全部'};
    for (final it in _items) {
      if (it.result != null) groups.add(it.result!.group);
    }
    return groups.toList();
  }

  /// 当前选中的分组；分组因删除/重扫 消失时自动落回「全部」。
  String get _effectiveGroup =>
      _groups.contains(_selectedGroup) ? _selectedGroup : '全部';

  List<AiScanItem> get _filtered {
    final group = _effectiveGroup;
    if (group == '全部') return _items;
    return _items.where((it) => it.result?.group == group).toList();
  }

  int get _doneCount =>
      _items.where((it) => it.state == AiScanItemState.done).length;

  int get _failedCount =>
      _items.where((it) => it.state == AiScanItemState.failed).length;

  // ── 构建 ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final overlay = scheme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light
        : SystemUiOverlayStyle.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlay,
      child: Scaffold(
        backgroundColor: scheme.surfaceContainerLowest,
        body: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_hasPermission) {
      return _PermissionGate(
        blocked: _permissionBlocked,
        onRetry: _retryPermission,
        onOpenSystemSettings: () async {
          await _galleryService.openSettings();
          await _retryPermission();
        },
      );
    }
    final list = _filtered;
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _GalleryHeader(
            scanning: _scanning,
            selectionMode: _selectionMode,
            selectedCount: _selectedIds.length,
            allVisibleSelected: list.isNotEmpty &&
                _selectedIds.containsAll(list.map((it) => it.asset.id)),
            progressText: _items.isNotEmpty
                ? '$_doneCount/${_items.length} 已分析'
                : '最新 ${_settings.scanCount}张',
            onTapBack: () =>
                _selectionMode ? _exitSelection() : Navigator.of(context).maybePop(),
            onTapSettings: _openSettings,
            onTapScan: _scanning ? _stopScan : _startScan,
            onExitSelection: _exitSelection,
            onSelectAll: _selectAllVisible,
            onDeleteSelected: _deleteSelected,
            deleting: _deleting,
          ),
          _GroupChips(
            groups: _groups,
            selected: _effectiveGroup,
            onSelected: (g) => setState(() => _selectedGroup = g),
            onTapMultiSelect: _items.isEmpty
                ? null
                : () => _selectionMode ? _exitSelection() : _enterSelection(),
            selectionMode: _selectionMode,
          ),
          if (_failedCount > 0 && !_selectionMode && !_scanning)
            _FailureBar(
              count: _failedCount,
              onRetry: _retryFailed,
              onOpenLog: _openLog,
            ),
          Expanded(child: _buildGrid(list)),
        ],
      ),
    );
  }

  Widget _buildGrid(List<AiScanItem> list) {
    if (_items.isEmpty && !_scanning) {
      return _EmptyState(
        configured: _settings.isConfigured,
        onOpenSettings: _openSettings,
        onOpenLog: _openLog,
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          '该分组暂无图片',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.72,
      ),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final id = item.asset.id;
        return RevealItem(
          index: index,
          controller: _revealController,
          child: _GalleryCell(
            item: item,
            selectionMode: _selectionMode,
            selected: _selectedIds.contains(id),
            onTap: () {
              if (_selectionMode) {
                _toggleSelected(id);
              } else if (item.state == AiScanItemState.done) {
                _openDetail(item);
              } else if (item.state == AiScanItemState.failed) {
                _showFailure(item);
              }
            },
            onLongPress: () {
              if (_selectionMode) {
                _toggleSelected(id);
              } else {
                _enterSelection(id);
              }
            },
          ),
        );
      },
    );
  }
}

// ============================================================================
// 头部（圆钮返回 + 大标题 + 进度 + 扫描 + 配置；多选时整体切换成选择栏）
// ============================================================================

class _GalleryHeader extends StatelessWidget {
  final bool scanning;
  final bool selectionMode;
  final int selectedCount;
  final bool allVisibleSelected;
  final String progressText;
  final bool deleting;
  final VoidCallback onTapBack;
  final VoidCallback onTapSettings;
  final VoidCallback onTapScan;
  final VoidCallback onExitSelection;
  final VoidCallback onSelectAll;
  final VoidCallback onDeleteSelected;

  const _GalleryHeader({
    required this.scanning,
    required this.selectionMode,
    required this.selectedCount,
    required this.allVisibleSelected,
    required this.progressText,
    required this.deleting,
    required this.onTapBack,
    required this.onTapSettings,
    required this.onTapScan,
    required this.onExitSelection,
    required this.onSelectAll,
    required this.onDeleteSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (selectionMode) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            _CircleIconButton(
              icon: Icons.close_rounded,
              semanticLabel: '退出多选',
              onTap: onExitSelection,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '已选 $selectedCount 项',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TextButton(
              onPressed: onSelectAll,
              child: Text(allVisibleSelected ? '取消全选' : '全选'),
            ),
            const SizedBox(width: 4),
            // 删除只做描边 + 错误色文字，页面上唯一的实心色块留给右下扫描钮
            OutlinedButton.icon(
              onPressed: selectedCount == 0 || deleting
                  ? null
                  : onDeleteSelected,
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(
                  color: selectedCount == 0
                      ? scheme.outlineVariant
                      : scheme.error.withValues(alpha: 0.6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                minimumSize: const Size(0, 36),
                visualDensity: VisualDensity.compact,
              ),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('删除'),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          _CircleIconButton(
            icon: Icons.arrow_back_ios_new_rounded,
            semanticLabel: '返回',
            onTap: onTapBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'AI 图库',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  progressText,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          // 扫描 / 停止 —— 全页唯一的实心强调色块
          _CircleIconButton(
            icon: scanning ? Icons.stop_rounded : Icons.radar_rounded,
            semanticLabel: scanning ? '停止扫描' : '开始扫描',
            filled: true,
            onTap: onTapScan,
          ),
          const SizedBox(width: 8),
          _CircleIconButton(
            icon: Icons.tune_rounded,
            semanticLabel: '配置',
            onTap: onTapSettings,
          ),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool filled;

  const _CircleIconButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: Material(
        color: filled ? scheme.primary : scheme.surfaceContainerHigh,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(
              icon,
              size: 19,
              color: filled ? scheme.onPrimary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// 分组 chips（选中只描边，不做实心块）
// ============================================================================

class _GroupChips extends StatelessWidget {
  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelected;
  final VoidCallback? onTapMultiSelect;
  final bool selectionMode;

  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.onSelected,
    required this.onTapMultiSelect,
    required this.selectionMode,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              scrollDirection: Axis.horizontal,
              itemCount: groups.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final g = groups[i];
                final isSel = g == selected;
                return Semantics(
                  selected: isSel,
                  button: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => onSelected(g),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel
                            ? scheme.primary.withValues(alpha: 0.08)
                            : scheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: isSel
                              ? scheme.primary.withValues(alpha: 0.55)
                              : Colors.transparent,
                        ),
                      ),
                      child: Text(
                        g,
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: isSel
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                          fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              onPressed: onTapMultiSelect,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                foregroundColor: selectionMode
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
              ),
              icon: Icon(
                selectionMode
                    ? Icons.done_all_rounded
                    : Icons.checklist_rounded,
                size: 16,
              ),
              label: Text(selectionMode ? '完成' : '多选'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 失败提示条（有条失败才出现：一条路径直达重试与日志）
// ============================================================================

class _FailureBar extends StatelessWidget {
  final int count;
  final VoidCallback onRetry;
  final VoidCallback onOpenLog;

  const _FailureBar({
    required this.count,
    required this.onRetry,
    required this.onOpenLog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
      child: Container(
        padding: const EdgeInsets.only(left: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.error.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, size: 16, color: scheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count 张分析失败',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            TextButton(
              onPressed: onOpenLog,
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              child: const Text('日志'),
            ),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: scheme.primary,
              ),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// 网格单元（四态：分析中 / 失败 / 待分析 / 已完成 + 选中环）
// ============================================================================

class _GalleryCell extends StatelessWidget {
  final AiScanItem item;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _GalleryCell({
    required this.item,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final showDone = item.state == AiScanItemState.done && item.result != null;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          // 选中环固定 2px 宽（未选中用透明色），避免勾选时格子内容跳动
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 缩略图（photo_manager 原生缩图 → Image.memory）
              FutureBuilder<Uint8List?>(
                future: item.asset.thumbnailDataWithSize(
                  const ThumbnailSize(300, 420),
                ),
                builder: (context, snap) {
                  final data = snap.data;
                  if (snap.connectionState != ConnectionState.done ||
                      data == null) {
                    return ColoredBox(color: scheme.surfaceContainerHigh);
                  }
                  return Image.memory(
                    data,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  );
                },
              ),
              // 状态遮罩
              if (item.state == AiScanItemState.analyzing)
                _StateOverlay(
                  background: scheme.scrim.withValues(alpha: 0.45),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.onPrimary,
                    ),
                  ),
                )
              else if (item.state == AiScanItemState.pending)
                _StateOverlay(
                  background: scheme.scrim.withValues(alpha: 0.30),
                  child: Icon(
                    Icons.hourglass_empty_rounded,
                    size: 18,
                    color: scheme.onPrimary.withValues(alpha: 0.85),
                  ),
                )
              else if (item.state == AiScanItemState.failed)
                // 失败态用「暗底 + 错误色图标 + 细边框」，不铺整块 errorContainer
                Container(
                  decoration: BoxDecoration(
                    color: scheme.scrim.withValues(alpha: 0.45),
                    border: Border.all(
                      color: scheme.error.withValues(alpha: 0.8),
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Icon(
                      Icons.error_outline_rounded,
                      size: 20,
                      color: scheme.error,
                    ),
                  ),
                ),
              // 底部信息条（仅已完成）
              if (showDone)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          scheme.scrim.withValues(alpha: 0),
                          scheme.scrim.withValues(alpha: 0.65),
                        ],
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.result!.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: scheme.onPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (item.result!.isImportant) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.priority_high_rounded,
                            size: 12,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              // 多选勾选圈（描边，不填色）
              if (selectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // 勾选圈只描边不填色：多选时会同时出现很多个，
                      // 一旦填主色就等于一屏色块，破坏「一页一块」的规则
                      color: selected
                          ? scheme.surface
                          : scheme.scrim.withValues(alpha: 0.35),
                      border: Border.all(
                        color: selected ? scheme.primary : scheme.onPrimary,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: scheme.primary,
                          )
                        : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StateOverlay extends StatelessWidget {
  final Color background;
  final Widget child;

  const _StateOverlay({required this.background, required this.child});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: Center(child: child),
    );
  }
}

// ============================================================================
// 空态 / 权限
// ============================================================================

class _EmptyState extends StatelessWidget {
  final bool configured;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenLog;

  const _EmptyState({
    required this.configured,
    required this.onOpenSettings,
    required this.onOpenLog,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_awesome_motion_outlined,
              size: 52,
              color: scheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 14),
            Text(
              configured ? '点击右上角雷达开始扫描' : '先在配置页填好 LLM 服务',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              configured
                  ? '分析最新的若干张图片 · 长按图片可多选删除'
                  : '协议 / 地址 / Key / 模型 / 提示词 / 数量',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                if (!configured)
                  OutlinedButton(
                    onPressed: onOpenSettings,
                    child: const Text('去配置'),
                  ),
                OutlinedButton.icon(
                  onPressed: onOpenLog,
                  icon: const Icon(Icons.receipt_long_outlined, size: 16),
                  label: const Text('运行日志'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  final bool blocked;
  final VoidCallback onRetry;
  final VoidCallback onOpenSystemSettings;

  const _PermissionGate({
    required this.blocked,
    required this.onRetry,
    required this.onOpenSystemSettings,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 52,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 14),
            Text(
              blocked ? '相册权限已被拒绝' : '需要相册访问权限',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              blocked
                  ? '请到系统设置里允许访问照片后再回来'
                  : '只读取图片，用于本地分析（不会上传原图）',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: [
                if (blocked)
                  OutlinedButton(
                    onPressed: onOpenSystemSettings,
                    child: const Text('去系统设置'),
                  ),
                OutlinedButton(
                  onPressed: onRetry,
                  child: const Text('重新申请'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
