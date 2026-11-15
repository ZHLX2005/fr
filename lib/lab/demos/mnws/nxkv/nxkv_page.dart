import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../api/mnws/mnws.dart';
import '../../../../core/note/composer/md_composer.dart';
import '../../../../design_tokens/spacing.dart';
import 'nxkv_contract_view.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
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
/// ## 第 4 轮的落点（样式优化）
///
/// 反馈三条，各自落在哪一层：
///
///   1. 「项目和项目组不要以侧边栏的滚动 tab 表示，应该用目录树」——
///      [NxKvDrawer] 里的横向 chips 换成 `NxKvController.sideList()` 画的行清单
///      （见 `api/mnws/nxkv/nxkv_tree.dart`）；
///   2. 「任务只标记完成，不要领任务的 btn」—— 抽屉里的「领一条」与正文页的
///      「领取」都删了，动作条只留「标完成」；
///   3. 「附件也应该通过网络传输到手机端展示」—— 见 [NxKvTaskView] 的附件区：
///      图片经桥取字节内联画出来，其它文件落盘后交给系统打开。
///
/// ## 第 5 轮的落点（侧边栏逻辑对齐 nx-kv）
///
/// 反馈：「侧边栏的逻辑仍然不对，参考当前的 nx-kv 的侧边栏」。第 4 轮那版是
/// 组 → 项目 → 主题的三级树，而 nx-kv 面板在 11-03 就把语义改成了
/// **组是入口（叶子）、项目是模块（平铺）**：组不装项目、项目不因为被组链接而
/// 消失、顺序按名字不按待领数。抽屉已按这份逻辑重写，规则全在
/// `nxkv_tree.dart`（纯函数，可单测）。
///
/// ## 为什么第一屏是队列而不是任务
///
/// 手机上打开这个页面的人，八成是「想知道现在有什么活」。所以没有「当前任务」
/// 时它就是一个队列；点一条才进正文 —— 抽屉负责在两者之间横跳。
class NxKvPage extends ConsumerStatefulWidget {
  const NxKvPage({super.key, required this.target, this.controller});

  final MnWsAppTarget target;

  /// 从外面塞一个 controller 进来（**测试用的口子**）。
  ///
  /// 平时是 null，页面自己按 [target] 建一个。留这个口子的理由很实在：
  /// 第 1 轮的「主页面一直 loading」是**整页从没被渲染过一次**就发出去了
  /// （作者当时跑不起 flutter test，也没有真机）。有了它，
  /// `test/lab/demos/mnws/nxkv_page_smoke_test.dart` 才能把首页 + 抽屉
  /// 整页渲一遍 —— 订阅漏了、首帧崩了、布局溢出了，都是这一步能抓住的。
  final NxKvController? controller;

  @override
  ConsumerState<NxKvPage> createState() => _NxKvPageState();
}

class _NxKvPageState extends ConsumerState<NxKvPage> {
  final _scaffold = GlobalKey<ScaffoldState>();
  NxKvController? _controller;

  /// 这个 controller 是不是本页自己建的（只 dispose 自己建的那个）。
  bool _ownsController = false;

  /// 主区正在看哪条任务；null = 停在队列。
  int? _taskId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 端点要从 riverpod 拿，所以不能在 initState 里建
    if (_controller != null) return;
    final injected = widget.controller;
    if (injected != null) {
      _controller = injected;
      return;
    }
    final c = NxKvController(
      target: widget.target,
      endpoint: ref.read(mnWsEndpointProvider),
    );
    _controller = c;
    _ownsController = true;
    c.bootstrap();
  }

  @override
  void dispose() {
    if (_ownsController) _controller?.dispose();
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

  // ── 动作（抽屉里点的那个）──────────────────────────────────

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
      // 左缘右滑也能拉出侧边栏。默认只有 20dp，贴着屏幕边缘那一条在手势导航的
      // 返回手势区里，经常滑不动 —— 多给一点宽度，菜单按钮之外多一条路。
      drawerEdgeDragWidth: 48,
      drawer: NxKvDrawer(
        controller: c,
        currentId: _taskId,
        onPick: _open,
        onTopic: _switchTopic,
        onCreate: _create,
        onOpenTopics: _openTopics,
        onOpenContract: _openContract,
      ),
      // 不要再留 `QuickNavBottomBar.bodyBottomReserve`：
      // 这一页是 push 出来的整页路由（`MaterialPageRoute`），全局底栏挂在
      // 主壳的 Stack 里、被这条路由整块盖住 —— 那 104dp（64+16+safe）是**纯空白**。
      // 证据：编辑页是 `fullscreenDialog`，它从没留过这块占位也没被底栏盖住。
      // 去掉它，正文多出整整 104dp，这才是「可视空间最大化」里最大的一笔。
      //
      // **但顶部安全区不能省**（第 3 轮反馈「侧边栏无法显示，太上面了」）：
      // 这里写过 `top: false`，理由是「push 出来的路由顶上没有主壳 chrome」。
      // 主壳确实没有，但**状态栏有**：36dp 的上下文条紧贴屏幕最顶，
      // 而状态栏一般 24~48dp（挖孔机更高）——整条上下文条连同 ☰ 都压在状态栏底下。
      // 系统状态栏区域不接收触摸，所以那一下点击根本到不了 InkWell：
      // 用户看到的就是「侧边栏打不开」，位置也就是「太上面」。
      // 边界拖拽也救不了 —— 拖拽区从 y=0 起算，同样在状态栏里。
      body: SafeArea(
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
          // 侧边栏唯一的显式入口。44×36 —— 纵向受条高限制，横向给足；
          // 原来 40 宽的裸 InkWell 没有 tooltip、没有语义标签，读屏也读不出它是啥。
          IconButton(
            tooltip: '打开侧边栏',
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 44, height: 36),
            icon: Icon(Icons.menu, color: cs.onSurfaceVariant),
            onPressed: () => _scaffold.currentState?.openDrawer(),
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
