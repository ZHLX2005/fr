import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PageTurnDirection { next, previous }

enum PageCurlPhase { idle, dragging, settling }

enum _GestureStartMode { corner, edge }

class PageTurnRequest {
  const PageTurnRequest({required this.direction, required this.completed});

  final PageTurnDirection direction;
  final bool completed;
}

class PageCurlView extends StatefulWidget {
  const PageCurlView({
    super.key,
    required this.currentPage,
    required this.targetPage,
    required this.canTurnNext,
    required this.canTurnPrevious,
    required this.onTurnFinished,
  });

  final Widget currentPage;
  final Widget? targetPage;
  final bool canTurnNext;
  final bool canTurnPrevious;
  final ValueChanged<PageTurnRequest> onTurnFinished;

  @override
  State<PageCurlView> createState() => _PageCurlViewState();
}

class _PageCurlViewState extends State<PageCurlView>
    with SingleTickerProviderStateMixin {
  static const double _cornerHotZone = 92;
  static const Duration _settleDuration = Duration(milliseconds: 220);

  late final AnimationController _settleController =
      AnimationController(vsync: this, duration: _settleDuration)
        ..addListener(_onAnimationTick)
        ..addStatusListener(_onAnimationStatusChanged);

  Animation<double>? _progressAnimation;
  PageCurlPhase _phase = PageCurlPhase.idle;
  PageTurnDirection? _direction;
  bool _completeOnRelease = false;
  double _progress = 0;
  Size _viewport = Size.zero;
  Offset? _dragPosition;
  _GestureStartMode? _gestureStartMode;

  @override
  void dispose() {
    _settleController.dispose();
    super.dispose();
  }

  bool _isInHotZone(
    Offset localPosition,
    Size size,
    PageTurnDirection direction,
  ) {
    final isBottom = localPosition.dy >= size.height - _cornerHotZone;
    if (!isBottom) return false;
    if (direction == PageTurnDirection.next) {
      return localPosition.dx >= size.width - _cornerHotZone;
    }
    return localPosition.dx <= _cornerHotZone;
  }

  bool _isInEdgeZone(
    Offset localPosition,
    Size size,
    PageTurnDirection direction,
  ) {
    final edgeWidth = math.max(72.0, size.width * 0.22);
    if (direction == PageTurnDirection.next) {
      return localPosition.dx >= size.width - edgeWidth;
    }
    return localPosition.dx <= edgeWidth;
  }

  Offset _normalizeStartPosition(
    Offset localPosition,
    _GestureStartMode mode,
    Size size,
  ) {
    final targetY = mode == _GestureStartMode.corner
        ? localPosition.dy
        : size.height * 0.84;
    return Offset(
      localPosition.dx.clamp(0.0, size.width).toDouble(),
      targetY.clamp(24.0, size.height - 12).toDouble(),
    );
  }

  void _handlePanStart(DragStartDetails details) {
    if (_phase == PageCurlPhase.settling || _viewport == Size.zero) return;

    final local = details.localPosition;
    final wantNext = _isInHotZone(local, _viewport, PageTurnDirection.next);
    final wantPrevious = _isInHotZone(
      local,
      _viewport,
      PageTurnDirection.previous,
    );
    final edgeNext = _isInEdgeZone(local, _viewport, PageTurnDirection.next);
    final edgePrevious = _isInEdgeZone(
      local,
      _viewport,
      PageTurnDirection.previous,
    );
    _GestureStartMode? startMode;

    if (wantNext && widget.canTurnNext) {
      _direction = PageTurnDirection.next;
      startMode = _GestureStartMode.corner;
    } else if (wantPrevious && widget.canTurnPrevious) {
      _direction = PageTurnDirection.previous;
      startMode = _GestureStartMode.corner;
    } else if (edgeNext && widget.canTurnNext) {
      _direction = PageTurnDirection.next;
      startMode = _GestureStartMode.edge;
    } else if (edgePrevious && widget.canTurnPrevious) {
      _direction = PageTurnDirection.previous;
      startMode = _GestureStartMode.edge;
    } else {
      _direction = null;
      return;
    }

    final normalizedLocal = _normalizeStartPosition(local, startMode, _viewport);
    setState(() {
      _phase = PageCurlPhase.dragging;
      _progress = 0.02;
      _dragPosition = normalizedLocal;
      _gestureStartMode = startMode;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_phase != PageCurlPhase.dragging || _direction == null) return;
    final local = _normalizeStartPosition(
      details.localPosition,
      _gestureStartMode ?? _GestureStartMode.corner,
      _viewport,
    );
    final progress = switch (_direction!) {
      PageTurnDirection.next =>
        ((1 - (local.dx / _viewport.width)) * 1.08).clamp(0.0, 1.0),
      PageTurnDirection.previous => ((local.dx / _viewport.width) * 1.08).clamp(
        0.0,
        1.0,
      ),
    };
    setState(() {
      _progress = progress;
      _dragPosition = local;
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_phase != PageCurlPhase.dragging || _direction == null) return;
    final velocity = details.velocity.pixelsPerSecond.dx;
    final fastForward = _direction == PageTurnDirection.next
        ? velocity < -900
        : velocity > 900;
    _completeOnRelease = _progress > 0.5 || fastForward;
    _animateSettle(_completeOnRelease ? 1 : 0);
  }

  void _animateSettle(double target) {
    _progressAnimation = Tween<double>(begin: _progress, end: target).animate(
      CurvedAnimation(parent: _settleController, curve: Curves.easeOutCubic),
    );
    setState(() {
      _phase = PageCurlPhase.settling;
    });
    _settleController.forward(from: 0);
  }

  void _onAnimationTick() {
    final animation = _progressAnimation;
    if (animation == null) return;
    setState(() {
      _progress = animation.value;
    });
  }

  void _onAnimationStatusChanged(AnimationStatus status) {
    if (status != AnimationStatus.completed || _direction == null) return;
    final completed = _completeOnRelease;
    final direction = _direction!;
    _progressAnimation = null;
    _completeOnRelease = false;
    setState(() {
      _phase = PageCurlPhase.idle;
      _progress = 0;
      _direction = null;
      _dragPosition = null;
      _gestureStartMode = null;
    });
    widget.onTurnFinished(
      PageTurnRequest(direction: direction, completed: completed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final interactive =
            _phase == PageCurlPhase.dragging ||
            _phase == PageCurlPhase.settling;
        final direction = _direction;
        final target = widget.targetPage;

        if (!interactive || direction == null || target == null) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: _handlePanStart,
            onPanUpdate: _handlePanUpdate,
            onPanEnd: _handlePanEnd,
            child: widget.currentPage,
          );
        }

        final isNext = direction == PageTurnDirection.next;
        final dragPosition = _resolveDragPosition(isNext);
        final foldStrength = Curves.easeOut.transform(
          _progress.clamp(0.0, 1.0),
        );
        final foldWidth = math.max(
          32.0,
          _viewport.width * (0.10 + 0.36 * foldStrength),
        );
        final tipX = dragPosition.dx;
        final tipY = dragPosition.dy;
        final liftBias = (0.5 - (tipY / _viewport.height)).clamp(-0.45, 0.45);
        final topFoldX = isNext
            ? (tipX + foldWidth * (0.24 + liftBias * 0.34)).clamp(
                0.0,
                _viewport.width,
              )
            : (tipX - foldWidth * (0.24 - liftBias * 0.34)).clamp(
                0.0,
                _viewport.width,
              );
        final bottomFoldX = isNext
            ? (tipX - foldWidth * (0.12 - liftBias * 0.18)).clamp(
                0.0,
                _viewport.width,
              )
            : (tipX + foldWidth * (0.12 + liftBias * 0.18)).clamp(
                0.0,
                _viewport.width,
              );
        final flapLeft = math.min(math.min(topFoldX, bottomFoldX), tipX);
        final flapRight = math.max(math.max(topFoldX, bottomFoldX), tipX);
        final flapWidth = math.max(
          1.0,
          isNext ? _viewport.width - flapLeft : flapRight,
        );
        final skew = (1 - _progress) * 0.06 * (isNext ? -1 : 1);
        final scaleX = 1 - 0.12 * _progress;

        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onPanStart: _handlePanStart,
          onPanUpdate: _handlePanUpdate,
          onPanEnd: _handlePanEnd,
          onPanCancel: () {
            if (_phase == PageCurlPhase.dragging) {
              _completeOnRelease = false;
              _animateSettle(0);
            }
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              target,
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipPath(
                    clipper: _PageBedShadowClipper(
                      direction: direction,
                      topFoldX: topFoldX,
                      bottomFoldX: bottomFoldX,
                      tip: Offset(tipX, tipY),
                      shadowDepth: math.max(18.0, foldWidth * 0.52),
                    ),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: isNext
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          end: isNext
                              ? Alignment.centerLeft
                              : Alignment.centerRight,
                          colors: [
                            Colors.black.withValues(
                              alpha: 0.05 + 0.16 * _progress,
                            ),
                            Colors.black.withValues(alpha: 0.03),
                            Colors.transparent,
                          ],
                          stops: const [0.0, 0.42, 1.0],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipPath(
                  clipper: _CurrentPageClipper(
                    direction: direction,
                    topFoldX: topFoldX,
                    bottomFoldX: bottomFoldX,
                    tip: Offset(tipX, tipY),
                  ),
                  child: widget.currentPage,
                ),
              ),
              Positioned(
                left: flapLeft,
                top: 0,
                bottom: 0,
                width: flapWidth,
                child: ClipPath(
                  clipper: _PageFlapClipper(
                    direction: direction,
                    topFoldX: topFoldX,
                    bottomFoldX: bottomFoldX,
                    tip: Offset(tipX, tipY),
                    anchorLeft: flapLeft,
                  ),
                  child: Transform(
                    alignment: isNext
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    transform: Matrix4.identity()
                      ..setEntry(1, 0, skew)
                      ..scaleByDouble(scaleX, 1.0, 1.0, 1.0),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        widget.currentPage,
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: isNext
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              end: isNext
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              colors: [
                                const Color(0xFFFDF6EA).withValues(alpha: 0.96),
                                const Color(0xFFF1E1CA).withValues(alpha: 0.90),
                                const Color(0xFFD2B699).withValues(alpha: 0.48),
                              ],
                              stops: const [0.0, 0.68, 1.0],
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: isNext
                                  ? Alignment.centerLeft
                                  : Alignment.centerRight,
                              end: isNext
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              colors: [
                                const Color(0xFFF3E8D9).withValues(alpha: 0.92),
                                const Color(0xFFE2D1C0).withValues(alpha: 0.74),
                                const Color(0xFFB99778).withValues(alpha: 0.18),
                              ],
                              stops: const [0.0, 0.72, 1.0],
                            ),
                          ),
                        ),
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.white.withValues(alpha: 0.22),
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.08),
                              ],
                              stops: const [0.0, 0.35, 1.0],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left:
                    (isNext
                            ? tipX - foldWidth * 0.16
                            : tipX - foldWidth * 0.70)
                        .clamp(0.0, _viewport.width),
                top: 0,
                bottom: 0,
                width: math.min(_viewport.width, foldWidth * 0.82),
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isNext
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: isNext
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          Colors.black.withValues(
                            alpha: 0.20 + 0.12 * _progress,
                          ),
                          Colors.black.withValues(alpha: 0.05),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: (isNext ? tipX - 2 : tipX - 6).clamp(
                  0.0,
                  _viewport.width,
                ),
                top: 0,
                bottom: 0,
                width: 10,
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: isNext
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        end: isNext
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        colors: [
                          Colors.white.withValues(alpha: 0.38),
                          Colors.black.withValues(alpha: 0.14),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Offset _resolveDragPosition(bool isNext) {
    final lastPosition = _dragPosition;
    final defaultY = _viewport.height * 0.84;
    if (lastPosition == null) {
      return Offset(
        isNext ? _viewport.width : 0,
        defaultY.clamp(24.0, _viewport.height - 12).toDouble(),
      );
    }
    final targetX = switch (_phase) {
      PageCurlPhase.dragging => lastPosition.dx,
      PageCurlPhase.settling => isNext
          ? _viewport.width * (1 - _progress)
          : _viewport.width * _progress,
      PageCurlPhase.idle => isNext ? _viewport.width : 0,
    };
    return Offset(
      targetX.clamp(0.0, _viewport.width).toDouble(),
      lastPosition.dy.clamp(24.0, _viewport.height - 12).toDouble(),
    );
  }
}

class _CurrentPageClipper extends CustomClipper<Path> {
  const _CurrentPageClipper({
    required this.direction,
    required this.topFoldX,
    required this.bottomFoldX,
    required this.tip,
  });

  final PageTurnDirection direction;
  final double topFoldX;
  final double bottomFoldX;
  final Offset tip;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (direction == PageTurnDirection.next) {
      path.moveTo(0, 0);
      path.lineTo(topFoldX, 0);
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(bottomFoldX, size.height);
      path.lineTo(0, size.height);
    } else {
      path.moveTo(size.width, 0);
      path.lineTo(topFoldX, 0);
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(bottomFoldX, size.height);
      path.lineTo(size.width, size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _CurrentPageClipper oldClipper) {
    return direction != oldClipper.direction ||
        topFoldX != oldClipper.topFoldX ||
        bottomFoldX != oldClipper.bottomFoldX ||
        tip != oldClipper.tip;
  }
}

class _PageFlapClipper extends CustomClipper<Path> {
  const _PageFlapClipper({
    required this.direction,
    required this.topFoldX,
    required this.bottomFoldX,
    required this.tip,
    required this.anchorLeft,
  });

  final PageTurnDirection direction;
  final double topFoldX;
  final double bottomFoldX;
  final Offset tip;
  final double anchorLeft;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (direction == PageTurnDirection.next) {
      path.moveTo(topFoldX - anchorLeft, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(bottomFoldX - anchorLeft, size.height);
      path.lineTo(tip.dx - anchorLeft, tip.dy);
    } else {
      path.moveTo(0, 0);
      path.lineTo(topFoldX - anchorLeft, 0);
      path.lineTo(tip.dx - anchorLeft, tip.dy);
      path.lineTo(bottomFoldX - anchorLeft, size.height);
      path.lineTo(0, size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PageFlapClipper oldClipper) {
    return direction != oldClipper.direction ||
        topFoldX != oldClipper.topFoldX ||
        bottomFoldX != oldClipper.bottomFoldX ||
        tip != oldClipper.tip ||
        anchorLeft != oldClipper.anchorLeft;
  }
}

class _PageBedShadowClipper extends CustomClipper<Path> {
  const _PageBedShadowClipper({
    required this.direction,
    required this.topFoldX,
    required this.bottomFoldX,
    required this.tip,
    required this.shadowDepth,
  });

  final PageTurnDirection direction;
  final double topFoldX;
  final double bottomFoldX;
  final Offset tip;
  final double shadowDepth;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (direction == PageTurnDirection.next) {
      final topOuter = math.max(0.0, topFoldX - shadowDepth);
      final midOuter = math.max(0.0, tip.dx - shadowDepth * 0.38);
      final bottomOuter = math.max(0.0, bottomFoldX - shadowDepth);
      path.moveTo(topOuter, 0);
      path.lineTo(topFoldX, 0);
      path.lineTo(tip.dx, tip.dy);
      path.lineTo(bottomFoldX, size.height);
      path.lineTo(bottomOuter, size.height);
      path.lineTo(midOuter, tip.dy);
    } else {
      final topOuter = math.min(size.width, topFoldX + shadowDepth);
      final midOuter = math.min(size.width, tip.dx + shadowDepth * 0.38);
      final bottomOuter = math.min(size.width, bottomFoldX + shadowDepth);
      path.moveTo(topFoldX, 0);
      path.lineTo(topOuter, 0);
      path.lineTo(midOuter, tip.dy);
      path.lineTo(bottomOuter, size.height);
      path.lineTo(bottomFoldX, size.height);
      path.lineTo(tip.dx, tip.dy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PageBedShadowClipper oldClipper) {
    return direction != oldClipper.direction ||
        topFoldX != oldClipper.topFoldX ||
        bottomFoldX != oldClipper.bottomFoldX ||
        tip != oldClipper.tip ||
        shadowDepth != oldClipper.shadowDepth;
  }
}
