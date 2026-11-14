import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/mnws_app_views.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_controller.dart';
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
      active: true,
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
  );

  const task = kv.LocaltaskTasksTask(
    id: 14,
    status: 'pending',
    title: '修一下 fr nx-kv 的样式',
    round: 2,
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
    expect(find.text('搜任务：标题或编号'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '99');
    await tester.pump();

    // 搜不到时要说清「搜的是什么」，不能只留一片空
    expect(find.text('没有匹配「99」的任务'), findsOneWidget);
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
              active: true,
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
