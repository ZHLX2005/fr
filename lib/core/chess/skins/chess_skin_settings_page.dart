// lib/core/chess/skins/chess_skin_settings_page.dart
//
// 全屏换肤设置页 — 左侧皮肤列表 + 自定义棋盘颜色 + 右侧实时棋盘预览。
//
// 布局（桌面/平板可两栏；手机窄屏自动降级为竖排单栏）：
//   AppBar(title: '棋盘皮肤', leading: BackButton)
//   body（宽屏 ≥600）: Row(
//     left:  皮肤列表 + 自定义棋盘颜色（整体可滚动）
//     right: 实时预览（选中皮肤的 ChessBoard + 初始局面，配色实时反映）
//   )
//   body（窄屏 <600）: Column(
//     top:    横向皮肤缩略图条（横向滚动）
//     mid:    自定义棋盘颜色（紧凑排版）
//     bottom: 实时棋盘预览 + 选中皮肤名提示
//   )
//
// 返回语义：
//   · 皮肤：返回箭头（AppBar leading）→ pop(_selectedId) 应用当前选中皮肤；
//     系统返回手势 / 首页 back 键 → 同上（经 PopScope 拦截转成携带 _selectedId）
//   · 自定义棋盘颜色：不走返回值 —— 点选即通过 [onPaletteChanged] 实时回调
//     调用方（父级立即 setState + BoardColorPrefs 持久化），无需等返回。
//     优先级：BoardPalette（用户自定义） > context.chessColors（主题）。
//
// 颜色走 context.chessColors（v6.2.1 主题通道）；棋子图像用
// ChessSkinBundle.byId(id) 解析（含 default → unicode 回退）。

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../models/board_state.dart';
import '../models/piece.dart';
import '../widgets/board_palette.dart';
import '../widgets/chess_board.dart';
import 'chess_skin.dart';
import 'chess_skin_meta.dart';
import 'chess_skin_meta_sync.dart';
import 'local_chess_skin.dart';

/// 全屏换肤设置页 — 左侧皮肤列表 + 自定义棋盘颜色 + 右侧实时棋盘预览。
class ChessSkinSettingsPage extends StatefulWidget {
  const ChessSkinSettingsPage({
    super.key,
    required this.initialSkinId,
    this.initialPalette,
    this.onPaletteChanged,
    this.localSkins = const {},
    this.onRequestDownload,
    this.isDownloading,
    this.downloadError,
    this.onRetryDownload,
  });

  /// 进入页面时选中的皮肤 id（由调用方传入，通常是已持久化的值）。
  final String initialSkinId;

  /// 进入页面时的自定义棋盘配色（null = 跟随主题）。
  final BoardPalette? initialPalette;

  /// 用户改动自定义配色时实时回调（null = 清除自定义，跟随主题）。
  ///
  /// 即时触发（不等返回箭头）—— 调用方据此 setState 更新对弈棋盘 +
  /// BoardColorPrefs 持久化。null = 未提供（页面仍可预览，不改外部状态）。
  final ValueChanged<BoardPalette?>? onPaletteChanged;

  /// 调用方已本地化的皮肤（id → LocalChessSkin）。预览优先用本地文件渲染。
  final Map<String, LocalChessSkin> localSkins;

  /// 点击皮肤时触发下载（由调用方拥有 localizer，异步下载后更新 [localSkins]）。
  /// null → 预览回退 [ChessSkinBundle.byId]（网络皮肤 / unicode）。
  final void Function(String skinId)? onRequestDownload;

  /// 查询某皮肤是否正在下载中（显示 loading）。
  final bool Function(String skinId)? isDownloading;

  /// 查询某皮肤上次下载的错误信息（null = 无错误；显示"下载失败 + 重试"）。
  final String? Function(String skinId)? downloadError;

  /// 点击"重试"按钮时触发重新下载（通常与 [onRequestDownload] 同一实现）。
  final void Function(String skinId)? onRetryDownload;

