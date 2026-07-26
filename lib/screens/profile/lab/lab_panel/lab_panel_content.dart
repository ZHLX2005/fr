// 面板内容：标题条 + 收藏快捷格子（可拖拽排序）+ 拖拽删除区 + 把手。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/entities/reorderable_animation_config.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../../../../lab/lab_container.dart';
import '../providers/lab_card_provider.dart';
import 'const_lab_panel.dart';
import 'lab_panel_colors.dart';
import 'lab_panel_handle.dart';

class LabPanelContent extends StatefulWidget {
  final ScrollController scrollController;
  final List<MapEntry<String, DemoPage>> demos;
  final LabPanelColors panelColors;
  final bool scrollable;

  /// 连续量：内容的位移/缩放/透明度与把手形态都跟它，每帧只重建包装层。
  /// readyToOpen / closeProgress 都是 progress 的纯函数（见 [panelCloseProgress]），
  /// 不再作为独立 prop 逐帧传进来。
  final ValueListenable<double> progress;

  /// 离散量：由状态机的 expanded/draggingPanel 决定，随 setState 传入。
  final bool showCloseCue;

  final VoidCallback onHandleDragStart;
  final ValueChanged<double> onHandleDragUpdate;
  final ValueChanged<double> onHandleDragEnd;
  final ValueChanged<DemoPage> onDemoTap;

  const LabPanelContent({
    super.key,
    required this.scrollController,
    required this.demos,
    required this.panelColors,
    required this.scrollable,
    required this.progress,
    required this.showCloseCue,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onDemoTap,
  });

  @override
  State<LabPanelContent> createState() => _LabPanelContentState();
}

class _LabPanelContentState extends State<LabPanelContent> {
  final LabCardProvider _provider = LabCardProvider();
  String? _draggingFavoriteTitle;
  bool _isDeleteZoneActive = false;

  @override
  void initState() {
    super.initState();
    _provider.addListener(_handleProviderChanged);
  }

  @override
  void dispose() {
    _provider.removeListener(_handleProviderChanged);
    super.dispose();
  }

  void _handleProviderChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// title → demo 索引。收藏格子的排序、渲染、拖拽全按 title 找 demo，
  /// 原实现在每个 itemBuilder 里线性扫 widget.demos（O(收藏数 × demo 数)）。
  /// demos 只在 LabPage.initState 构建一次，这里跟随 demos 变化重建即可。
  late Map<String, DemoPage> _demoByTitle = _buildDemoIndex();

  Map<String, DemoPage> _buildDemoIndex() => {
    for (final e in widget.demos) e.value.title: e.value,
  };

