import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../api/mnws/mnws.dart';
import '../../../../core/note/composer/md_composer.dart';
import '../../../../design_tokens/spacing.dart';
import '../mnws_app_views.dart';
import 'nxkv_contract_view.dart';
import 'nxkv_controller.dart';
import 'nxkv_drawer.dart';
import 'nxkv_queue_view.dart';
import 'nxkv_task_view.dart';
import 'nxkv_topics_view.dart';

/// nx-kv 的**原生面板**（在 fr 里）。
///
/// ## 与 nx-kv 自己的面板对位
///
///   | nx-kv 面板 | 这里 |
///   |---|---|
///   | 任务页（主题 + 队列） | 抽屉 + [NxKvQueueView] |
///   | 一条任务的正文 | [NxKvTaskView] |
///   | 契约与能力 | [NxKvContractView]（抽屉底部进） |
///
/// 底下全是同一份**生成出来的**客户端（`package:nx_kv_client`），
/// 页面里没有一行手写 HTTP：nx-kv 加一条 action，端侧 `pub upgrade` 就能用。
///
/// ## 这一版的版面（第 1 轮验收反馈的落点）
///
/// 反馈原文三条，按顺序：
///
///   1. 「头部 nav 影响视觉，去掉 nav，确保可视空间最大化」——
///      原来的 AppBar（56）+ TabBar（48）+ 连接条（30）一共 134dp 常驻在顶上，
///      而这一页真正要看的只有一条任务的正文。现在整条 nav 拆掉，只在顶部留
///      36dp 的**上下文条**（菜单 + 现在在哪条任务上），可视高度多出近 100dp。
///   2. 「增加抽屉侧边栏组件，通过侧边栏切换任务，同时需要搜索框选取任务或 picker topic」——
///      见 [NxKvDrawer]：搜索框 + 主题选择器 + 任务清单三件套。
///   3. 「确保编辑区有 80% 的编辑空间」——
///      任务页的 chrome 只剩 36（上下文条）+ 40（动作条）= 76dp，正文拿到 ~88%；
///      编辑页（[MdComposerPage]）也只留 44 + 40 + 48 三条，正文同样过 80%。
///
/// ## 为什么第一屏是队列而不是任务
///
/// 手机上打开这个页面的人，八成是「想知道现在有什么活」。所以没有「当前任务」
/// 时它就是一个队列；点一条才进正文 —— 抽屉负责在两者之间横跳。
class NxKvPage extends ConsumerStatefulWidget {
  const NxKvPage({super.key, required this.target});

  final MnWsAppTarget target;

  @override
  ConsumerState<NxKvPage> createState() => _NxKvPageState();
}

