import 'package:flutter/material.dart';

/// 删除区域组件
///
/// 特性：
/// 1. 卡片进入时高亮
/// 2. 卡片进入删除区时触发确认删除
/// 3. 弹性动画反馈
class DeleteZone extends StatefulWidget {
  final bool isActive;
  final VoidCallback? onDeleteConfirmed;
  final double height;

  const DeleteZone({
    super.key,
    this.isActive = false,
    this.onDeleteConfirmed,
    this.height = 80,
  });

  @override
  State<DeleteZone> createState() => _DeleteZoneState();
}

class _DeleteZoneState extends State<DeleteZone>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(DeleteZone oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _pulseController.forward().then((_) => _pulseController.reverse());
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.isActive ? _pulseAnimation.value : 1.0,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: widget.height,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: widget.isActive
                    ? [Colors.red.shade400, Colors.red.shade600]
                    : [Colors.grey.shade700, Colors.grey.shade800],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: widget.isActive
                  ? [
                      BoxShadow(
                        color: Colors.red.withOpacity(0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedRotation(
                    turns: widget.isActive ? 0.1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.delete_outline,
                      color: widget.isActive ? Colors.white : Colors.grey,
                      size: 32,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    widget.isActive ? '释放删除' : '拖动删除',
                    style: TextStyle(
                      color: widget.isActive ? Colors.white : Colors.grey,
                      fontSize: 16,
                      fontWeight:
                          widget.isActive ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 检测卡片是否进入删除区的组件
class DeleteZoneDetector extends StatefulWidget {
  final Widget child;
  final Rect deleteZoneRect;
  final Function(bool isInZone) onZoneStatusChanged;
  final VoidCallback? onDeleteTriggered;

  const DeleteZoneDetector({
    super.key,
    required this.child,
    required this.deleteZoneRect,
    required this.onZoneStatusChanged,
    this.onDeleteTriggered,
  });

  @override
  State<DeleteZoneDetector> createState() => _DeleteZoneDetectorState();
}

class _DeleteZoneDetectorState extends State<DeleteZoneDetector> {
  bool _isInZone = false;

  void checkIfCardInZone(Offset cardCenter) {
    final isInZone = widget.deleteZoneRect.contains(cardCenter);
    if (isInZone != _isInZone) {
      setState(() => _isInZone = isInZone);
      widget.onZoneStatusChanged(isInZone);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_isInZone)
          Positioned(
            left: widget.deleteZoneRect.left,
            top: widget.deleteZoneRect.top,
            width: widget.deleteZoneRect.width,
            height: widget.deleteZoneRect.height,
            child: GestureDetector(
              onTap: widget.onDeleteTriggered,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.red.withOpacity(0.5),
                    width: 2,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
