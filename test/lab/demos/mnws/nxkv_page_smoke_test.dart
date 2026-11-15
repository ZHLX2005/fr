import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_boards.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';
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

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('搜组 / 项目 / 任务'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();

    // 搜不到时要说清「搜的是什么」，不能只留一片空
    expect(find.text('没有匹配「99」的任务'), findsOneWidget);
  });

  testWidgets('抽屉：组是入口（叶子），项目平铺', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // 两段标题说清「上面是组、下面是项目」；组行不铺成员（nx-kv 的现行逻辑）
    expect(find.text('项目组'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(find.text('mobile'), findsOneWidget);
    expect(find.text('fr'), findsWidgets, reason: '项目行平铺，与组行并列');
    expect(tester.takeException(), isNull);

    // 第 4 轮反馈第二条：不要「领任务的 btn」
    expect(find.textContaining('领一条'), findsNothing);
  });

  testWidgets('点组行 → 组队列（本组任务），不跳项目', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu));
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
    // 两个分段标题还在 —— 组行与项目行是并列的两段
    expect(find.text('项目组'), findsOneWidget);
    expect(find.text('项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('组里也能直接打开一条组任务（带物理落点队列）', (tester) async {
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
    ));

    await tester.tap(find.byIcon(Icons.menu));
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

    await tester.tap(find.byIcon(Icons.menu));
    await tester.pumpAndSettle();

    // 抽屉里的任务行（正文那一行标题在抽屉与队列各出现一次，点抽屉里的那条）
    await tester.tap(find.text('修一下 fr nx-kv 的样式').last);
    await tester.pumpAndSettle();

    // 主区换成正文态：上下文条改口「任务 #14」，抽屉自动收起
    expect(find.text('任务 #14'), findsOneWidget);
    expect(tester.takeException(), isNull);
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

      final menu = tester.getRect(find.byIcon(Icons.menu));
      expect(menu.top, greaterThanOrEqualTo(44),
          reason: '☰ 压在状态栏里就点不到 —— 侧边栏等于打不开');
      // 整条上下文条也应在状态栏之下（36dp 高，落在 44 ~ 80）
      expect(menu.bottom, lessThanOrEqualTo(80));

      // 真的能点开（touch 走 UI 树，不只是几何位置对）
      await tester.tap(find.byIcon(Icons.menu));
      await tester.pumpAndSettle();
      expect(find.text('搜组 / 项目 / 任务'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('抽屉自己的内容也从状态栏下沿开始', (tester) async {
      fakeSafeArea(tester);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: NxKvPage(target: target, controller: ready())),
      ));

      await tester.tap(find.byIcon(Icons.menu));
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