class _NxKvPageState extends ConsumerState<NxKvPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  NxKvController? _controller;

  /// 主区正在看哪条任务；null = 停在队列。
  int? _taskId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 端点要从 riverpod 拿，所以不能在 initState 里建
    if (_controller != null) return;
    final c = NxKvController(
      target: widget.target,
      endpoint: ref.read(mnWsEndpointProvider),
    );
    _controller = c;
    c.bootstrap();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // ── 主区切换 ──────────────────────────────────────────────

  void _open(int? id) {
    setState(() => _taskId = id);
    _closeDrawer();
  }

  /// 换主题：主区回到该主题的队列，抽屉留着（人还要在里面挑活）。
  void _switchTopic(String key) {
    _controller!.select(key);
    setState(() => _taskId = null);
  }

  void _closeDrawer() {
    final s = _scaffold.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
  }

  // ── 动作（抽屉里点的那两个）────────────────────────────────

  Future<void> _claim() async {
    final c = _controller!;
    final topic = c.selected;
    if (topic == null) return;
    _closeDrawer();
    try {
      final r = await c.claim(topic);
      await c.refresh();
      if (!mounted) return;
      if (r.status == kv.LocaltaskClaimStatus.ok && r.taskId != null) {
        _open(r.taskId);
      } else {
        _toast(r.status == kv.LocaltaskClaimStatus.blocked
            ? '这个主题的任务被依赖挡住了，先去完成上游'
            : '这个主题暂时没有可领的任务');
      }
    } catch (e) {
      _toast('领取失败：${NxKvController.humanize(e)}');
    }
  }

  Future<void> _create() async {
    final c = _controller!;
    final topic = c.selected;
    if (topic == null) return;
    _closeDrawer();
    final md = await openMdComposer(
      context,
      title: '新建任务 · ${topic.name}',
      hint: '第一行写标题（# 开头），下面写背景/验收/约束。',
      initialText: '# \n\n## 背景\n\n\n## 验收\n\n- [ ] \n\n## 约束\n\n- \n',
      submitLabel: '派发任务',
      templates: const ['背景', '验收', '约束'],
    );
    if (md == null || md.trim().isEmpty) return;
    try {
      final r = await c.add(md, topic.cwd);
      await c.refresh();
      if (!mounted) return;
      _open(r.id);
    } catch (e) {
      _toast('派发失败：${NxKvController.humanize(e)}');
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  // ── 低频页（契约 / 主题）────────────────────────────────────

  void _openContract() {
    final c = _controller!;
    _closeDrawer();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => _Sheet(
        title: '契约',
        child: NxKvContractView(controller: c),
      ),
    ));
  }

  void _openTopics() {
    final c = _controller!;
    _closeDrawer();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (ctx) => _Sheet(
        title: '主题',
        child: NxKvTopicsView(
          controller: c,
          onOpen: (key) {
            c.select(key);
            _open(null);
            Navigator.of(ctx).pop();
          },
        ),
      ),
    ));
  }

  // ── UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    if (c == null) return const SizedBox.shrink();

    return Scaffold(
      key: _scaffold,
      drawer: NxKvDrawer(
        controller: c,
        currentId: _taskId,
        onPick: _open,
        onTopic: _switchTopic,
        onClaim: _claim,
        onCreate: _create,
        onOpenTopics: _openTopics,
        onOpenContract: _openContract,
      ),
      // 不要再留 `QuickNavBottomBar.bodyBottomReserve`：
      // 这一页是 push 出来的整页路由（`MaterialPageRoute`），全局底栏挂在
      // 主壳的 Stack 里、被这条路由整块盖住 —— 那 104dp（64+16+safe）是**纯空白**。
      // 证据：编辑页是 `fullscreenDialog`，它从没留过这块占位也没被底栏盖住。
      // 去掉它，正文多出整整 104dp，这才是「可视空间最大化」里最大的一笔。
      body: SafeArea(
        top: false,
        child: PopScope(
          // 任务开着时，系统返回先回队列，而不是直接退出这个 App 视图
          canPop: _taskId == null,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _open(null);
          },
          child: Column(
            children: [
              _contextBar(c),
              Expanded(
                child: _taskId == null
                    ? NxKvQueueView(controller: c, onOpen: _open)
                    : NxKvTaskView(
                        key: ValueKey(_taskId),
                        controller: c,
                        id: _taskId!,
                        topicKey: c.selectedKey,
                        onSwitch: _open,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 上下文条：36dp，替代原来 134dp 的 AppBar + TabBar + 连接条。
  ///
  /// 它只回答两个问题：**在哪**、**怎么换地方**。其余（契约、主题、筛选）
  /// 全在抽屉里 —— 那些一眼看不完的东西不该常驻在正文上方。
  Widget _contextBar(NxKvController c) {
    final cs = Theme.of(context).colorScheme;
    final taskMode = _taskId != null;
    return Container(
      height: 36,
      padding: const EdgeInsets.only(right: AppSpacing.xxs),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _scaffold.currentState?.openDrawer(),
            child: SizedBox(
              width: 40,
              height: 36,
              child: Icon(Icons.menu, size: 18, color: cs.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: c,
              builder: (_, _) {
                final t = c.selected;
                return Text(
                  taskMode
                      ? '任务 #$_taskId'
                      : '${t?.name ?? '（无主题）'}${t == null ? '' : ' · 待领 ${t.pending}/${t.total}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                );
              },
            ),
          ),
          // 任务开着时这颗是「回队列」，否则是「刷新」——同一个位置，两种用途
          IconButton(
            tooltip: taskMode ? '回到队列' : '刷新',
            iconSize: 16,
            visualDensity: VisualDensity.compact,
            icon: Icon(taskMode ? Icons.close : Icons.refresh, color: cs.outline),
            onPressed: taskMode ? () => _open(null) : c.bootstrap,
          ),
        ],
      ),
    );
  }
}

/// 低频页的外壳：带返回的整页，和主区共用同一个 controller。
class _Sheet extends StatelessWidget {
  const _Sheet({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title, style: const TextStyle(fontSize: 15))),
      body: child,
    );
  }
}