  /// 两栏布局分界宽度（≥此值用 Row 两栏，否则竖排单栏）。
  static const double kWideBreakpoint = 600;

  @override
  State<ChessSkinSettingsPage> createState() => _ChessSkinSettingsPageState();
}

class _ChessSkinSettingsPageState extends State<ChessSkinSettingsPage> {
  /// 当前选中皮肤 id（初始 = 进入页面前的皮肤）。
  late String _selectedId;

  /// 当前自定义棋盘配色（null = 跟随主题；点选预设/自定义色实时更新）。
  BoardPalette? _palette;

  /// KV 皮肤加载状态：true=正在拉取 / false=已完成（成功或回退）。
  bool _kvLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSkinId;
    _palette = widget.initialPalette;
    // 方案A：每次进入换肤页按需拉取 KV index（后台，5s 超时 best-effort）。
    // 初始列表 7 套（const catalog）；KV 返回后 setState 追加新皮肤（"闪增"）。
    // 不在 main/demo 启动期拉取，避免冷启动网络请求。
    _fetchKvSkins();
  }

  Future<void> _fetchKvSkins() async {
    final merged = await fetchAndMergeSkins().catchError((Object _) => false);
    if (!mounted) return;
    setState(() => _kvLoading = false);
    // 若 KV 同 id 覆盖了当前选中皮肤，通知 demo 层 re-prefetch 新 fileId
    // （旧缓存按新 fileId 校验会 miss → 重下新图）。
    if (merged == true && widget.localSkins[_selectedId] == null) {
      // 轻量 re-check：若 demo 层传入的 localSkins 未覆盖当前选中，触发一次下载。
      widget.onRequestDownload?.call(_selectedId);
    }
  }

  /// 返回箭头：把当前选中的皮肤 id 带回调用方（应用 + 持久化由调用方完成）。
  /// 自定义配色不走返回值（点选时已实时回调过调用方）。
  void _popWithSelection() {
    Navigator.of(context).pop(_selectedId);
  }

  /// 皮肤条目点击：切换选中态 + 触发调用方下载（异步，预览下载完成后刷新）。
  void _selectSkin(String id) {
    if (id == _selectedId) return;
    setState(() => _selectedId = id);
    // 已本地化的皮肤无需再下载；未本地化 → 通知调用方异步下载。
    if (!widget.localSkins.containsKey(id)) {
      widget.onRequestDownload?.call(id);
    }
  }

  /// 应用自定义配色：预览实时刷新 + 通知调用方（持久化 + 应用到对弈棋盘）。
  void _applyPalette(BoardPalette? palette) {
    setState(() => _palette = palette);
    widget.onPaletteChanged?.call(palette);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return PopScope(
      // 拦截系统返回（手势 / 首页键）→ 也携带当前选中皮肤返回，保证"选完即生效"。
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithSelection();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: AppBar(
          title: const Text('棋盘皮肤'),
          backgroundColor: Theme.of(context).colorScheme.surface,
          // 返回箭头：pop 携带当前选中皮肤 id（"选完即生效"）。
          leading: BackButton(onPressed: _popWithSelection),
          bottom: _kvLoading
              ? const PreferredSize(
                  preferredSize: Size.fromHeight(2),
                  child: LinearProgressIndicator(minHeight: 2),
                )
              : null,
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= ChessSkinSettingsPage.kWideBreakpoint;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：皮肤列表 + 自定义棋盘颜色（整体可滚动）
                  SizedBox(
                    width: 280,
                    child: _LeftPanel(
                      selectedId: _selectedId,
                      onSelectSkin: _selectSkin,
                      localSkins: widget.localSkins,
                      palette: _palette,
                      onSelectPalette: _applyPalette,
                    ),
                  ),
                  // 右侧：实时棋盘预览
                  Expanded(
                    child: _SkinPreview(
                      skinId: _selectedId,
                      localSkins: widget.localSkins,
                      boardPalette: _palette,
                      isDownloading:
                          widget.isDownloading?.call(_selectedId) ?? false,
                      downloadError: widget.downloadError?.call(_selectedId),
                      onRetry: widget.onRetryDownload,
                    ),
                  ),
                ],
              );
            }
            // 窄屏：竖排 — 顶部横向皮肤条 + 自定义颜色 + 底部预览。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SkinStrip(
                  selectedId: _selectedId,
                  onSelect: _selectSkin,
                  localSkins: widget.localSkins,
                ),
                _ColorSection(
                  palette: _palette,
                  onSelect: _applyPalette,
                ),
                Expanded(
                  child: _SkinPreview(
                    skinId: _selectedId,
                    localSkins: widget.localSkins,
                    boardPalette: _palette,
                    isDownloading:
                        widget.isDownloading?.call(_selectedId) ?? false,
                    downloadError: widget.downloadError?.call(_selectedId),
                    onRetry: widget.onRetryDownload,
                  ),
                ),
              ],
            );
          },
        ),
        // 底部安全区提示（说明返回箭头即应用）
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              '点击左侧皮肤实时预览 · 返回箭头即应用所选皮肤',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.coordinateLabel),
            ),
          ),
        ),
      ),
    );
  }
}

