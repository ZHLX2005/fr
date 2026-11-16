import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_boards.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_template.dart';
import 'package:xiaodouzi_fr/core/note/note_root_scope.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_motion.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_page.dart';

/// 整页冒烟：**这一页得真被渲染过一次**。
///
/// 第 1 轮的「主页面一直 loading」不是逻辑错，是这页从没在测试或真机上跑过：
/// 三个视图都没订阅 controller，谁来都发现不了。所以这里把首页、抽屉、
/// 抽屉→主区的切换各渲一遍，先保证不崩、字对得上。
///
/// 只验「画得出来 + 交互通到」，不验数据：网络入口全部悬空（见 [_StubController]）。
void main() {
  const target = MnWsAppTarget(
    pc: MnWsPcGroup(
      bridgeId: 'laptop-test',
      name: 'test-pc',
      userId: 'u1',
      connectedAt: '',
      apps: [],
    ),
    pcApp: MnWsPcApp(
      app: 'nx-kv',
      title: 'nx-kv',
      port: null,
      base: null,
      bridgeId: 'laptop-test',
      alive: true,
    ),
  );

  const topic = kv.LocaltaskListTopic(
    key: 'board/kv_fr',
    name: 'fr',
    cwd: 'D:/DevProjects/my/github/fr',
    summary: '现状一句话',
    waiting: false,
    pending: 1,
    claimed: 0,
    done: 1,
    total: 2,
    repo: kv.LocaltaskListTopicRepo(name: 'fr', key: 'github.com/zhlx2005/fr'),
  );

  /// 侧边栏第一层（组）的数据源：`GET /api/boards`。
  /// 没有它，树也要能用（全落在「未分组」下）——这里给上，才能验「组行画得出来」。
  const mobileBoard = NxKvBoard(
    id: 'b_mobile',
    key: 'group/mobile',
    name: 'mobile',
    repoKeys: ['github.com/zhlx2005/fr'],
  );

  /// 组任务（`localtask.boardtasks`）：mobile 组里的一条，物理落在 fr 的队列。
  const groupTask = kv.LocaltaskBoardTasksBoardTask(
    id: 18,
    status: 'pending',
    title: '第2轮 fr',
    round: 2,
    ready: true,
    project: 'fr',
    topicKey: 'board/kv_fr',
    createdAt: '2026-11-15T12:00:00Z',
    consumedAt: '',
    completedAt: '',
    claimedByName: '',
    roundSummary: '',
  );

  const mobileStats = kv.LocaltaskBoardTasksBoard(
    id: 'b_mobile',
    key: 'group/mobile',
    name: 'mobile',
    pending: 1,
    total: 1,
    tasks: [groupTask],
  );

  const task = kv.LocaltaskTasksTask(
    id: 14,
    status: 'pending',
    title: '修一下 fr nx-kv 的样式',
    round: 2,
    board: '',
    ready: true,
    reopenCount: 0,
    createdAt: '2026-11-14T13:00:00Z',
    consumedAt: '',
    completedAt: '',
    claimedByName: '',
    roundSummary: '',
  );

  _StubController ready() => _StubController()
    ..topics = const [topic]
    ..selectedKey = topic.key
    ..tasks = const [task]
    ..boards = const [mobileBoard]
    ..boardTasks = const [mobileStats]
    ..boardTasksKnown = true
    ..loading = false;

  testWidgets('首帧渲得出来：上下文条 + 队列行', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    expect(tester.takeException(), isNull);
    // 上下文条（36dp）说的就是「现在在哪」
    expect(find.text('fr · 待领 1/2'), findsOneWidget);
    expect(find.text('#14'), findsOneWidget);
    expect(find.text('修一下 fr nx-kv 的样式'), findsOneWidget);
  });

  testWidgets('抽屉打得开，搜索能过滤', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('搜组 / 项目 / 任务'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();

    // 搜不到时要说清「搜的是什么」，不能只留一片空
    expect(find.text('没有匹配「99」的任务'), findsOneWidget);
  });

  testWidgets('抽屉：一棵树（组行 + 项目行同层），组是叶子', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    // 与面板侧栏同一形态：没有「项目组 / 项目」两段标题，组行与项目行同一层平铺
    expect(find.text('项目组'), findsNothing);
    expect(find.text('项目'), findsNothing);
    expect(find.byIcon(Icons.workspaces_rounded), findsOneWidget, reason: '组行的图标底座');
    expect(find.byIcon(Icons.folder_rounded), findsWidgets, reason: '项目行');
    expect(find.text('mobile'), findsOneWidget);
    expect(find.text('fr'), findsWidgets, reason: '项目行平铺，与组行并列');
    expect(tester.takeException(), isNull);

    // 第 4 轮反馈第二条：不要「领任务的 btn」
    expect(find.textContaining('领一条'), findsNothing);

    // 组是叶子：组行尾不画展开箭头（那会暗示「点进去还有下一层」）。
    // 断言按「组行这一棵子树里有没有 NxKvChevron」来写 —— 主区的任务行也有箭头，
    // 按图标全局找会把它算进来。
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('mobile'), matching: find.byType(NxKvPress)).first,
        matching: find.byType(NxKvChevron),
      ),
      findsNothing,
    );
  });

  testWidgets('点组行 → 组队列（本组任务），不跳项目', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.text('mobile'));
    await tester.pumpAndSettle();

    // 上下文条说的是「我在这个组里」，且报的是**组任务**口径（不是成员队列之和）
    expect(find.text('mobile · 组任务 1/1'), findsOneWidget);
    // 组里列的是组任务本身，带归属项目 tag
    expect(find.text('第2轮 fr'), findsWidgets);
    expect(find.text('fr'), findsWidgets);

    // 组不是「装着项目的文件夹」：不再有返回行 / 「N 个项目」那种成员清单
    expect(find.text('返回'), findsNothing);
    expect(find.textContaining('1 个项目'), findsNothing);
    // 组行仍是叶子：选中它之后也不会长出箭头
    expect(
      find.descendant(
        of: find.ancestor(of: find.text('mobile'), matching: find.byType(NxKvPress)).first,
        matching: find.byType(NxKvChevron),
      ),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('组里也能直接打开一条组任务（带物理落点队列）', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('mobile'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('第2轮 fr').last);
    await tester.pumpAndSettle();

    // 主区切到正文态；topicKey 用的是组任务自己的落点（board/kv_fr），不是「当前选中项」
    expect(find.text('任务 #18'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('抽屉点一条 → 主区切到任务', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    // 抽屉里的任务行（正文那一行标题在抽屉与队列各出现一次，点抽屉里的那条）
    await tester.tap(find.text('修一下 fr nx-kv 的样式').last);
    await tester.pumpAndSettle();

    // 主区换成正文态：上下文条改口「任务 #14」，抽屉自动收起
    expect(find.text('任务 #14'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// 一个仓库挂两条队列：面板里「项目行 = 进目录，箭头 = 展开子内容」，
  /// 端侧照抄 —— 点行进队列、点箭头才展开。上一版是「多队列时点行只展开、
  /// 进不去」，那是第 3 轮反馈里「逻辑仍然不对」最扎眼的一处。
  const topic2 = kv.LocaltaskListTopic(
    key: 'board/kv_fr_docs',
    name: 'fr-docs',
    cwd: 'D:/DevProjects/my/github/fr/docs',
    summary: '',
    waiting: false,
    pending: 0,
    claimed: 0,
    done: 0,
    total: 0,
    repo: kv.LocaltaskListTopicRepo(name: 'fr', key: 'github.com/zhlx2005/fr'),
  );

  testWidgets('多队列项目：点行就进队列，箭头才展开队列', (tester) async {
    final c = _StubController()
      ..topics = const [topic, topic2]
      ..selectedKey = topic2.key
      ..tasks = const [task]
      ..loading = false;
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: c)),
    ));

    await tester.tap(find.byIcon(Icons.menu_rounded));
    await tester.pumpAndSettle();

    // 多队列才有箭头（面板的 chevron 只在有子内容时给）
    expect(find.byType(NxKvChevron), findsOneWidget);
    // 选中项所在的项目行自动展开，两条队列都在
    expect(find.text('fr-docs'), findsOneWidget);

    // 点「项目行」本身 → 进它的默认队列（第一条），不是展开/收起
    final row = find.ancestor(of: find.byIcon(Icons.folder_rounded), matching: find.byType(NxKvPress)).first;
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(c.selectedKey, topic.key, reason: '点行 = 进队列（默认第一条），与面板 openRow 一致');

    // 点箭头 → 收起；再点 → 展开（q 弹展开）。
    // 按语义标签找（箭头本身是 Transform 代理，按渲染盒点会报「没打中」的假警告）
    await tester.tap(find.bySemanticsLabel('收起队列'));
    await tester.pumpAndSettle();
    expect(find.text('fr-docs'), findsNothing, reason: '箭头负责展开/收起');

    await tester.tap(find.bySemanticsLabel('展开队列'));
    await tester.pumpAndSettle();
    expect(find.text('fr-docs'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  /// fr #22：「在侧边栏按钮旁边增加一个新建任务 icon」。
  ///
  /// 派活是这一页最高频的动作，不该「开抽屉 → 再点一次新建」。这两条锁住：
  /// ① 它在 ☰ **旁边**（同一排、右边），且点了真能到编辑页；
  /// ② 没选中任何队列时它不是死键，要说清该先做什么。
  group('上下文条 · 快速新建', () {
    Widget page(_StubController c) => ProviderScope(
          child: MaterialApp(
            home: NoteRootScope(
              noteRoot: NoteFactory.create(),
              child: NxKvPage(target: target, controller: c),
            ),
          ),
        );

    testWidgets('＋ 与 ☰ 同排相邻，点它直接进派活编辑页', (tester) async {
      await tester.pumpWidget(page(ready()));

      final menu = tester.getRect(find.byIcon(Icons.menu_rounded));
      final add = tester.getRect(find.byIcon(Icons.add_rounded));
      expect(add.left, greaterThanOrEqualTo(menu.right),
          reason: '要挨在侧边栏按钮右边，不是收进抽屉里');
      expect(add.center.dy, closeTo(menu.center.dy, 0.5), reason: '同一排');

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 落点就是上下文里那个队列（标题里带名字，人才知道派到哪去了）
      expect(find.text('新建任务 · fr'), findsOneWidget);
      expect(find.text('派发任务'), findsOneWidget);

      // fr #23：正文骨架来自服务端模板；桩不可达 → 面板同款兜底，且标题行在前
      // （服务端拿首个 `# ` 行当任务标题，没有这一行标题就会变成「本轮问题」）
      final box = tester.widget<TextField>(find.byType(TextField)).controller!;
      expect(box.text, '# \n\n$nxKvNewTaskFallbackBody');
      expect(box.selection.baseOffset, 2, reason: '光标落在标题行，不是模板末尾');
    });

    testWidgets('没选队列时点 ＋ 说清该先做什么', (tester) async {
      final c = ready()
        ..topics = const []
        ..selectedKey = null;
      await tester.pumpWidget(page(c));

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump();

      expect(find.text('先在侧边栏选一个组或项目队列，再新建任务'), findsOneWidget);
      expect(find.text('派发任务'), findsNothing, reason: '没落点就不该打开编辑页');
    });
  });

  /// 真机状态栏高度不是 0 —— 上面三条用的是测试默认环境（padding=0），
  /// 所以它们证明不了「36dp 的上下文条会不会被状态栏吞掉」。
  ///
  /// 第 3 轮反馈「侧边栏无法显示，太上面了」就是这一层：`SafeArea(top: false)`
  /// 让上下文条贴着屏幕最顶，36dp 全落在状态栏区间里。状态栏不接收触摸，
  /// ☰ 那一下根本到不了 InkWell。这条用例把状态栏设成 44dp 复现硬件环境。
  group('真机安全区（状态栏 44dp / 手势条 34dp）', () {
    void fakeSafeArea(WidgetTester tester) {
      tester.view.physicalSize = const Size(1179, 2556);
      tester.view.devicePixelRatio = 3.0;
      tester.view.padding = const FakeViewPadding(top: 132, bottom: 102);
      addTearDown(tester.view.reset);
    }

    testWidgets('☰ 落在状态栏下沿之下，点得开', (tester) async {
      fakeSafeArea(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
      ));

      // 语境：MediaQuery 认到的状态栏确实是 44dp
      expect(MediaQuery.of(tester.element(find.byType(NxKvPage))).padding.top, 44);

      final menu = tester.getRect(find.byIcon(Icons.menu_rounded));
      expect(menu.top, greaterThanOrEqualTo(44),
          reason: '☰ 压在状态栏里就点不到 —— 侧边栏等于打不开');
      // 整条上下文条也应在状态栏之下（36dp 高，落在 44 ~ 80）
      expect(menu.bottom, lessThanOrEqualTo(80));

      // 真的能点开（touch 走 UI 树，不只是几何位置对）
      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();
      expect(find.text('搜组 / 项目 / 任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('抽屉自己的内容也从状态栏下沿开始', (tester) async {
      fakeSafeArea(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
      ));

      await tester.tap(find.byIcon(Icons.menu_rounded));
      await tester.pumpAndSettle();

      // 抽屉顶部的「nx-kv + 机器名」不能被挖孔/状态栏盖住
      final head = tester.getRect(find.text('nx-kv'));
      expect(head.top, greaterThanOrEqualTo(44));
      expect(tester.takeException(), isNull);
    });
  });
}

/// 网络入口全部悬空：这一层只测渲染与交互，不该为跑一个用例去连桥。
class _StubController extends NxKvController {
  _StubController()
      : super(
          target: const MnWsAppTarget(
            pc: MnWsPcGroup(
              bridgeId: 'laptop-test',
              name: 'test-pc',
              userId: 'u1',
              connectedAt: '',
              apps: [],
            ),
            pcApp: MnWsPcApp(
              app: 'nx-kv',
              title: 'nx-kv',
              port: null,
              base: null,
              bridgeId: 'laptop-test',
              alive: true,
            ),
          ),
          endpoint: MnWsEndpoint(
            baseUrl: 'http://127.0.0.1:9',
            grantReader: () async => null,
          ),
        );

  @override
  Future<void> refresh() async {}

  @override
  Future<void> checkContract() async {}

  @override
  Future<void> loadTasks({String? status}) async {}

  /// 正文视图像「点了但拉不到」：这里就让它拉不到，看它会不会挂住整个页面。
  @override
  Future<kv.LocaltaskGetOutput> task(int id, String? key) async =>
      throw const MnWsException(MnWsErrorKind.unreachable, '测试桩：不连桥');
}
