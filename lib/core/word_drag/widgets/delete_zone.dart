import 'package:flutter/material.dart';

/// 右侧删除区域组件
///
/// 特性：
/// 1. 位于屏幕右侧中央
/// 2. 随卡片靠近逐渐显现（透明度+大小）
/// 3. 卡片进入区域后高亮，释放才删除
class DeleteZone extends StatelessWidget {
  final bool isActive;
  final double opacity; // 0.0 - 1.0，透明度
  final double progress; // 0.0 - 1.0，拖动进度
  final VoidCallback? onDeleteTriggered;

  const DeleteZone({
    super.key,
    this.isActive = false,
    this.opacity = 1.0,
    this.progress = 0.0,
    this.onDeleteTriggered,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity.clamp(0.0, 1.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 80 + progress * 40,
        height: 120 + progress * 60,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isActive
                ? [Colors.red.shade500, Colors.red.shade700]
                : [Colors.grey.shade800, Colors.grey.shade900],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(24 + progress * 12),
          border: Border.all(
            color: isActive
                ? Colors.red.shade300.withValues(alpha: 0.8)
                : Colors.grey.shade700,
            width: 2 + progress * 2,
          ),
          boxShadow: [
            BoxShadow(
              color: isActive
                  ? Colors.red.withValues(alpha: 0.4 + progress * 0.3)
                  : Colors.black.withValues(alpha: 0.3),
              blurRadius: isActive ? 20 + progress * 15 : 10,
              spreadRadius: isActive ? 2 + progress * 5 : 0,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: isActive ? 1.3 : 1.0,
              duration: const Duration(milliseconds: 150),
              child: Icon(
                Icons.delete,
                color: isActive ? Colors.white : Colors.grey,
                size: 36 + progress * 12,
              ),
            ),
            const SizedBox(height: 8),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.grey,
                fontSize: 12 + progress * 4,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
              child: Text(isActive ? '释放删除' : '拖到这里'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 删除区检测器 - 检测卡片是否进入删除区
class DeleteZoneDetector extends StatefulWidget {
  final Widget child;
  final Rect zoneRect;
  final Function(bool isInZone) onZoneStatusChanged;
  final VoidCallback? onDeleteTriggered;

  const DeleteZoneDetector({
    super.key,
    required this.child,
    required this.zoneRect,
    required this.onZoneStatusChanged,
    this.onDeleteTriggered,
  });

  @override
  State<DeleteZoneDetector> createState() => _DeleteZoneDetectorState();
}

class _DeleteZoneDetectorState extends State<DeleteZoneDetector> {
  bool _isInZone = false;

  void checkPosition(Offset cardCenter) {
    // 扩大检测区域，让进入更容易
    final expandedRect = widget.zoneRect.inflate(20);
    final isInZone = expandedRect.contains(cardCenter);

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
        // 删除确认覆盖层
        if (_isInZone)
          Positioned.fill(
            child: GestureDetector(
              onTap: widget.onDeleteTriggered,
              child: Container(
                color: Colors.red.withValues(alpha: 0.15),
                child: const Center(
                  child: Text(
                    '松开删除',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      shadows: [
                        Shadow(
                          color: Colors.black54,
                          blurRadius: 10,
                        ),
                      ],
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
