import 'package:flutter/material.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../design_tokens/spacing.dart';
import 'nxkv_controller.dart';
import 'nxkv_widgets.dart';

/// 「契约」视图：端侧与服务端**是不是还说着同一种话**。
///
/// 这一页存在的理由很实在：fr 只维护 UI，协议全在 nx-kv 那边演进。
/// 于是「端侧跑的生成物是不是过期了」必须是个**用户可见的状态**，而不是
/// 一个只有 agent 在 CI 日志里才知道的事实。
///
/// 三块内容：
///   1. 指纹对账（本地生成物 vs `GET /api/contract`）；
///   2. 契约里有什么（action × 路由 × 说明）；
///   3. 这些能力**本界面接了几条** —— 对不上的就是「契约有、UI 没接」。
class NxKvContractView extends StatelessWidget {
  const NxKvContractView({super.key, required this.controller});

  final NxKvController controller;

  /// 本界面真正调用过的 action。与契约对账，差集就是「UI 还没接」。
  ///
  /// 这是一个**手维护的清单**（诚实说：它是本页唯一的软肋）——所以它很短，
  /// 短到 review 时能一眼看完。真正的强校验在编译期：少一条方法直接编不过。
  static const Set<String> wired = {
    'localtask.list',
    'localtask.tasks',
    'localtask.get',
    'localtask.claim',
    'localtask.add',
    'localtask.done',
    'localtask.reopen',
    'system.contract',
    'system.bootstrap',
  };

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final cs = Theme.of(context).colorScheme;
    final remote = c.remoteContract;

    return RefreshIndicator(
      onRefresh: c.checkContract,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          // ① 指纹
          NxKvSection(
            title: '契约指纹',
            trailing: c.contractLoading
                ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                : null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      c.drift == null ? Icons.verified_outlined : Icons.report_problem_outlined,
                      size: 16,
                      color: c.drift == null ? cs.primary : cs.error,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        c.drift == null ? '端侧与服务端同一份契约' : '端侧跑在旧契约上',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: c.drift == null ? cs.primary : cs.error,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                NxKvMetaRow('端侧', '${c.localHash} · ${c.localVersion}'),
                NxKvMetaRow('服务端', remote == null ? '—' : '${remote.hash} · ${remote.version}'),
                if (c.drift != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(c.drift!, style: TextStyle(fontSize: 11, color: cs.error, height: 1.5)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '拧法：fr 仓库 `flutter pub upgrade nx_kv_client` → 提交 pubspec.lock 的一行变更。'
                    '夜跑机器人会替你做这件事（`sync-nxkv-contract.yml`）。',
                    style: TextStyle(fontSize: 10, color: cs.outline, height: 1.6),
                  ),
                ],
                if (c.contractError != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text('拉不到契约：${c.contractError}', style: TextStyle(fontSize: 11, color: cs.error)),
                  TextButton(onPressed: c.checkContract, child: const Text('重试')),
                ],
              ],
            ),
          ),

          // ② 能力清单
          if (remote != null)
            NxKvSection(
              title: '契约给了什么（${remote.actions.length} 条 action）',
              trailing: Text(
                '本界面接了 ${remote.actions.where((a) => wired.contains(a.id)).length}',
                style: TextStyle(fontSize: 10, color: cs.outline),
              ),
              child: Column(
                children: [
                  for (final a in remote.actions) _actionRow(a, cs),
                ],
              ),
            ),

          // ③ 说明
          NxKvSection(
            title: '这一页为什么存在',
            child: Text(
              'fr 只维护 UI，协议全在 nx-kv 侧演进。于是「端侧的生成物是否过期」'
              '必须是看得见的状态 —— 对不上时，页面照常能开，但会在这里说清楚是哪一边旧了。',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, height: 1.7),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
        ],
      ),
    );
  }

  Widget _actionRow(kv.ContractAction a, ColorScheme cs) {
    final on = wired.contains(a.id);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            on ? Icons.check_circle_outline : Icons.remove_circle_outline,
            size: 13,
            color: on ? cs.primary : cs.outlineVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.id,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: on ? cs.onSurface : cs.outline,
                  ),
                ),
                if (a.http != null)
                  Text(
                    a.http!,
                    style: TextStyle(fontSize: 9, fontFamily: 'monospace', color: cs.outline.withValues(alpha: 0.8)),
                  ),
              ],
            ),
          ),
          Text(
            on ? '已接' : '未接',
            style: TextStyle(fontSize: 9, color: on ? cs.primary : cs.outlineVariant),
          ),
        ],
      ),
    );
  }
}
