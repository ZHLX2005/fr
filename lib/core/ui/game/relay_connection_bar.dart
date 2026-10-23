// lib/core/net_engine/relay_v3/relay_connection_bar.dart
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

import 'relay_v3_transport.dart';

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
      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('拉取快照失败（HTTP）'),
          duration: Duration(seconds: 2),
        ),
      );
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
