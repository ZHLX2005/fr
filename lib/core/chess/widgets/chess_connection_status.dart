// lib/core/chess/widgets/chess_connection_status.dart
//
// 国际象棋对弈页的"WS 连接状态徽标"（AppBar leading 用）。
//
// 职责：
//   · 订阅 handle.closeEvents（瞬断 → 橙） + handle.snapshots（恢复 → 绿）
//   · 三态显示：
//       connected（绿点 · "已连接"）
//       reconnecting（橙点 + 旋转小圈 · "重连中…"）— 收到 close 但还没回到快照
//       disposed（页面退出）— 状态徽标消失（依赖 widget tree dispose）
//
// 与 [RelayConnectionBar]（底部 28px 长条）的差异：
//   - 极简：单色点 + 短文字，紧凑放在 AppBar 里不挤走 room code
//   - 主动：橙态带 spinner，提示"正在尝试重新连接"
//   - 颜色走 context.chessColors（v6.2 第 6 strategy 通道），不写死 Color(0xFF...)
//
// 用法：
//   appBar: AppBar(
//     leading: ChessConnectionStatusBadge(handle: widget.handle),
//     title: Text('房间 ${snap.roomCode}'),
//     actions: [ ... ],
//   )

import 'dart:async';

import 'package:flutter/material.dart';

import '../../net_engine/relay_v3/relay_v3_transport.dart';

/// WS 连接状态徽标（圆点 + 文字 + 可选 spinner）。
///
/// 小巧：≤ 80 LOC，含自有订阅 + 三态切换。专为对弈页 AppBar 设计。
class ChessConnectionStatusBadge extends StatefulWidget {
  const ChessConnectionStatusBadge({super.key, required this.handle});

  final RoomHandle handle;

  @override
  State<ChessConnectionStatusBadge> createState() =>
      _ChessConnectionStatusBadgeState();
}

class _ChessConnectionStatusBadgeState extends State<ChessConnectionStatusBadge> {
  StreamSubscription<WSCloseEvent>? _closeSub;
  StreamSubscription<Snapshot>? _snapSub;

  /// true = 收到 close event 但还没回到快照 → 显示橙 + spinner。
  bool _reconnecting = false;

  @override
  void initState() {
    super.initState();
    // closeEvents：瞬断触发 → 进入橙态。RoomHandle 内部会自动重连。
    _closeSub = widget.handle.closeEvents.listen(_onClose);
    // snapshots：任意新快照到达 → WS 恢复 → 退出橙态。
    _snapSub = widget.handle.snapshots.listen(_onSnapshot);
  }

  @override
  void dispose() {
    _closeSub?.cancel();
    _snapSub?.cancel();
    super.dispose();
  }

  void _onClose(WSCloseEvent _) {
    if (!mounted) return;
    setState(() => _reconnecting = true);
  }

  void _onSnapshot(Snapshot _) {
    if (!mounted) return;
    if (_reconnecting) {
      setState(() => _reconnecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 已连接 = 主题 primary；重连中 = error/橙（跨主题自适应）。
    final dotColor =
        _reconnecting ? theme.colorScheme.error : theme.colorScheme.primary;
    final text = _reconnecting ? '重连中…' : '已连接';
    final fg = _reconnecting
        ? theme.colorScheme.onSurfaceVariant
        : theme.colorScheme.onSurface;

    // FittedBox scaleDown： AppBar leading 槽窄（默认 48 / 本页 86）时
    // 整体等比缩小，绝不让 Row 溢出报错。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 圆点（带柔光阴影）
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.5),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: fg,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5,
              ),
            ),
            if (_reconnecting) ...[
              const SizedBox(width: 6),
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.4,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
