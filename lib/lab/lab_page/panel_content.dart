part of '../../screens/lab/lab_page.dart';

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
          child: IgnorePointer(
            ignoring: !widget.scrollable,
            child: Transform.translate(
              offset: Offset(0, contentOffset),
              child: Opacity(
                opacity: contentOpacity,
                child: Transform.scale(
                  scale: contentScale.clamp(0.5, 1.0),
                  alignment: Alignment.topCenter,
                  child: ListView(
                    controller: widget.scrollController,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 24, 18, 20),
                    children: [
                      if (favoriteDemos.isNotEmpty)
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            for (final demo in favoriteDemos)
                              _FavoriteDemoShortcut(
                                demo: demo,
                                onTap: () => widget.onDemoTap(demo),
                              ),
                          ],
                        )
                      else
                        const _PanelEmptyFavorites(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 12),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => widget.onHandleDragStart(),
            onVerticalDragUpdate: (details) {
              widget.onHandleDragUpdate(details.delta.dy);
            },
            onVerticalDragEnd: (details) {
              widget.onHandleDragEnd(details.velocity.pixelsPerSecond.dy);
            },
            onVerticalDragCancel: () => widget.onHandleDragEnd(0.0),
            child: SizedBox(
              width: double.infinity,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Center(
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

class _FavoriteDemoShortcut extends StatelessWidget {
  final DemoPage demo;
  final VoidCallback onTap;

  const _FavoriteDemoShortcut({required this.demo, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: demo.title,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            width: 88,
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.62),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: _kAccentSoftColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    color: _kAccentDeepColor,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  demo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: _kPanelTextColor,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
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
