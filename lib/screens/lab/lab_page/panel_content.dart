part of '../lab_page.dart';

class _LabPanelContent extends StatefulWidget {
  final ScrollController scrollController;
  final List<MapEntry<String, DemoPage>> demos;
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
  late final rive.FileLoader _douziFileLoader = rive.FileLoader.fromAsset(
    'assets/rive/douzi.riv',
    riveFactory: rive.Factory.rive,
  );
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
    _douziFileLoader.dispose();
    super.dispose();
  }

  void _handleProviderChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  List<String> get _favoriteTitles {
    final order = _provider.getFavoritesOrder();
    return order.where((title) {
      return widget.demos.any((e) => e.value.title == title);
    }).toList();
  }

  DemoPage? _findDemoByTitle(String title) {
    final entry = widget.demos.cast<MapEntry<String, DemoPage>?>().firstWhere(
      (e) => e?.value.title == title,
      orElse: () => null,
    );
    return entry?.value;
  }

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
    final contentOffset = (1.0 - widget.progress) * 16.0;
    final contentScale = 0.5 + (widget.progress * 0.5);
    final contentOpacity = widget.progress.clamp(0.0, 1.0);
    final favoriteDemos = widget.demos
        .where((entry) => _provider.isFavorite(entry.value.title))
        .map((entry) => entry.value)
        .toList();

    return Column(
      children: [
        Expanded(
          child: Transform.translate(
            offset: Offset(0, contentOffset),
            child: Opacity(
              opacity: contentOpacity,
              child: Transform.scale(
                scale: contentScale.clamp(0.5, 1.0),
                alignment: Alignment.topCenter,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return Column(
                      children: [
                        Expanded(
                          flex: 7,
                          child: IgnorePointer(
                            ignoring: !widget.scrollable,
                            child: ListView(
                              controller: widget.scrollController,
                              physics: const BouncingScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                24,
                                18,
                                16,
                              ),
                              children: [
                                const _PanelTitleSection(),
                                const SizedBox(height: 16),
                                if (favoriteDemos.isNotEmpty)
                                  Builder(
                                    builder: (context) {
                                      return ReorderableBuilder<String>.builder(
                                        longPressDelay: const Duration(
                                          milliseconds: 300,
                                        ),
                                        animationConfig:
                                            const ReorderableAnimationConfig(
                                          dragFeedbackDuration: Duration.zero,
                                        ),
                                        feedbackScaleFactor: 1.0,
                                        dragChildBoxDecoration: BoxDecoration(
                                          color: Colors.black.withValues(
                                            alpha: 0.06,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          boxShadow: const <BoxShadow>[],
                                        ),
                                        onDragStarted: (index) {
                                          setState(() {
                                            _draggingFavoriteTitle =
                                                _favoriteTitles[index];
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
                                          final reorderedTitles = reorderFn(
                                            _favoriteTitles,
                                          );
                                          _provider.reorderFavorites(
                                            reorderedTitles,
                                          );
                                        },
                                        itemCount: _favoriteTitles.length,
                                        childBuilder: (itemBuilder) {
                                          return GridView.builder(
                                            shrinkWrap: true,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            gridDelegate:
                                                const SliverGridDelegateWithFixedCrossAxisCount(
                                              crossAxisCount: 4,
                                              mainAxisSpacing: 8,
                                              crossAxisSpacing: 8,
                                              childAspectRatio: 0.92,
                                            ),
                                            itemCount: _favoriteTitles.length,
                                            itemBuilder: (context, index) {
                                              final title =
                                                  _favoriteTitles[index];
                                              final demo =
                                                  _findDemoByTitle(title);
                                              if (demo == null) {
                                                return const SizedBox.shrink();
                                              }
                                              return itemBuilder(
                                                CustomDraggable(
                                                  key: ValueKey(title),
                                                  data: title,
                                                  child: _FavoriteDemoShortcut(
                                                    key: ValueKey(title),
                                                    demo: demo,
                                                    isDragActive:
                                                        _draggingFavoriteTitle ==
                                                        title,
                                                    onTap: () =>
                                                        widget.onDemoTap(demo),
                                                  ),
                                                ),
                                                index,
                                              );
                                            },
                                          );
                                        },
                                      );
                                    },
                                  )
                                else
                                  const _PanelEmptyFavorites(),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 3,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                            child: _PanelRiveSection(
                              fileLoader: _douziFileLoader,
                              maxHeight: constraints.maxHeight * 0.3,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
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
                        child: _PanelHandle(
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
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: double.infinity,
          constraints: const BoxConstraints(minHeight: 76),
          decoration: BoxDecoration(
            color: active
                ? const Color(0xFFD63B3B)
                : const Color(0xFFEF6B6B).withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: active ? 0.78 : 0.52),
              width: active ? 1.6 : 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFB3261E).withValues(
                  alpha: active ? 0.28 : 0.16,
                ),
                blurRadius: active ? 24 : 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
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
                active ? 'Release to remove favorite' : 'Drag here to delete',
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

class _PanelRiveSection extends StatelessWidget {
  final rive.FileLoader fileLoader;
  final double maxHeight;

  const _PanelRiveSection({
    required this.fileLoader,
    required this.maxHeight,
  });

  @override
  Widget build(BuildContext context) {
    final visualSize = math.min(maxHeight * 0.78, 160.0).clamp(88.0, 160.0);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: visualSize,
            height: visualSize,
            child: rive.RiveWidgetBuilder(
              fileLoader: fileLoader,
              dataBind: rive.DataBind.auto(),
              builder: (context, state) => switch (state) {
                rive.RiveLoading() => const SizedBox.shrink(),
                rive.RiveFailed() => const SizedBox.shrink(),
                rive.RiveLoaded(:final controller) => rive.RiveWidget(
                  controller: controller,
                  fit: rive.Fit.contain,
                  hitTestBehavior: rive.RiveHitTestBehavior.opaque,
                ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelTitleSection extends StatelessWidget {
  const _PanelTitleSection();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.42)),
        boxShadow: [
          BoxShadow(
            color: _kAccentDeepColor.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _kAccentSoftColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              'LAB PANEL',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _kAccentDeepColor,
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

  const _FavoriteDemoShortcut({
    super.key,
    required this.demo,
    required this.isDragActive,
    required this.onTap,
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

    return Tooltip(
      message: widget.demo.title,
      triggerMode: TooltipTriggerMode.tap,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: _handleHighlightChanged,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: Ink(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Opacity(
                  opacity: showOverlay ? 1.0 : 0.0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 8, 6, 8),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.max,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _kAccentSoftColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.star_rounded,
                          color: _kAccentDeepColor,
                          size: 18,
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
                            color: _kPanelTextColor,
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
  const _PanelEmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
      ),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: _kAccentSoftColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              Icons.star_border_rounded,
              color: _kAccentDeepColor,
              size: 26,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'No favorite demos yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _kPanelTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Long press a demo card and tap Favorite Demo.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _kPanelMutedTextColor),
          ),
        ],
      ),
    );
  }
}

class _PanelHandle extends StatelessWidget {
  final double progress;
  final bool readyToOpen;
  final double closeProgress;
  final bool showCloseCue;

  const _PanelHandle({
    required this.progress,
    required this.readyToOpen,
    required this.closeProgress,
    required this.showCloseCue,
  });

  @override
  Widget build(BuildContext context) {
    final handleWidth = 40 + progress * 18 - closeProgress * 8;
    final handleHeight = 4 + progress * 2;
    final strokeColor = _kAccentDeepColor;
    final bgColor = _kAccentColor.withValues(alpha: 0.12);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          width: handleWidth.clamp(30.0, 58.0),
          height: handleHeight.clamp(4.0, 6.0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white.withValues(alpha: 0.88),
                _kAccentSoftColor.withValues(alpha: 0.68),
              ],
            ),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: _kAccentDeepColor.withValues(alpha: 0.10),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: 42,
          height: 42,
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

  _PanelSurfacePainter({required this.progress});

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
          Colors.white.withValues(alpha: 0.95),
          _kAccentSoftColor.withValues(alpha: 0.38),
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
              Colors.white.withValues(alpha: 0.42),
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
