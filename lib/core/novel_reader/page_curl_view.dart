import 'dart:math' as math;

import 'package:flutter/material.dart';

enum PageTurnDirection { next, previous }

enum PageCurlPhase { idle, dragging, settling }

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

  void _handlePanStart(DragStartDetails details) {
    if (_phase == PageCurlPhase.settling || _viewport == Size.zero) return;

    final local = details.localPosition;
    final wantNext = _isInHotZone(local, _viewport, PageTurnDirection.next);
    final wantPrevious = _isInHotZone(
      local,
      _viewport,
      PageTurnDirection.previous,
    );

    if (wantNext && widget.canTurnNext) {
      _direction = PageTurnDirection.next;
    } else if (wantPrevious && widget.canTurnPrevious) {
      _direction = PageTurnDirection.previous;
    } else {
      _direction = null;
      return;
    }

    setState(() {
      _phase = PageCurlPhase.dragging;
      _progress = 0.02;
    });
  }

  void _handlePanUpdate(DragUpdateDetails details) {
    if (_phase != PageCurlPhase.dragging || _direction == null) return;
    final local = details.localPosition;
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
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.currentPage,
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: _CornerHint(
                    alignment: Alignment.bottomRight,
                    active: widget.canTurnNext,
                  ),
                ),
                Positioned(
                  left: 16,
                  bottom: 16,
                  child: _CornerHint(
                    alignment: Alignment.bottomLeft,
                    active: widget.canTurnPrevious,
                  ),
                ),
              ],
            ),
          );
        }

        final isNext = direction == PageTurnDirection.next;
        final foldStrength = Curves.easeOut.transform(
          _progress.clamp(0.0, 1.0),
        );
        final foldWidth = math.max(
          32.0,
          _viewport.width * (0.10 + 0.36 * foldStrength),
        );
        final foldX = isNext
            ? _viewport.width * (1 - _progress)
            : _viewport.width * _progress;
        final visibleCurrentWidth = isNext
            ? foldX.clamp(0.0, _viewport.width)
            : (_viewport.width - foldX).clamp(0.0, _viewport.width);
        final flapLeft = isNext ? math.max(0.0, foldX - foldWidth) : foldX;
        final flapWidth = isNext
            ? (_viewport.width - flapLeft).clamp(0.0, _viewport.width)
            : math.min(_viewport.width, foldWidth + foldX);
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
                child: ClipRect(
                  clipper: _VisiblePageClipper(
                    direction: direction,
                    visibleExtent: visibleCurrentWidth,
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
                    foldWidth: foldWidth,
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
                        target,
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
                            ? foldX - foldWidth * 0.18
                            : foldX - foldWidth * 0.72)
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
                left: (isNext ? foldX - 2 : foldX - 6).clamp(
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
}

class _VisiblePageClipper extends CustomClipper<Rect> {
  const _VisiblePageClipper({
    required this.direction,
    required this.visibleExtent,
  });

  final PageTurnDirection direction;
  final double visibleExtent;

  @override
  Rect getClip(Size size) {
    if (direction == PageTurnDirection.next) {
      return Rect.fromLTWH(0, 0, visibleExtent, size.height);
    }
    return Rect.fromLTWH(
      size.width - visibleExtent,
      0,
      visibleExtent,
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _VisiblePageClipper oldClipper) {
    return direction != oldClipper.direction ||
        visibleExtent != oldClipper.visibleExtent;
  }
}

class _PageFlapClipper extends CustomClipper<Path> {
  const _PageFlapClipper({required this.direction, required this.foldWidth});

  final PageTurnDirection direction;
  final double foldWidth;

  @override
  Path getClip(Size size) {
    final path = Path();
    if (direction == PageTurnDirection.next) {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width, size.height);
      path.lineTo(foldWidth * 0.12, size.height);
    } else {
      path.moveTo(0, 0);
      path.lineTo(size.width, 0);
      path.lineTo(size.width - foldWidth * 0.12, size.height);
      path.lineTo(0, size.height);
    }
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant _PageFlapClipper oldClipper) {
    return direction != oldClipper.direction ||
        foldWidth != oldClipper.foldWidth;
  }
}

class _CornerHint extends StatelessWidget {
  const _CornerHint({required this.alignment, required this.active});

  final Alignment alignment;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final isRight = alignment == Alignment.bottomRight;
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: active ? 1 : 0,
        duration: const Duration(milliseconds: 160),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isRight ? 24 : 8),
              topRight: Radius.circular(isRight ? 8 : 24),
              bottomLeft: const Radius.circular(24),
              bottomRight: const Radius.circular(24),
            ),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: 0.12),
                Colors.black.withValues(alpha: 0.08),
              ],
            ),
          ),
          child: Icon(
            isRight ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
            color: Colors.black45,
          ),
        ),
      ),
    );
  }
}