/// 左侧面板（宽屏）：皮肤列表 + 自定义棋盘颜色（SingleChildScrollView 整体滚动）。
///
/// 用 Column（非 ListView.builder）让所有皮肤条目常驻 build ——
/// finder / 测试可见性与滚动位置无关。
class _LeftPanel extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelectSkin;
  final Map<String, LocalChessSkin> localSkins;
  final BoardPalette? palette;
  final ValueChanged<BoardPalette?> onSelectPalette;

  const _LeftPanel({
    required this.selectedId,
    required this.onSelectSkin,
    required this.localSkins,
    required this.palette,
    required this.onSelectPalette,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    // Fix A：皮肤列表遍历 live [ChessSkinBundle.metas]（KV 合入的新皮肤实时可见），
    // 而非 const `kChessSkinsCatalog`（编译期快照，看不到 KV 追加）。
    final metas = ChessSkinBundle.metas;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < metas.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: colors.gridLine.withValues(alpha: 0.3)),
            _SkinTile(
              meta: metas[i],
              isSelected: metas[i].id == selectedId,
              localSkins: localSkins,
              onTap: () => onSelectSkin(metas[i].id),
            ),
          ],
          Divider(height: 1, color: colors.gridLine.withValues(alpha: 0.3)),
          // 自定义棋盘颜色区（优先级：用户自定义 > 主题）
          _ColorSection(palette: palette, onSelect: onSelectPalette),
        ],
      ),
    );
  }
}

/// 单个皮肤条目：wK 缩略图 + 显示名 + 选中勾。
class _SkinTile extends StatelessWidget {
  final ChessSkinMeta meta;
  final bool isSelected;
  final Map<String, LocalChessSkin> localSkins;
  final VoidCallback onTap;

  const _SkinTile({
    required this.meta,
    required this.isSelected,
    required this.localSkins,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    // 缩略图优先本地皮肤（离线可用）；未本地化回退注册表。
    final skin = localSkins[meta.id] ?? ChessSkinBundle.byId(meta.id);
    return ListTile(
      leading: _SkinThumb(skin: skin),
      title: Text(meta.displayName),
      trailing: isSelected
          ? Icon(Icons.check_circle, color: colors.checkWarning)
          : null,
      selected: isSelected,
      selectedTileColor: colors.lightSquare.withValues(alpha: 0.35),
      onTap: onTap,
    );
  }
}

/// 窄屏顶部横向皮肤条：一排 wK 缩略图（选中带勾 + 高亮边框）。
class _SkinStrip extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Map<String, LocalChessSkin> localSkins;

