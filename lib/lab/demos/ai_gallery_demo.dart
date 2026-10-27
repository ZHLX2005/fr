import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../services/gallery_service.dart';
import '../../screens/profile/lab/reveal_item.dart';
import '../lab_container.dart';
import 'ai_gallery/ai_gallery_models.dart';
import 'ai_gallery/ai_gallery_scanner.dart';
import 'ai_gallery/ai_gallery_settings.dart';
import 'ai_gallery/ai_gallery_settings_page.dart';
import 'ai_gallery/ai_gallery_detail_page.dart';
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
  bool _scanning = false;
  bool _assetsLoaded = false;

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
    _settings = await _settingsStore.load();
    _cachedResults = await _resultStore.loadAll();
    final perm = await _galleryService.checkPermission();
    if (!mounted) return;
    setState(() {
      _settings = _settings;
      _loadingSettings = false;
      _hasPermission = perm;
    });
    if (_settings.autoScan && _settings.isConfigured && perm) {
      unawaited(_startScan());
    }
  }

  Future<void> _startScan() async {
    if (_scanning || !_settings.isConfigured) return;
    setState(() => _scanning = true);
    try {
      final items = await _scanner.scan(
        settings: _settings,
        cachedResults: _cachedResults,
        onItem: (item) {
          if (!mounted) return;
          setState(() {
            final i = _items.indexWhere((it) => it.asset.id == item.asset.id);
            if (i >= 0) {
              _items[i] = item;
            } else {
              _items.add(item);
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _items = items;
        _assetsLoaded = true;
      });
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  void _stopScan() {
    _scanner.cancel();
  }

  Future<void> _openSettings() async {
    final updated = await Navigator.of(context).push<AiGallerySettings>(
      MaterialPageRoute(builder: (_) => const AiGallerySettingsPage()),
    );
    if (updated == null) return;
    setState(() => _settings = updated);
    // 关键配置变化后失效缓存结果并自动重扫
    if (_settings.autoScan && _settings.isConfigured) {
      unawaited(_startScan());
    }
  }

  Future<void> _openDetail(AiScanItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AiGalleryDetailPage(item: item),
      ),
    );
  }

  List<String> get _groups {
    final groups = <String>{'全部'};
    for (final it in _items) {
      if (it.result != null) groups.add(it.result!.group);
    }
    return groups.toList();
  }

  List<AiScanItem> get _filtered {
    if (_selectedGroup == '全部') return _items;
    return _items
        .where((it) => it.result?.group == _selectedGroup)
        .toList();
  }

  int get _doneCount =>
      _items.where((it) => it.state == AiScanItemState.done).length;

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
      return _PermissionGate(onRetry: _init);
    }
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _GalleryHeader(
            scanning: _scanning,
            progressText: _assetsLoaded || _items.isNotEmpty
                ? '$_doneCount/${_items.length} 已分析'
                : '最新 ${_settings.scanCount}张',
            onTapBack: () => Navigator.of(context).maybePop(),
            onTapSettings: _openSettings,
            onTapScan: _scanning ? _stopScan : _startScan,
          ),
          _GroupChips(
            groups: _groups,
            selected: _selectedGroup,
            onSelected: (g) => setState(() => _selectedGroup = g),
          ),
          Expanded(child: _buildGrid()),
        ],
      ),
    );
  }

  Widget _buildGrid() {
    if (_items.isEmpty && !_scanning) {
      return _EmptyState(
        configured: _settings.isConfigured,
        onOpenSettings: _openSettings,
      );
    }
    final list = _filtered;
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
        return RevealItem(
          index: index,
          controller: _revealController,
          child: _GalleryCell(
            item: list[index],
            onTap: () => _openDetail(list[index]),
          ),
        );
      },
    );
  }
}

// ============================================================================
// 头部（苹果质感：圆钮返回 + 大标题 + 进度胶囊 + 齿轮）
// ============================================================================

class _GalleryHeader extends StatelessWidget {
  final bool scanning;
  final String progressText;
  final VoidCallback onTapBack;
  final VoidCallback onTapSettings;
  final VoidCallback onTapScan;

  const _GalleryHeader({
    required this.scanning,
    required this.progressText,
    required this.onTapBack,
    required this.onTapSettings,
    required this.onTapScan,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          // 返回圆钮
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
          // 扫描 / 停止
          _CircleIconButton(
            icon: scanning
                ? Icons.stop_rounded
                : Icons.radar_rounded,
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
        color: filled
            ? scheme.primary
            : scheme.surfaceContainerHigh,
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
// 分组 chips
// ============================================================================

class _GroupChips extends StatelessWidget {
  final List<String> groups;
  final String selected;
  final ValueChanged<String> onSelected;

  const _GroupChips({
    required this.groups,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
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
                      ? scheme.primary
                      : scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  g,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color:
                            isSel ? scheme.onPrimary : scheme.onSurfaceVariant,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                      ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ============================================================================
// 网格单元（四态：分析中 / 失败 / 待分析 / 已完成）
// ============================================================================

class _GalleryCell extends StatelessWidget {
  final AiScanItem item;
  final VoidCallback onTap;

  const _GalleryCell({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: item.state == AiScanItemState.done ? onTap : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
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
                return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
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
              _StateOverlay(
                background: scheme.errorContainer.withValues(alpha: 0.88),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 18,
                  color: scheme.onErrorContainer,
                ),
              ),
            // 底部信息条（仅已完成）
            if (item.state == AiScanItemState.done && item.result != null)
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
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
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
                    ],
                  ),
                ),
              ),
          ],
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

  const _EmptyState({required this.configured, required this.onOpenSettings});

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
                  ? '将自动分析最新 X 张图片'
                  : '协议 / 地址 / Key / 模型 / 提示词 / 数量',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            if (!configured) ...[
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: onOpenSettings,
                child: const Text('去配置'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PermissionGate extends StatelessWidget {
  final VoidCallback onRetry;

  const _PermissionGate({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.photo_library_outlined,
            size: 52,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 14),
          const Text('需要相册访问权限'),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('重试')),
        ],
      ),
    );
  }
}
