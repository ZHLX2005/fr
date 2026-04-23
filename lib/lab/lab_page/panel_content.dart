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
    final topTitles = widget.demos
        .take(5)
        .map((entry) => entry.value.title)
        .toList();
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
                      _LabPanelHeroCard(
                        demoCount: widget.demos.length,
                        topLabel: topTitles.isNotEmpty
                            ? topTitles.first
                            : 'No demos',
                      ),
                      const SizedBox(height: 18),
                      const _PanelSectionHeader(
                        eyebrow: 'REGISTRY',
                        title: 'Quick read of the lab space',
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _ActionChip(
                            icon: Icons.widgets_outlined,
                            label: '${widget.demos.length} demos',
                          ),
                          const _ActionChip(
                            icon: Icons.vertical_align_top,
                            label: 'Top overscroll opens',
                          ),
                          const _ActionChip(
                            icon: Icons.pan_tool_alt_outlined,
                            label: 'Handle drag closes',
                          ),
                        ],
                      ),
                      if (favoriteDemos.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const _PanelSectionHeader(
                          eyebrow: 'FAVORITES',
                          title: 'Quick launch your saved demos',
                        ),
                        const SizedBox(height: 12),
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
                        ),
                      ],
                      const SizedBox(height: 18),
                      const _PanelSectionHeader(
                        eyebrow: 'RECENT',
                        title: 'Registered demo entries',
                      ),
                      const SizedBox(height: 12),
                      for (final demo in topTitles)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _StoryCard(
                            icon: Icons.chevron_right,
                            title: demo,
                            body:
                                'Registry entry available from the Lab grid and this pull panel.',
                          ),
                        ),
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          width: 96,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
                  size: 22,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                demo.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _kPanelTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabPanelHeroCard extends StatelessWidget {
  final int demoCount;
  final String topLabel;

  const _LabPanelHeroCard({required this.demoCount, required this.topLabel});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lab Overview',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: _kPanelTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'The panel opens with the same threshold, damping and close handle feel as the pull panel demo.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _kPanelMutedTextColor),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _MetricPill(label: 'Demos', value: '$demoCount'),
              const SizedBox(width: 10),
              Expanded(
                child: _MetricPill(label: 'First', value: topLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _kCardBaseColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPanelBorderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: _kPanelMutedTextColor),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: _kPanelTextColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelSectionHeader extends StatelessWidget {
  final String eyebrow;
  final String title;

  const _PanelSectionHeader({required this.eyebrow, required this.title});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: _kPanelMutedTextColor,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: _kPanelTextColor,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ActionChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: _kAccentDeepColor),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              color: _kPanelTextColor,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _StoryCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.56),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: 0.44)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _kAccentSoftColor.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: _kAccentDeepColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: _kPanelTextColor,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  style: const TextStyle(
                    color: _kPanelMutedTextColor,
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
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
    final topGlowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.72),
          Colors.white.withValues(alpha: 0.10),
          Colors.transparent,
        ],
        stops: const [0.0, 0.28, 1.0],
      ).createShader(Offset.zero & size);

    final glowHeight = math.min(size.height, 180.0);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, glowHeight), topGlowPaint);

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
              center: Offset(size.width * 0.5, glowHeight * 0.14),
              radius: size.width * 0.48,
            ),
          );
    canvas.drawCircle(
      Offset(size.width * 0.5, glowHeight * 0.14),
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
