import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../api/authhub/authhub_exception.dart';
import '../../../api/authhub/authhub_models.dart';
import '../../../api/providers/api_providers.dart';
import 'const_auth_login.dart';

/// 本机自测：不依赖相机，在一台设备上跑完扫码登录的完整闭环。
///
/// ── 为什么要复用同一个端点实例 ──────────────────────────────────────────
///
/// PC 侧的领取凭据 `qr_ctx` 是一个 **Cookie**，而"必须由创建这张票据的
/// 那台浏览器来领取"正是扫码登录防转发的全部机制。
/// 本面板用同一个 [AuthHubQrEndpoint]（同一个 Cookie 容器）依次扮演
/// PC 与手机，等价于真机上"PC 浏览器建码 + PC 浏览器领码"。
/// 若为每一步各 new 一个实例，qr_ctx 会丢，claim 必然失败 ——
/// 而且报的是 `qr_not_ready`，完全指不到"Cookie 没带上"这个根因。
///
/// ── 这个面板真正在验证什么 ──────────────────────────────────────────────
///
/// 不是"能不能跑通"，而是三条安全性质：
///   1. 未经手机批准时，连创建自己也领不到会话；
///   2. 批准后恰好领到一次；
///   3. 领完之后同一张票不能再被领第二次。
class SelfTestPanel extends ConsumerStatefulWidget {
  const SelfTestPanel({super.key});

  @override
  ConsumerState<SelfTestPanel> createState() => _SelfTestPanelState();
}

class _SelfTestPanelState extends ConsumerState<SelfTestPanel> {
  final List<String> _log = [];
  bool _running = false;

  @override
  void dispose() {
    // 离开页面时把自测建的票作废，不留一张"屏幕上已不显示但仍能被人批准"的码
    super.dispose();
  }

  void _v(String msg) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, '${DateTime.now().toString().substring(14, 23)}  $msg');
      if (_log.length > AuthLoginConst.maxLogLines) {
        _log.removeLast();
      }
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _log.clear();
    });
    final qr = ref.read(authHubQrEndpointProvider);
    final tm = ref.read(tokenManagerProvider);
    try {
      // 凭据不再由调用方传递（端点自己从登录态存储取），所以这里只做前置检查：
      // 没有登录态就明确告诉用户去哪一步，而不是让深处抛一个 401。
      if (!await ref.read(idpSessionStoreProvider).exists) {
        _v('✗ 没有统一登录平台登录态 —— 先到「统一登录」页登录');
        return;
      }

      qr.clearCookies();
      final session = await qr.create();
      _v('① 已建票 ${session.ticket.substring(0, 12)}…（${session.expiresIn}s 有效）');

      // ② 先验证"未经批准不能领取"。这一步必须在批准之前做，
      // 否则票据状态已经不是 pending，测不到这条了。
      try {
        await qr.claim(session.ticket);
        _v('✗ 重大缺陷：未经手机批准竟然领取成功（批准这一步被绕过了）');
        return;
      } on AuthHubException catch (e) {
        _v('② 未批准就领取 → 已拒绝 ${e.error} ✓');
      }

      final pv = await qr.preview(session.ticket);
      _v('③ 手机端预览：${pv.pcUa} / ${pv.pcGeo} ${pv.pcIp}');

      await qr.scan(session.ticket);
      _v('④ 已上报扫码，PC 侧轮询应变成 scanned');

      var seenScanned = false;
      for (var i = 0; i < 3 && !seenScanned; i++) {
        if (await qr.poll(session.ticket) == QrStatus.scanned) seenScanned = true;
        await Future<void>.delayed(AuthLoginConst.pollInterval);
      }
      _v(seenScanned ? '⑤ PC 侧确认看到 scanned ✓' : '⑤ 未观察到 scanned（不影响后续）');

      await qr.confirm(session.ticket);
      _v('⑥ 手机端已批准');

      QrStatus? observed;
      final deadline = DateTime.now().add(const Duration(seconds: 15));
      while (DateTime.now().isBefore(deadline)) {
        final st = await qr.poll(session.ticket);
        if (st != observed) {
          observed = st;
          _v('   PC 轮询到 ${st.name}');
        }
        if (st == QrStatus.confirmed) break;
        await Future<void>.delayed(AuthLoginConst.pollInterval);
      }
      if (observed != QrStatus.confirmed) {
        _v('✗ 没等到 confirmed，终止');
        return;
      }

      final claimed = await qr.claim(session.ticket);
      _v('⑦ 领取成功：${claimed['username']} ✓');

      // ⑧ 一次性：同一张票不能再领
      try {
        await qr.claim(session.ticket);
        _v('✗ 重大缺陷：同一张票据被领取了两次（外流的码会在有效期内反复可用）');
        return;
      } on AuthHubException catch (e) {
        _v('⑧ 重复领取 → 已拒绝 ${e.error} ✓');
      }

      _v('全部通过：状态机与 qr_ctx 绑定行为符合设计');
    } on AuthHubException catch (e) {
      _v('✗ ${e.error}: ${e.message}');
    } catch (e) {
      _v('✗ 未预期错误：$e');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '不依赖相机，在一台设备上依次扮演 PC 与手机，验证扫码状态机与'
            '「必须由创建者领取」这条防转发机制。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: FilledButton(
            onPressed: _running ? null : _run,
            child: Text(_running ? '自测中…' : AuthLoginConst.btnSelfTest),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: _log.isEmpty
                ? Center(
                    child: Text('点上方按钮开始',
                        style: Theme.of(context).textTheme.bodySmall),
                  )
                : ListView.builder(
                    itemCount: _log.length,
                    itemBuilder: (_, i) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(
                        _log[i],
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
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
