// lib/core/chess/skins/chess_skin_settings_page.dart
//
// 全屏换肤设置页 — 左侧皮肤列表 + 右侧实时棋盘预览。
//
// 布局（桌面/平板可两栏；手机窄屏自动降级为竖排单栏）：
//   AppBar(title: '棋盘皮肤', leading: BackButton)
//   body（宽屏 ≥600）: Row(
//     left:  皮肤列表（可滚动，每项 = wK 缩略图 + 名称 + 选中勾）
//     right: 实时预览（选中皮肤的 ChessBoard + 初始局面）
//   )
//   body（窄屏 <600）: Column(
//     top:    横向皮肤缩略图条（横向滚动）
//     bottom: 实时棋盘预览 + 选中皮肤名提示
//   )
//
// 返回语义：
//   · 返回箭头（AppBar leading）→ pop(_selectedId)：应用当前选中的皮肤
//   · 系统返回手势 / 首页 back 键 → 同上（经 PopScope 拦截转成携带 _selectedId）
//   · 调用方据此持久化 ChessSkinPrefs.write + 应用到对弈棋盘。
//
// 颜色全部走 context.chessColors（v6.2.1 主题通道）；棋子图像用
// ChessSkinBundle.byId(id) 解析（含 default → unicode 回退）。

import 'package:flutter/material.dart';

import '../../../widgets/context_chess_colors.dart';
import '../models/board_state.dart';
import '../models/piece.dart';
import '../widgets/chess_board.dart';
import 'chess_skin.dart';
import 'chess_skin_meta.dart';
import 'local_chess_skin.dart';

/// 全屏换肤设置页 — 左侧皮肤列表 + 右侧实时棋盘预览。
class ChessSkinSettingsPage extends StatefulWidget {
  const ChessSkinSettingsPage({
    super.key,
    required this.initialSkinId,
    this.localSkins = const {},
    this.onRequestDownload,
    this.isDownloading,
    this.downloadError,
    this.onRetryDownload,
  });

  /// 进入页面时选中的皮肤 id（由调用方传入，通常是已持久化的值）。
  final String initialSkinId;

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

  @override
  void initState() {
    super.initState();
    _selectedId = widget.initialSkinId;
  }

  /// 返回箭头：把当前选中的皮肤 id 带回调用方（应用 + 持久化由调用方完成）。
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
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            final wide =
                constraints.maxWidth >= ChessSkinSettingsPage.kWideBreakpoint;
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 左侧：皮肤列表（固定宽度，可滚动）
                  SizedBox(
                    width: 280,
                    child: _SkinList(
                      selectedId: _selectedId,
                      onSelect: _selectSkin,
                      localSkins: widget.localSkins,
                    ),
                  ),
                  // 右侧：实时棋盘预览
                  Expanded(
                    child: _SkinPreview(
                      skinId: _selectedId,
                      localSkins: widget.localSkins,
                      isDownloading:
                          widget.isDownloading?.call(_selectedId) ?? false,
                      downloadError: widget.downloadError?.call(_selectedId),
                      onRetry: widget.onRetryDownload,
                    ),
                  ),
                ],
              );
            }
            // 窄屏：竖排 — 顶部横向皮肤条 + 底部预览。
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _SkinStrip(
                  selectedId: _selectedId,
                  onSelect: _selectSkin,
                  localSkins: widget.localSkins,
                ),
                Expanded(
                  child: _SkinPreview(
                    skinId: _selectedId,
                    localSkins: widget.localSkins,
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

/// 左侧皮肤列表（宽屏用）：每项 = wK 缩略图 + 显示名 + 选中勾。
class _SkinList extends StatelessWidget {
  final String selectedId;
  final ValueChanged<String> onSelect;
  final Map<String, LocalChessSkin> localSkins;

  const _SkinList({
    required this.selectedId,
    required this.onSelect,
    this.localSkins = const {},
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.chessColors;
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: kChessSkinsCatalog.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.gridLine.withValues(alpha: 0.3)),
      itemBuilder: (context, i) {
        final meta = kChessSkinsCatalog[i];
        final isSelected = meta.id == selectedId;
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
          onTap: () => onSelect(meta.id),
        );
      },
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
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: kChessSkinsCatalog.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final meta = kChessSkinsCatalog[i];
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

/// 右侧实时预览：选中皮肤的 ChessBoard + 初始局面（白方视角）。
///
/// 皮肤解析优先级：
///   1. 本地皮肤（[localSkins] 命中）→ FileImage 本地文件，零网络
///   2. 下载中（[isDownloading]）→ 居中 loading（下载完成后由调用方刷新）
///   3. 下载失败（[downloadError] != null）→ "下载失败 + 重试"按钮
///   4. 回退 [ChessSkinBundle.byId]（RemoteChessSkin / unicode）
class _SkinPreview extends StatelessWidget {
  final String skinId;
  final Map<String, LocalChessSkin> localSkins;
  final bool isDownloading;
  final String? downloadError;
  final void Function(String skinId)? onRetry;

  const _SkinPreview({
    required this.skinId,
    this.localSkins = const {},
    this.isDownloading = false,
    this.downloadError,
    this.onRetry,
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