  const _SkinStrip({
    required this.selectedId,
    required this.onSelect,
    this.localSkins = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    // Fix A：横向缩略图条同样遍历 live [ChessSkinBundle.metas]
    // （KV 合入的新皮肤在窄屏也能看到）。
    final metas = ChessSkinBundle.metas;
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: metas.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final meta = metas[i];
          final isSelected = meta.id == selectedId;
          final skin = localSkins[meta.id] ?? ChessSkinBundle.byId(meta.id);
          return InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => onSelect(meta.id),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? colors.lightSquare.withValues(alpha: 0.35)
                    : null,
                border: Border.all(
                  color: isSelected ? colors.checkWarning : colors.gridLine,
                  width: isSelected ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                children: [
                  Center(child: _SkinThumb(skin: skin, size: 32)),
                  if (isSelected)
                    const Positioned(
                      top: 1,
                      right: 1,
                      child: Icon(Icons.check_circle, size: 14),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// "自定义棋盘颜色" 区：预设色板 + 跟随主题 + 自定义拾色对话框。
///
/// 优先级语义（本区核心）：点任一预设 / 自定义色 → BoardPalette 覆盖
/// 主题两主格色（boardPalette?.X ?? context.chessColors.X）；
/// 点"跟随主题" → 清除自定义（回调 null），棋盘完全走主题。
class _ColorSection extends StatelessWidget {
  /// 当前自定义配色（null = 跟随主题）。
  final BoardPalette? palette;

  /// 点选结果回调：null = 清除自定义；非 null = 应用该配色。
  final ValueChanged<BoardPalette?> onSelect;

  const _ColorSection({required this.palette, required this.onSelect});

  /// 预设棋盘配色（名称, 浅色格, 深色格）。
  static const List<(String, Color, Color)> kPresets = [
    ('经典木色', Color(0xFFF0D9B5), Color(0xFFB58863)),
    ('绿色棋盘', Color(0xFFAAD751), Color(0xFF5D9B44)),
    ('灰蓝棋盘', Color(0xFF8CA2AD), Color(0xFF7B9467)),
  ];

  bool _isSelectedPreset(Color light, Color dark) =>
      palette?.lightSquare == light && palette?.darkSquare == dark;

  /// 当前是否选中了某个预设（用于"自定义色…"按钮的高亮判定）。
  bool get _isPresetSelected =>
      kPresets.any((p) => _isSelectedPreset(p.$2, p.$3));

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.format_color_fill_outlined,
                size: 16,
                color: colors.coordinateLabel,
              ),
              const SizedBox(width: 6),
              Text(
                '自定义棋盘颜色',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: colors.coordinateLabel,
                  ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 预设色板（点选即应用 + 实时预览）
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              for (final (name, light, dark) in kPresets)
                _PresetTile(
                  name: name,
                  light: light,
                  dark: dark,
                  selected: _isSelectedPreset(light, dark),
                  onTap: () => onSelect(
                    BoardPalette(lightSquare: light, darkSquare: dark),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          // 跟随主题（清除自定义）+ 自定义色（打开拾色对话框）
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _ActionTile(
                icon: Icons.auto_awesome,
                label: '跟随主题',
                selected: palette == null,
                onTap: () => onSelect(null),
              ),
              _ActionTile(
                icon: Icons.colorize,
                label: '自定义色…',
                selected: palette != null && !_isPresetSelected,
                onTap: () => _openCustomPicker(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 打开自定义拾色对话框（浅格 / 深格两组色板网格），确定后回调所选配色。
  Future<void> _openCustomPicker(BuildContext context) async {
    final picked = await showDialog<BoardPalette>(
      context: context,
      builder: (ctx) => _CustomColorDialog(
        initialLight: palette?.lightSquare,
        initialDark: palette?.darkSquare,
      ),
    );
    if (picked != null) onSelect(picked);
  }
}

/// 单个预设色板块：2x2 双色对照小方块 + 名称；点击应用。
class _PresetTile extends StatelessWidget {
  final String name;
  final Color light;
  final Color dark;
  final bool selected;
  final VoidCallback onTap;

  const _PresetTile({
    required this.name,
    required this.light,
    required this.dark,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.lightSquare.withValues(alpha: 0.35) : null,
          border: Border.all(
            color: selected ? colors.checkWarning : colors.gridLine,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 2x2 迷你棋盘小方块（浅深对照，直观预览配色）
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                width: 22,
                height: 22,
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: ColoredBox(color: light)),
                          Expanded(child: ColoredBox(color: dark)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: ColoredBox(color: dark)),
                          Expanded(child: ColoredBox(color: light)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.coordinateLabel,
                  ),
            ),
            if (selected) ...[
              const SizedBox(width: 4),
              Icon(Icons.check, size: 14, color: colors.checkWarning),
            ],
          ],
        ),
      ),
    );
  }
}

/// 动作小块（跟随主题 / 自定义色…）：图标 + 文案，选中态高亮。
class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.lightSquare.withValues(alpha: 0.35) : null,
          border: Border.all(
            color: selected ? colors.checkWarning : colors.gridLine,
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: colors.coordinateLabel),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.coordinateLabel,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 自定义拾色对话框：浅色格 / 深色格两组色板网格 + 确定 / 取消。
///
/// 不引入 flutter_colorpicker 依赖 —— 用精选棋盘色板网格（浅色系 / 深色系
/// 各 12 色，涵盖经典木色 / 绿 / 灰蓝 / 粉 / 紫 / 深黑等常见棋盘配色）。
class _CustomColorDialog extends StatefulWidget {
  final Color? initialLight;
  final Color? initialDark;

  const _CustomColorDialog({this.initialLight, this.initialDark});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late Color _light;
  late Color _dark;

  /// 精选棋盘色板：前 12 浅色系 + 后 12 深色系（顺序配对可作默认组合）。
  static const List<Color> kSwatches = [
    // 浅色系（浅色格候选）
    Color(0xFFFFF8E7), Color(0xFFF0D9B5), Color(0xFFEBE5D6), Color(0xFFDEE3E6),
    Color(0xFFEEF2E2), Color(0xFFF5E0DF), Color(0xFFE8DEF8), Color(0xFFFFF3D6),
    Color(0xFFE7E7E7), Color(0xFFFAFAF8), Color(0xFFF2D8D8), Color(0xFFEFEADD),
    // 深色系（深色格候选）
    Color(0xFF6B5D4F), Color(0xFFB58863), Color(0xFFA07E5A), Color(0xFF8CA2AD),
    Color(0xFF7B9467), Color(0xFFC79A9B), Color(0xFF9A8BC7), Color(0xFFD9B36C),
    Color(0xFF4D4D4D), Color(0xFF3D3127), Color(0xFF5D9B44), Color(0xFF2B2B2B),
  ];

  @override
  void initState() {
    super.initState();
    _light = widget.initialLight ?? kSwatches[1];
    _dark = widget.initialDark ?? kSwatches[13];
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('自定义棋盘颜色'),
      content: SizedBox(
        width: 340,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _swatchGroup(context, '浅色格', _light,
                  (c) => setState(() => _light = c)),
              const SizedBox(height: 14),
              _swatchGroup(context, '深色格', _dark,
                  (c) => setState(() => _dark = c)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            BoardPalette(lightSquare: _light, darkSquare: _dark),
          ),
          child: const Text('确定'),
        ),
      ],
    );
  }

  /// 一组色板：标签 + 当前色小方块 + Wrap 圆形色板（点击选中，选中加粗边框）。
  Widget _swatchGroup(
    BuildContext context,
    String label,
    Color current,
    ValueChanged<Color> onPick,
  ) {
    final colors = context.chessColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: colors.coordinateLabel),
            ),
            const SizedBox(width: 8),
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: current,
                border: Border.all(color: colors.gridLine),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in kSwatches)
              InkWell(
                onTap: () => onPick(c),
                borderRadius: BorderRadius.circular(13),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: current == c
                        ? Border.all(color: colors.checkWarning, width: 2.5)
                        : Border.all(
                            color: colors.gridLine.withValues(alpha: 0.5),
                            width: 1,
                          ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

/// 右侧实时预览：选中皮肤的 ChessBoard + 初始局面（白方视角）。
///
/// 皮肤解析优先级：
///   1. 本地皮肤（[localSkins] 命中）→ FileImage 本地文件，零网络
///   2. 下载中（[isDownloading]）→ 居中 loading（下载完成后由调用方刷新）
///   3. 下载失败（[downloadError] != null）→ "下载失败 + 重试"按钮
///   4. 回退 [ChessSkinBundle.byId]（RemoteChessSkin / unicode）
///
/// 配色：[boardPalette]（用户自定义）实时反映到预览棋盘 ——
/// null = 跟随主题；非 null = 覆盖主题两主格色。
class _SkinPreview extends StatelessWidget {
  final String skinId;
  final Map<String, LocalChessSkin> localSkins;
  final bool isDownloading;
  final String? downloadError;
  final void Function(String skinId)? onRetry;

  /// 自定义棋盘配色（null = 跟随主题），实时反映在预览棋盘上。
  final BoardPalette? boardPalette;

  const _SkinPreview({
    required this.skinId,
    this.localSkins = const {},
    this.isDownloading = false,
    this.downloadError,
    this.onRetry,
    this.boardPalette,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    // 优先本地皮肤；下载中显示 loading；失败显示重试；其余回退注册表。
    final skin = localSkins[skinId] ?? ChessSkinBundle.byId(skinId);
    final hasError = downloadError != null && !isDownloading;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 实时棋盘（真实 ChessBoard 渲染，非占位）
          Expanded(
            child: AspectRatio(
              aspectRatio: 1,
              child: isDownloading
                  // 下载中：居中 loading（背景沿用预览区表面色）
                  ? Center(
                      child: CircularProgressIndicator(
                        color: colors.checkWarning,
                      ),
                    )
                  : hasError
                  // 下载失败：提示 + 重试按钮
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.cloud_off,
                            size: 40,
                            color: colors.gridLine,
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              downloadError ?? '下载失败',
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed: () => onRetry?.call(skinId),
                            icon: const Icon(Icons.refresh, size: 16),
                            label: const Text('重试'),
                          ),
                        ],
                      ),
                    )
                  : ChessBoard(
                      state: BoardState.initial(),
                      skin: skin,
                      sideToMove: PieceColor.white,
                      // 用户自定义棋盘配色（null = 跟随主题）
                      boardPalette: boardPalette,
                      // 预览无交互：onSquareTap 留 null（ChessBoard 可选参数）。
                      onSquareTap: null,
                    ),
            ),
          ),
          const SizedBox(height: 12),
          // 选中皮肤名 + 返回提示
          Text(
            skin.displayName,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: colors.coordinateLabel),
          ),
          const SizedBox(height: 4),
          Text(
            isDownloading
                ? '皮肤下载中…（首次使用需联网下载）'
                : hasError
                ? '下载失败，可点击重试'
                : '点击返回使用此皮肤',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colors.gridLine),
          ),
        ],
      ),
    );
  }
}

/// 皮肤棋子缩略图（wK 王棋图像；无图像时回退 unicode ♔）。
class _SkinThumb extends StatelessWidget {
  final ChessSkin skin;
  final double size;

  const _SkinThumb({required this.skin, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final image = skin.pieces['wK'];
    return SizedBox(
      width: size,
      height: size,
      child: Center(
        child: image != null
            ? Image(
                image: image,
                width: size,
                height: size,
                fit: BoxFit.contain,
              )
            : Text(
                '♔',
                style: TextStyle(
                  fontSize: size * 0.75,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}
