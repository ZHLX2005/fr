import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;

import '../../../../api/mnws/mnws.dart';
import '../../../../core/note/composer/md_composer.dart';
import '../../../../design_tokens/spacing.dart';
import 'nxkv_contract_view.dart';
import '../../../../api/mnws/nxkv/nxkv_controller.dart';
import '../../../../api/mnws/nxkv/nxkv_tree.dart';
import 'nxkv_drawer.dart';
import 'nxkv_image_pick.dart';
import 'nxkv_motion.dart';
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
/// ## 第 6 轮的落点（组是组、项目是项目）
///
/// 反馈：「当前和 nx-kv web 侧的语义完全不同 / 项目组就是项目组 / 新建可以选择
/// 项目组下的绑定仓库 / 项目就是项目 / 项目组的不要跳到项目去」。
///
/// 于是组和项目成了**两条并列的队列**（面板的 `#/group/<id>` 与 `#/dir/<key>`）：
///   · 点组 → 主区是**本组任务**（跨成员项目的队列），每条带归属项目 tag；
///   · 点项目 → 主区是本项目的**项目走向**任务（组任务剔除）；
///   · 组里「新建」先选落点（本组绑定的仓库），归属写 frontmatter；
///   · 组成员表只用于选落点，不再是导航。
///
/// ## 第 7 轮的落点（侧栏逻辑收尾 + UI/UX）
///
/// 反馈两条：「侧边栏的逻辑仍然不对，参考当前的 nx-kv 的侧边栏」+「优化一下
/// uiux，从视觉和 icon 标识上优化，用一些更加圆滑的 icon 提升质感，同时希望
/// 动效足够 ios，足够 q 弹，比如使用贝塞尔曲线之类的方式」。
///
///   · 逻辑：徽标与「谁是叶子」收进 `NxKvSideRow`（`badgeText` / `hasChevron`，
///     面板 `.cnt` 同口径）；抽屉从「两段标题」改回面板的**一棵树**；
///     项目行点一下就是进队列，箭头只管展开多队列（上一版多队列时点行进不去）；
///   · 手感：`nxkv_motion.dart` —— 圆润 icon（`*_rounded`）+ 图标底座 +
///     按压回弹（[NxKvPress]）+ 过冲曲线（[NxKvMotion.snap]，easeOutBack 的
///     贝塞尔常数，测试里采样钉住「确实过冲」）。
///
/// 规则全在 `nxkv_tree.dart`（纯函数，可单测），数据全在 `NxKvController`。
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

  /// 那条任务物理落在哪条队列（组任务跨成员队列，不能拿当前选中项顶替）。
  String? _taskTopicKey;

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

  void _open(int? id, {String? topicKey}) {
    setState(() {
      _taskId = id;
      _taskTopicKey = id == null ? null : (topicKey ?? _controller!.selectedKey);
    });
    _closeDrawer();
  }

  /// 换项目队列：主区回到该队列，抽屉留着（人还要在里面挑活）。
  void _switchTopic(String key) {
    _controller!.select(key);
    setState(() {
      _taskId = null;
      _taskTopicKey = null;
    });
  }

  /// 换组队列：组有自己的任务，**不跳到成员项目去**（面板 `#/group/<id>` 同款）。
  void _switchBoard(String boardKey) {
    _controller!.selectBoard(boardKey);
    setState(() {
      _taskId = null;
      _taskTopicKey = null;
    });
  }

  void _closeDrawer() {
    final s = _scaffold.currentState;
    if (s != null && s.isDrawerOpen) s.closeDrawer();
  }

  // ── 动作（抽屉里点的那个）──────────────────────────────────

  /// 派一条任务：项目里直接落进本项目队列；组里先**选落点项目**再派。
  ///
  /// 反馈原话「新建可以选择项目组下的绑定仓库」说的就是组这一路：组任务要落到
  /// 某个成员仓库的队列（agent 按目录领活），归属（frontmatter 的 board）才写本组。
  /// 选择器只列**本组绑定且本机真有队列**的仓库 —— 选一个没队列的等于派不出去。
  Future<void> _create() async {
    final c = _controller!;
    final board = c.selectedGroup;
    final topic = c.selected;
    // 上下文条上的 ＋ 常驻可见，没选中任何队列时不能静默无反应（那是死键）
    if (board == null && topic == null) {
      _toast('先在侧边栏选一个组或项目队列，再新建任务');
      return;
    }
    _closeDrawer();

    // 组里派活：先选落点（成员仓库 → 它的队列），归属写本组
    NxKvSideRow? member;
    kv.LocaltaskListTopic? landing;
    var composerTitle = '新建任务 · ${topic?.name ?? ''}';
    if (board != null) {
      final members = c.sideList().membersOf(board);
      if (members.isEmpty) {
        _toast('这个组在本机没有可落点的项目队列 —— 成员项目要先在 PC 上登记并建队列');
        return;
      }
      member = await _pickMember(board, members);
      if (member == null) return;
      landing = member.queues.isEmpty ? null : member.queues.first;
      if (landing == null) {
        _toast('「${member.label}」在本机还没有任务队列');
        return;
      }
      composerTitle = '新建任务 · ${board.label} → ${member.label}';
    } else {
      landing = topic;
    }
    if (landing == null) return;
    // 选完落点是异步的（弹窗）：页面可能已经关了，别拿着旧 context 开编辑页
    if (!mounted) return;

    final md = await openMdComposer(
      context,
      title: composerTitle,
      hint: '第一行写标题（# 开头），下面写背景/验收/约束。',
      initialText: '# \n\n## 背景\n\n\n## 验收\n\n- [ ] \n\n## 约束\n\n- \n',
      submitLabel: '派发任务',
      templates: const ['背景', '验收', '约束'],
      pickImage: () => pickAndUploadImage(c, context),
      imageResolver: c.attachmentBytes,
    );
    if (md == null || md.trim().isEmpty) return;
    final target = landing;
    final picked = member;
    try {
      final r = (board != null && picked != null)
          ? await c.addToBoard(
              md,
              boardId: board.groupId.isEmpty ? board.groupKey : board.groupId,
              projectKey: picked.repoKey.isNotEmpty ? picked.repoKey : picked.label,
            )
          : await c.add(md, target.cwd);
      await c.refresh();
      if (!mounted) return;
      // 组任务跨成员队列：物理落点从刷新后的组任务里找回来（找不到就用刚才选的队列）
      var key = target.key;
      if (board != null) {
        for (final b in c.boardTasks) {
          for (final t in b.tasks) {
            if (t.id == r.id) key = t.topicKey;
          }
        }
      }
      _open(r.id, topicKey: key);
    } catch (e) {
      _toast('派发失败：${NxKvController.humanize(e)}');
    }
  }

  /// 选落点项目（组任务的「归属项目」）：只列本组绑定、且本机真有队列的仓库。
  Future<NxKvSideRow?> _pickMember(NxKvSideRow board, List<NxKvSideRow> members) {
    final cs = Theme.of(context).colorScheme;
    return showDialog<NxKvSideRow>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('派到「${board.label}」下的哪个项目？', style: const TextStyle(fontSize: 15)),
        contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final m in members)
                ListTile(
                  dense: true,
                  title: Text(m.label, style: const TextStyle(fontSize: 13)),
                  subtitle: Text(
                    m.hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10, color: cs.outline),
                  ),
                  onTap: () => Navigator.of(ctx).pop(m),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('取消')),
        ],
      ),
    );
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
        onPick: (id, topicKey) => _open(id, topicKey: topicKey),
        onTopic: _switchTopic,
        onBoard: _switchBoard,
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
                // 队列 ⇄ 任务：淡入 + 极轻微右移。没有这一层时，点开一条任务是
                // 整屏「啪」一下换掉 —— 内容全变、位置全变，眼睛要重新找落点。
                // 位移只给 3%（240ms 走完），是「推入」的暗示而不是真的滑动：
                // 真滑一整屏会让中间的列表跟着抖，反而慢。
                child: AnimatedSwitcher(
                  duration: NxKvMotion.base,
                  switchInCurve: NxKvMotion.glide,
                  switchOutCurve: NxKvMotion.soft,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.03, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _taskId == null
                      ? NxKvQueueView(
                          key: const ValueKey('queue'),
                          controller: c,
                          onOpen: (id, topicKey) => _open(id, topicKey: topicKey),
                        )
                      : NxKvTaskView(
                          key: ValueKey('task-$_taskId'),
                          controller: c,
                          id: _taskId!,
                          // 组任务跨成员队列：用打开时记下的落点，不用「当前选中项」
                          topicKey: _taskTopicKey,
                          onSwitch: (id) => _open(id, topicKey: _taskTopicKey),
                        ),
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
            icon: Icon(Icons.menu_rounded, color: cs.onSurfaceVariant),
            onPressed: () => _scaffold.currentState?.openDrawer(),
          ),
          // 快速新建（fr #22）：「派一条活」是这一页最高频的动作，不该先开抽屉、
          // 再点一次「新建」。放在 ☰ 旁边紧邻，是因为两者是同一组「换个地方 / 添一条」
          // 的入口；用 primary 上色把它和导航用的 ☰ 区分开（同排第三颗是刷新/返回，
          // 灰的）。落点即当前选中的组或项目队列 —— 与抽屉里那颗按钮同一条流程。
          IconButton(
            tooltip: '新建任务',
            iconSize: 18,
            padding: EdgeInsets.zero,
            visualDensity: VisualDensity.compact,
            constraints: const BoxConstraints.tightFor(width: 40, height: 36),
            icon: Icon(Icons.add_rounded, color: cs.primary),
            onPressed: _create,
          ),
          Expanded(
            child: AnimatedBuilder(
              animation: c,
              builder: (_, _) {
                // 「在哪」有三态：一条任务 / 一个组 / 一个项目队列
                final g = c.selectedGroup;
                final t = c.selected;
                final where = taskMode
                    ? '任务 #$_taskId'
                    : g != null
                        ? '${g.label} · 组任务 ${g.statsKnown ? '${g.pending}/${g.total}' : '数暂时没有'}'
                        : '${t?.name ?? '（无主题）'}${t == null ? '' : ' · 待领 ${t.pending}/${t.total}'}';
                // 换队列时这句话要「滑进来」而不是硬换：36dp 的条上，硬换会像闪屏
                return AnimatedSwitcher(
                  duration: NxKvMotion.base,
                  switchInCurve: NxKvMotion.glide,
                  switchOutCurve: NxKvMotion.soft,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(begin: const Offset(0.06, 0), end: Offset.zero).animate(anim),
                      child: child,
                    ),
                  ),
                  child: Text(
                    where,
                    key: ValueKey<String>(where),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
          ),
          // 任务开着时这颗是「回队列」，否则是「刷新」——同一个位置，两种用途
          IconButton(
            tooltip: taskMode ? '回到队列' : '刷新',
            iconSize: 17,
            visualDensity: VisualDensity.compact,
            icon: Icon(taskMode ? Icons.close_rounded : Icons.refresh_rounded, color: cs.outline),
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
