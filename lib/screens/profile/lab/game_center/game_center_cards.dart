// 游戏中心 — 卡片 / 徽章 / 过滤 chip 组件
//
// 三种卡：
//   [GameFeaturedCard] 顶部横滑精选大卡（联机优先）
//   [GameGridCard]     自适应列数网格卡（主列表）
//   [GameCategoryChip] 分类过滤 chip（border-emphasis 风格，不用纯色填充）
//
// 收藏与自定义封面都读同一个 LabCardProvider（与 Lab 页共享一份数据），
// 卡片各自订阅、按需重建，避免整页 setState。

import 'package:flutter/material.dart';

import '../../../../core/game_kit/skin/game_center_skin_spec.dart';
import '../../../../lab/lab_container.dart';
import '../providers/lab_card_provider.dart';
import 'const_game_center.dart';
import 'game_center_artwork.dart';

// ══════════════════════════════════════════════════════════════
// 精选大卡
// ══════════════════════════════════════════════════════════════

class GameFeaturedCard extends StatefulWidget {
  const GameFeaturedCard({super.key, required this.demo, required this.onTap});

  final DemoPage demo;
  final VoidCallback onTap;

  @override
  State<GameFeaturedCard> createState() => _GameFeaturedCardState();
}

class _GameFeaturedCardState extends State<GameFeaturedCard> {
  final _provider = LabCardProvider();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = gameMetaOf(widget.demo.slug);
    final remoteCover = gameCenterCoverOf(
      widget.demo.slug,
      kGameCenterSkinLarge,
    );
    final bgPath = _provider.getBackground(widget.demo.title);
    final hasPhoto = remoteCover != null ||
        (bgPath != null && bgPath.isNotEmpty);
    final scheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.975 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kGcCardRadius + 4),
            boxShadow: [
              BoxShadow(
                // 有封面时用中性阴影，避免程序化配色光晕透出
                color: hasPhoto
                    ? scheme.onSurface.withValues(alpha: 0.22)
                    : meta.gradient.last.withValues(alpha: 0.28),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kGcCardRadius + 4),
            child: Stack(
              fit: StackFit.expand,
              children: [
                GameArtwork(
                  meta: meta,
                  backgroundPath: bgPath,
                  remoteCover: remoteCover,
                  iconSize: 72,
                ),
                // 底部信息条：再压一层深色渐变，保证长描述也可读
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
                          Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62),
                        ],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 24, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.demo.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                              color: Theme.of(context).colorScheme.surface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.demo.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              _GlassPill(
                                icon: meta.isOnline
                                    ? Icons.wifi_tethering_rounded
                                    : Icons.person_rounded,
                                label: meta.mode,
                              ),
                              const Spacer(),
                              _GlassPill(
                                icon: Icons.play_arrow_rounded,
                                label: '开始',
                                filled: true,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 10,
                  left: 12,
                  child: _GlassPill(
                    icon: kGameCategoryIcons[GameCategory.multiplayer]!,
                    label: '精选',
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: GameFavoriteStar(title: widget.demo.title),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 网格卡
// ══════════════════════════════════════════════════════════════

class GameGridCard extends StatefulWidget {
  const GameGridCard({super.key, required this.demo, required this.onTap});

  final DemoPage demo;
  final VoidCallback onTap;

  @override
  State<GameGridCard> createState() => _GameGridCardState();
}

class _GameGridCardState extends State<GameGridCard> {
  final _provider = LabCardProvider();
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = gameMetaOf(widget.demo.slug);
    final scheme = theme.colorScheme;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(kGcCardRadius),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    GameArtwork(
                      meta: meta,
                      backgroundPath: _provider.getBackground(
                        widget.demo.title,
                      ),
                      remoteCover: gameCenterCoverOf(
                        widget.demo.slug,
                        kGameCenterSkinSmall,
                      ),
                    ),
                    if (meta.isOnline)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: _GlassPill(
                          icon: Icons.wifi_tethering_rounded,
                          label: '联机',
                          dense: true,
                        ),
                      ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GameFavoriteStar(
                        title: widget.demo.title,
                        dense: true,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.demo.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitleOf(meta),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// "联机双人 · 棋游" —— 玩法 + 分类，一行说清这是什么游戏
  String _subtitleOf(GameMeta meta) {
    final tags = meta.categories
        .where((c) => c != GameCategory.multiplayer)
        .map((c) => kGameCategoryLabels[c])
        .whereType<String>()
        .toList();
    if (tags.isEmpty) return meta.mode;
    return '${meta.mode} · ${tags.join('/')}';
  }
}

// ══════════════════════════════════════════════════════════════
// 收藏星标
// ══════════════════════════════════════════════════════════════

class GameFavoriteStar extends StatefulWidget {
  const GameFavoriteStar({super.key, required this.title, this.dense = false});

  /// LabCardProvider 以 demo.title 作为收藏 key（与 Lab 页一致）
  final String title;
  final bool dense;

  @override
  State<GameFavoriteStar> createState() => _GameFavoriteStarState();
}

class _GameFavoriteStarState extends State<GameFavoriteStar> {
  final _provider = LabCardProvider();

  @override
  void initState() {
    super.initState();
    _provider.addListener(_onProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_onProviderChanged);
    super.dispose();
  }

  void _onProviderChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final next = !_provider.isFavorite(widget.title);
    await _provider.setFavorite(widget.title, next);
  }

  @override
  Widget build(BuildContext context) {
    final isFav = _provider.isFavorite(widget.title);
    final size = widget.dense ? 18.0 : 22.0;

    return IconButton(
      tooltip: isFav ? '取消收藏' : '收藏',
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.all(widget.dense ? 6 : 10),
      constraints: const BoxConstraints(),
      onPressed: _toggle,
      icon: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        transitionBuilder: (child, anim) =>
            ScaleTransition(scale: anim, child: child),
        child: Icon(
          isFav ? Icons.star_rounded : Icons.star_border_rounded,
          key: ValueKey(isFav),
          size: size,
          color: isFav ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.surface,
          shadows: const [Shadow(color: Color(0x66000000), blurRadius: 6)],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 分类过滤 chip
// ══════════════════════════════════════════════════════════════

/// border-emphasis 风格：选中 = 浅 tint 底 + 同色描边 + 同色前景，
/// 不用饱和纯色填充（见 styles-skill / border-emphasis）。
class GameCategoryChip extends StatelessWidget {
  const GameCategoryChip({
    super.key,
    required this.label,
    required this.icon,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final fg = selected ? accent : scheme.onSurfaceVariant;

    return Material(
      color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.0),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.10)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.45)
                  : scheme.outlineVariant.withValues(alpha: 0.6),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                '$count',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: fg.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 封面上的玻璃小胶囊
// ══════════════════════════════════════════════════════════════

class _GlassPill extends StatelessWidget {
  const _GlassPill({
    required this.icon,
    required this.label,
    this.dense = false,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final bool dense;

  /// true = 白底深字（用于"开始"这类主操作），false = 半透明黑底白字
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final fg = filled ? Theme.of(context).colorScheme.onSurface : Theme.of(context).colorScheme.surface;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: filled
            ? Theme.of(context).colorScheme.surface.withValues(alpha: 0.92)
            : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: dense ? 12 : 14, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style:
                (dense
                        ? Theme.of(context).textTheme.labelSmall
                        : Theme.of(context).textTheme.labelMedium)
                    ?.copyWith(color: fg, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
