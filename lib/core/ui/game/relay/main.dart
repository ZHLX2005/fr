// lib/core/ui/game/relay/main.dart
//
// 共享的 WS 连接状态条 — 所有基于 Lua 的互联网房间游戏通用。
//
// 显示：
//   ● 已连接（绿）     [☁ 拉取最新快照]
//   ● 已断开 · 自动重连中（红） [⏳ 拉取中…]
//
// 设计要点：
//   - 自带 stream 订阅（closeEvents + snapshots），调用方无需管理
//   - 内置 fetchSnapshot 调用 + 防双击 spinner + 失败 snackbar
//   - 28px 固定高度（避免出现/消失撑动下方操作栏）
//   - 圆点颜色用 Theme.colorScheme.primary / error，跨主题自适应
//
// 用法：
//   final bar = RelayConnectionBar(handle: handle, theme: theme);
//   // 嵌入任意 Column 的底部
//   bar

import 'dart:async';

import 'package:flutter/material.dart';

import '../../global/notification/main.dart';
import '../../../net_engine/relay_v3/relay_v3_transport.dart';

/// WS 连接状态条（圆点 + 文字 + 拉取最新快照按钮）。
///
/// 自带 stream 订阅 + 防双击 + 失败 snackbar，调用方只需把它放进布局。
class RelayConnectionBar extends StatefulWidget {
  const RelayConnectionBar({super.key, required this.handle});

  final RoomHandle handle;

  @override
  State<RelayConnectionBar> createState() => _RelayConnectionBarState();
}

class _RelayConnectionBarState extends State<RelayConnectionBar> {
  StreamSubscription<Snapshot>? _sub;
  StreamSubscription<dynamic>? _closeSub;

  bool _wsConnected = false;
  bool _pulling = false;

  @override
  void initState() {
    super.initState();
    _wsConnected = widget.handle.isConnected;
    _sub = widget.handle.snapshots.listen(_onSnapshot);
    _closeSub = widget.handle.closeEvents.listen(_onWSClose);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _closeSub?.cancel();
    super.dispose();
  }

  void _onSnapshot(Snapshot _) {
    if (!mounted) return;
    setState(() => _wsConnected = widget.handle.isConnected);
  }

  void _onWSClose(dynamic _) {
    if (!mounted) return;
    setState(() => _wsConnected = widget.handle.isConnected);
  }

  Future<void> _pullSnapshot() async {
    if (_pulling) return;
    setState(() => _pulling = true);
    try {
      await widget.handle.fetchSnapshot();
    } catch (_) {
      if (!mounted) return;
      AppNotification.show(context, '拉取快照失败（HTTP）',
          type: AppNotificationType.error);
    } finally {
      if (mounted) setState(() => _pulling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dotColor = _wsConnected
        ? theme.colorScheme.primary
        : theme.colorScheme.error;
    final statusText = _wsConnected ? '已连接' : '已断开 · 自动重连中';
    final btnSub = theme.colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 28,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withValues(alpha: 0.3),
          border: Border(
            top: BorderSide(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: dotColor.withValues(alpha: 0.6),
                    blurRadius: 4,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                color: _wsConnected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                letterSpacing: 1,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _pulling ? null : _pullSnapshot,
              icon: _pulling
                  ? SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: btnSub,
                      ),
                    )
                  : Icon(Icons.cloud_download_outlined, size: 14, color: btnSub),
              label: Text(
                _pulling ? '拉取中…' : '拉取最新快照',
                style: TextStyle(fontSize: 11, color: btnSub),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── RelayConnectionStatusBadge（AppBar 用连接状态徽标）──



/// WS 连接状态徽标（圆点 + 文字 + 可选 spinner）。
///
/// 小巧：≤ 80 LOC，含自有订阅 + 三态切换。专为对弈页 AppBar 设计。
class RelayConnectionStatusBadge extends StatefulWidget {
  const RelayConnectionStatusBadge({super.key, required this.handle});

  final RoomHandle handle;

  @override
  State<RelayConnectionStatusBadge> createState() =>
      _RelayConnectionStatusBadgeState();
}

class _RelayConnectionStatusBadgeState
    extends State<RelayConnectionStatusBadge> {
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
