part of '../lab_page.dart';

class _LabPanelContent extends StatefulWidget {
  final ScrollController scrollController;
  final List<MapEntry<String, DemoPage>> demos;
  final LabPanelColors panelColors;
  final bool scrollable;
  final double progress;
  final bool readyToOpen;
  final double closeProgress;
  final bool showCloseCue;
  final VoidCallback onHandleDragStart;
  final ValueChanged<double> onHandleDragUpdate;
  final ValueChanged<double> onHandleDragEnd;
  final ValueChanged<DemoPage> onDemoTap;

  const _LabPanelContent({
    required this.scrollController,
    required this.demos,
    required this.panelColors,
    required this.scrollable,
    required this.progress,
    required this.readyToOpen,
    required this.closeProgress,
    required this.showCloseCue,
    required this.onHandleDragStart,
    required this.onHandleDragUpdate,
    required this.onHandleDragEnd,
    required this.onDemoTap,
  });

  @override
  State<_LabPanelContent> createState() => _LabPanelContentState();
}

class _LabPanelContentState extends State<_LabPanelContent> {
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
  void didUpdateWidget(covariant _LabPanelContent oldWidget) {
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
    final contentOffset = (1.0 - widget.progress) * kLabPanelContentOffset;
    final contentScale =
        kLabPanelContentMinScale +
        (widget.progress * (1.0 - kLabPanelContentMinScale));
    final contentOpacity = widget.progress.clamp(0.0, 1.0);
    final pc = widget.panelColors;
    // 收藏列表只算一次：build 内多处（空态判断 + 格子渲染 + 拖拽索引）复用同一份，
    // 避免每处各扫一遍。
    final favoriteTitles = _favoriteTitles;

    return Column(
      children: [
        Expanded(
          child: RepaintBoundary(
            child: Transform.translate(
              offset: Offset(0, contentOffset),
              child: Opacity(
                opacity: contentOpacity,
                child: Transform.scale(
                  scale: contentScale.clamp(kLabPanelContentMinScale, 1.0),
                  alignment: Alignment.topCenter,
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
                              _provider.reorderFavorites(
                                reorderFn(favoriteTitles),
                              );
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
                          child: _PanelHandle(
                            panelColors: pc,
                            progress: widget.progress,
                            readyToOpen: widget.readyToOpen,
                            closeProgress: widget.closeProgress,
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
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
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

class _PanelHandle extends StatelessWidget {
  final LabPanelColors panelColors;
  final double progress;
  final bool readyToOpen;
  final double closeProgress;
  final bool showCloseCue;

  const _PanelHandle({
    required this.panelColors,
    required this.progress,
    required this.readyToOpen,
    required this.closeProgress,
    required this.showCloseCue,
  });

  @override
  Widget build(BuildContext context) {
    final pc = panelColors;
    final handleWidth =
        kLabHandleWidthBase +
        progress * kLabHandleWidthGain -
        closeProgress * kLabHandleWidthShrink;
    final handleHeight = kLabHandleHeightBase + progress * kLabHandleHeightGain;
    final strokeColor = pc.accentDeep;
    final bgColor = pc.accent.withValues(alpha: 0.12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: kLabHandleAnimDuration,
          curve: Curves.easeOut,
          width: handleWidth.clamp(kLabHandleWidthMin, kLabHandleWidthMax),
          height: handleHeight.clamp(
            kLabHandleHeightBase,
            kLabHandleHeightMax,
          ),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.88),
                pc.accentSoft.withValues(alpha: 0.68),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: pc.accentDeep.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: kLabHandleRingSize,
          height: kLabHandleRingSize,
          child: CustomPaint(
            painter: _HandleStatePainter(
              progress: readyToOpen ? 1.0 : progress.clamp(0.0, 1.0),
              closeProgress: closeProgress,
              strokeColor: strokeColor,
              bgColor: bgColor,
              readyToOpen: readyToOpen,
              showCloseCue: showCloseCue,
            ),
          ),
        ),
      ],
    );
  }
}

class _PanelSurfacePainter extends CustomPainter {
  final double progress;
  final LabPanelColors colors;

  _PanelSurfacePainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final waveDepth = (24.0 - progress * 12.0).clamp(10.0, 24.0);
    final path = Path()..moveTo(0, 0);
    path.quadraticBezierTo(
      size.width * 0.22,
      waveDepth,
      size.width * 0.5,
      waveDepth * 0.78,
    );
    path.quadraticBezierTo(size.width * 0.78, waveDepth * 0.52, size.width, 0);

    final edgePaint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.white.withValues(alpha: colors.isDark ? 0.18 : 0.95),
          colors.accentSoft.withValues(alpha: 0.38),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, waveDepth));
    canvas.drawPath(
      path,
      edgePaint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );

    final highlightPaint = Paint()
      ..shader =
          RadialGradient(
            colors: [
              Colors.white.withValues(alpha: colors.isDark ? 0.10 : 0.42),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(size.width * 0.5, size.height * 0.08),
              radius: size.width * 0.48,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.5, size.height * 0.08),
      size.width * 0.48,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _PanelSurfacePainter oldDelegate) {
    return progress != oldDelegate.progress;
  }
}

class _HandleStatePainter extends CustomPainter {
  final double progress;
  final double closeProgress;
  final Color strokeColor;
  final Color bgColor;
  final bool readyToOpen;
  final bool showCloseCue;

  _HandleStatePainter({
    required this.progress,
    required this.closeProgress,
    required this.strokeColor,
    required this.bgColor,
    required this.readyToOpen,
    required this.showCloseCue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 3;

    final basePaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(center, radius, basePaint);

    final activePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = readyToOpen ? 4 : 3;

    final sweep = readyToOpen ? 2 * math.pi : math.pi * 2 * progress;
    if (sweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2,
        sweep,
        false,
        activePaint,
      );
    }

    if (readyToOpen) {
      final dotPaint = Paint()..color = strokeColor;
      canvas.drawCircle(center, 4.5, dotPaint);
      return;
    }

    final cuePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.8;

    final direction = showCloseCue ? -1.0 : 1.0;
    final spread = 7 + closeProgress * 4;
    final path = Path()
      ..moveTo(center.dx - 7, center.dy - spread * direction * 0.2)
      ..lineTo(center.dx, center.dy + spread * direction * 0.45)
      ..lineTo(center.dx + 7, center.dy - spread * direction * 0.2);
    canvas.drawPath(path, cuePaint);
  }

  @override
  bool shouldRepaint(covariant _HandleStatePainter oldDelegate) {
    return progress != oldDelegate.progress ||
        closeProgress != oldDelegate.closeProgress ||
        strokeColor != oldDelegate.strokeColor ||
        bgColor != oldDelegate.bgColor ||
        readyToOpen != oldDelegate.readyToOpen ||
        showCloseCue != oldDelegate.showCloseCue;
  }
}
