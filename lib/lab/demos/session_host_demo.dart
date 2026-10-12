// lib/lab/demos/session_host_demo.dart
//
// 会话托管监视（调试面板）：看 DemoSessionHost 上现在挂着哪些会话、
// 谁 detached 了多久、离回收阈值多远；支持手动 drop 真销毁。
// P2 治理工具——联机房间类迁移后排查「僵尸会话 / 忘了 drop」的第一现场。
// 本 demo 刻意保持默认 page scope：看板随页面走，不给自己托管。

import 'dart:async';

import 'package:flutter/material.dart';

import '../demo_session_host.dart';
import '../lab_container.dart';

/// Lab demo 注册项
class SessionHostDemo extends DemoPage {
  @override
  String get title => '会话托管监视';

  @override
  String get slug => 'session-host';

  @override
  String get description =>
      '调试：查看 DemoSessionHost 活动会话（detached 时长/状态类型），可手动 drop';

  @override
  Widget buildPage(BuildContext context) => const _SessionHostPanelPage();
}

class _SessionHostPanelPage extends StatefulWidget {
  const _SessionHostPanelPage();

  @override
  State<_SessionHostPanelPage> createState() => _SessionHostPanelPageState();
}

class _SessionHostPanelPageState extends State<_SessionHostPanelPage> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // host 不是 Listenable：面板轮询拿新数据（调试场景 2s 足够，
    // 不为它给 host 装事件流）
    _tick = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  Future<void> _drop(String slug) async {
    await demoSessionHost.drop(slug);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('已 drop $slug')),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sessions = demoSessionHost.active.values.toList()
      ..sort((a, b) => a.slug.compareTo(b.slug));
    if (sessions.isEmpty) {
      return Center(
        child: Text(
          '当前没有活动会话\n（session scope 的 demo 连接后出现在这里）',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final hs = sessions[i];
        return _SessionCard(hs: hs, onDrop: () => _drop(hs.slug));
      },
    );
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({required this.hs, required this.onDrop});

  final HostedSession hs;
  final Future<void> Function() onDrop;

  String get _status {
    final d = hs.detachedAt;
    if (d == null) return 'attached（页面在场）';
    final mins = DateTime.now().difference(d).inMinutes;
    final left = kSessionIdleReapTimeout.inMinutes - mins;
    return 'detached ${mins}m · 距回收 ${left < 0 ? '已过期' : '${left}m'}';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: cs.shadow.withValues(alpha: 0.06),
      surfaceTintColor: Colors.transparent,
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(
          hs.detached ? Icons.link_off_rounded : Icons.link_rounded,
          color: hs.detached ? cs.tertiary : cs.primary,
        ),
        title: Text(
          hs.slug,
          style: TextStyle(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
        subtitle: Text(
          '${hs.state.runtimeType} · $_status',
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline_rounded, color: cs.error),
          tooltip: 'drop（真销毁）',
          onPressed: onDrop,
        ),
      ),
    );
  }
}

void registerSessionHostDemo() => demoRegistry.register(SessionHostDemo());