  @override
  void didUpdateWidget(covariant LabPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.demos, widget.demos)) {
      _demoByTitle = _buildDemoIndex();
    }
  }

  List<String> get _favoriteTitles {
    return _provider
        .getFavoritesOrder()
        .where(_demoByTitle.containsKey)
        .toList();
  }

  DemoPage? _findDemoByTitle(String title) => _demoByTitle[title];

  Future<void> _handleFavoriteDeleteAccepted(String title) async {
    if (!_provider.isFavorite(title)) return;
    setState(() {
      _isDeleteZoneActive = false;
      _draggingFavoriteTitle = null;
    });
    await _provider.setFavorite(title, false);
    HapticFeedback.mediumImpact();
  }

  @override
  Widget build(BuildContext context) {
    final pc = widget.panelColors;
    // 收藏列表只算一次：build 内多处（空态判断 + 格子渲染 + 拖拽索引）复用同一份，
    // 避免每处各扫一遍。
    final favoriteTitles = _favoriteTitles;

    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            // 列表本体作为 child 只造一次，每帧变的只有外层的位移/透明度/缩放。
            child: ValueListenableBuilder<double>(
              valueListenable: widget.progress,
              builder: (context, progress, child) {
                final contentScale =
                    kLabPanelContentMinScale +
                    (progress * (1.0 - kLabPanelContentMinScale));
                return Transform.translate(
                  offset: Offset(0, (1.0 - progress) * kLabPanelContentOffset),
                  child: Opacity(
                    opacity: progress.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: contentScale.clamp(kLabPanelContentMinScale, 1.0),
                      alignment: Alignment.topCenter,
                      child: child,
                    ),
                  ),
                );
              },
              child: IgnorePointer(
                ignoring: !widget.scrollable,
                child: ListView(
                  controller: widget.scrollController,
                  physics: const BouncingScrollPhysics(),
                  padding: kLabPanelListPadding,
                  children: [
                    _PanelTitleSection(panelColors: pc),
                    const SizedBox(height: 16),
                    if (favoriteTitles.isNotEmpty)
                      ReorderableBuilder<String>.builder(
                        longPressDelay: kLabFavoriteLongPressDelay,
                        animationConfig: const ReorderableAnimationConfig(
                          dragFeedbackDuration: Duration.zero,
                        ),
                        feedbackScaleFactor: 1.0,
                        dragChildBoxDecoration: BoxDecoration(
                          color: Colors.black.withValues(
                            alpha: kLabFavoritePressOverlayAlpha,
                          ),
                          borderRadius: BorderRadius.circular(
                            kLabFavoriteRadius,
                          ),
                          boxShadow: const <BoxShadow>[],
                        ),
                        onDragStarted: (index) {
                          setState(() {
                            _draggingFavoriteTitle = favoriteTitles[index];
                            _isDeleteZoneActive = false;
                          });
                          HapticFeedback.lightImpact();
                        },
                        onUpdatedDraggedChild: (index) {},
                        onDragEnd: (index) {
                          setState(() {
                            _draggingFavoriteTitle = null;
                            _isDeleteZoneActive = false;
                          });
                        },
                        onReorder: (reorderFn) {
                          _provider.reorderFavorites(reorderFn(favoriteTitles));
                        },
                        itemCount: favoriteTitles.length,
                        childBuilder: (itemBuilder) {
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: kLabFavoriteCrossAxisCount,
                                  mainAxisSpacing: kLabFavoriteSpacing,
                                  crossAxisSpacing: kLabFavoriteSpacing,
                                  childAspectRatio: kLabFavoriteAspectRatio,
                                ),
                            itemCount: favoriteTitles.length,
                            itemBuilder: (context, index) {
                              final title = favoriteTitles[index];
                              final demo = _findDemoByTitle(title);
                              if (demo == null) {
                                return const SizedBox.shrink();
                              }
                              return itemBuilder(
                                CustomDraggable(
                                  key: ValueKey(title),
                                  data: title,
                                  child: _FavoriteDemoShortcut(
                                    key: ValueKey(title),
                                    panelColors: pc,
                                    demo: demo,
                                    isDragActive:
                                        _draggingFavoriteTitle == title,
                                    onTap: () => widget.onDemoTap(demo),
                                  ),
                                ),
                                index,
                              );
                            },
                          );
                        },
                      )
                    else
                      _PanelEmptyFavorites(panelColors: pc),
                  ],
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              child: Center(
                child: _draggingFavoriteTitle != null
                    ? _PanelDeleteZone(
                        isActive: _isDeleteZoneActive,
                        onWillAccept: (data) {
                          final accept = data == _draggingFavoriteTitle;
                          if (_isDeleteZoneActive != accept) {
                            setState(() {
                              _isDeleteZoneActive = accept;
                            });
                          }
                          return accept;
                        },
                        onLeave: (_) {
                          if (_isDeleteZoneActive) {
                            setState(() {
                              _isDeleteZoneActive = false;
                            });
                          }
                        },
                        onAccept: _handleFavoriteDeleteAccepted,
                      )
                    : GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onVerticalDragStart: (_) => widget.onHandleDragStart(),
                        onVerticalDragUpdate: (details) {
                          widget.onHandleDragUpdate(details.delta.dy);
                        },
                        onVerticalDragEnd: (details) {
                          widget.onHandleDragEnd(
                            details.velocity.pixelsPerSecond.dy,
                          );
                        },
                        onVerticalDragCancel: () => widget.onHandleDragEnd(0.0),
                        child: SizedBox(
                          width: double.infinity,
                          child: PanelHandle(
                            panelColors: pc,
                            progress: widget.progress,
                            showCloseCue: widget.showCloseCue,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelDeleteZone extends StatelessWidget {
  final bool isActive;
  final bool Function(String?) onWillAccept;
  final ValueChanged<String?> onLeave;
  final ValueChanged<String> onAccept;

  const _PanelDeleteZone({
    required this.isActive,
    required this.onWillAccept,
    required this.onLeave,
    required this.onAccept,
  });

  @override
  Widget build(BuildContext context) {
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => onWillAccept(details.data),
      onLeave: onLeave,
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidateData, rejectedData) {
        final active = isActive || candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: kLabDeleteAnimDuration,
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: kLabDeleteMinHeight),
          decoration: BoxDecoration(
            color: active
                ? kLabDeleteActiveColor
                : kLabDeleteIdleColor.withValues(alpha: kLabDeleteIdleAlpha),
            borderRadius: BorderRadius.circular(kLabDeleteRadius),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.78 : 0.52),
              width: active ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: kLabDeleteShadowColor.withValues(
                  alpha: active ? 0.28 : 0.16,
                ),
                blurRadius: active ? 24 : 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: kLabDeletePadding,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                active ? Icons.delete_forever_rounded : Icons.delete_outline,
                color: Colors.white,
                size: active ? 28 : 24,
              ),
              const SizedBox(width: 10),
              Text(
                active ? '松手移除收藏' : '拖到这里删除',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PanelTitleSection extends StatelessWidget {
  final LabPanelColors panelColors;

  const _PanelTitleSection({required this.panelColors});

  @override
  Widget build(BuildContext context) {
    final pc = panelColors;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: pc.glassFill,
        borderRadius: BorderRadius.circular(kLabPanelGlassRadius),
        border: Border.all(color: pc.glassBorder),
        boxShadow: [
          BoxShadow(
            color: pc.accentDeep.withValues(alpha: kLabPanelGlassShadowAlpha),
            blurRadius: kLabPanelGlassShadowBlur,
            offset: kLabPanelGlassShadowOffset,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: pc.accentSoft.withValues(alpha: kLabPanelAccentSoftAlpha),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'LAB PANEL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: pc.accentDeep,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FavoriteDemoShortcut extends StatefulWidget {
  final DemoPage demo;
  final bool isDragActive;
  final VoidCallback onTap;
  final LabPanelColors panelColors;

  const _FavoriteDemoShortcut({
    super.key,
    required this.demo,
    required this.isDragActive,
    required this.onTap,
    required this.panelColors,
  });

  @override
  State<_FavoriteDemoShortcut> createState() => _FavoriteDemoShortcutState();
}

class _FavoriteDemoShortcutState extends State<_FavoriteDemoShortcut> {
  bool _isPressed = false;

  void _handleHighlightChanged(bool value) {
    if (_isPressed == value) return;
    setState(() {
      _isPressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showOverlay = _isPressed || widget.isDragActive;
    final pc = widget.panelColors;

    return Tooltip(
      message: widget.demo.title,
      triggerMode: TooltipTriggerMode.tap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _handleHighlightChanged,
          borderRadius: BorderRadius.circular(kLabFavoriteRadius),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Ink(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (showOverlay)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: kLabFavoritePressOverlayAlpha,
                      ),
                      borderRadius: BorderRadius.circular(kLabFavoriteRadius),
                    ),
                  ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        width: kLabFavoriteIconBoxSize,
                        height: kLabFavoriteIconBoxSize,
                        decoration: BoxDecoration(
                          color: pc.accentSoft.withValues(
                            alpha: kLabPanelAccentSoftAlpha,
                          ),
                          borderRadius: BorderRadius.circular(
                            kLabFavoriteIconBoxRadius,
                          ),
                        ),
                        child: Icon(
                          Icons.star_rounded,
                          color: pc.accentDeep,
                          size: kLabFavoriteIconSize,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 1),
                        child: Text(
                          widget.demo.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: pc.text,
                                fontWeight: FontWeight.w700,
                                height: 1.0,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PanelEmptyFavorites extends StatelessWidget {
  final LabPanelColors panelColors;

  const _PanelEmptyFavorites({required this.panelColors});

  @override
  Widget build(BuildContext context) {
    final pc = panelColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: pc.glassFill,
        borderRadius: BorderRadius.circular(kLabPanelGlassRadius),
        border: Border.all(color: pc.glassBorder),
      ),
      child: Column(
        children: [
          Container(
            width: kLabEmptyIconBoxSize,
            height: kLabEmptyIconBoxSize,
            decoration: BoxDecoration(
              color: pc.accentSoft.withValues(alpha: kLabPanelAccentSoftAlpha),
              borderRadius: BorderRadius.circular(kLabEmptyIconBoxRadius),
            ),
            child: Icon(
              Icons.star_border_rounded,
              color: pc.accentDeep,
              size: kLabEmptyIconSize,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有收藏的 demo',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: pc.text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '长按 demo 卡片，选择「收藏」即可加入',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: pc.mutedText),
          ),
        ],
      ),
    );
  }
}
