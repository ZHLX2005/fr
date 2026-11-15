import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/mnws.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_controller.dart';
import 'package:xiaodouzi_fr/core/note/note_root_scope.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxkv/nxkv_page.dart';

/// 任务详情页冒烟：**这一页得真的渲染过一次正文**。
///
/// 之前的桩让 `task()` 永远抛错，详情页只验过「拉不到不崩」。这一轮正文区
/// 大改（段落可点、附件卡片化、轮次时间线），得有一条**带真数据的**用例：
/// 正文用应用的笔记渲染器画（`NoteRootScope` 里的 `NoteFactory`），附件经桥
/// 取字节 —— 桩的 endpoint 指向 127.0.0.1:9，必然失败，正好验「取不回来」
/// 的降级路径。
const text = '''
## 背景

侧边栏的逻辑仍然不对，参考当前的 nx-kv 的侧边栏。另外优化一下 uiux，从视觉和
icon 标识上优化，用一些更加圆滑的 icon 提升质感。

## 验收

- [ ] 组行不再画展开箭头
- [ ] 徽标口径与面板 `.cnt` 一致

> [!NOTE] 第 1 轮 · 完成总结
> 侧栏改成组 + 项目平铺，去掉了两段标题。
> 徽标改成有活才画。

> [!WARNING] 第 2 轮 · 验收反馈
> 当前和 nx-kv web 侧的语义完全不同。项目组就是项目组，新建可以选择项目组下的
> 绑定仓库，项目就是项目，项目组的不要跳到项目去。
''';

const attachments = <kv.LocaltaskGetAttachment>[
  kv.LocaltaskGetAttachment(
    id: 'a2',
    kind: 'file',
    kindLabel: '文档',
    name: '验收反馈-第2轮.md',
    sizeText: '2.1 KB',
    isImage: false,
    note: '验收原文',
    localPath: r'D:\DevProjects\my\github\fr\docs\fb2.md',
  ),
];

kv.LocaltaskGetOutput detail() => kv.LocaltaskGetOutput(
      id: 19,
      text: text,
      status: 'claimed',
      round: 3,
      roundSummary: '',
      reopenCount: 2,
      childCount: 0,
      childRoundCount: 0,
      createdAt: '2026-11-15T13:20:00Z',
      consumedAt: '2026-11-15T13:21:00Z',
      pickupSec: 42,
      completedAt: '',
      doneAt: '',
      feedback: '',
      claimedBy: 'agent-laptop',
      claimedByName: 'agent-laptop',
      claimedFrom: 'local',
      ready: false,
      blocksFollowing: false,
      blockBy: const [],
      deletedAt: '',
      archivedAt: '',
      archivedReason: '',
      attachments: attachments,
    );

void main() {
  const topic = kv.LocaltaskListTopic(
    key: 'board/kv_fr',
    name: 'fr',
    cwd: 'D:/DevProjects/my/github/fr',
    summary: '现状一句话',
    waiting: false,
    pending: 1,
    claimed: 0,
    done: 3,
    total: 4,
    repo: kv.LocaltaskListTopicRepo(name: 'fr', key: 'github.com/zhlx2005/fr'),
  );

  const task = kv.LocaltaskTasksTask(
    id: 19,
    status: 'pending',
    title: '侧边栏逻辑收尾 + 圆润质感与 iOS 式 q 弹动效',
    round: 3,
    board: 'kv_fr',
    ready: true,
    reopenCount: 2,
    createdAt: '2026-11-15T13:20:00Z',
    consumedAt: '2026-11-15T13:21:00Z',
    completedAt: '',
    claimedByName: 'agent-laptop',
    roundSummary: '',
  );

  Future<NxKvController> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1179, 2556);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(top: 132, bottom: 102);
    addTearDown(tester.view.reset);

    final c = _Stub()
      ..topics = const [topic]
      ..selectedKey = topic.key
      ..tasks = const [task]
      ..loading = false;

    await tester.pumpWidget(
      MaterialApp(
        home: NoteRootScope(
          noteRoot: NoteFactory.create(),
          child: NxKvPage(target: c.target, controller: c),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('侧边栏逻辑收尾 + 圆润质感与 iOS 式 q 弹动效'));
    await tester.pumpAndSettle();
    return c;
  }

  testWidgets('任务页渲得出来：编号块 + 状态胶囊 + 胶囊动作条', (tester) async {
    await boot(tester);

    // 头部三件套
    expect(find.text('#19'), findsOneWidget);
    expect(find.text('进行中'), findsOneWidget);
    expect(find.textContaining('重开 2 次'), findsOneWidget);

    // 动作条：两颗胶囊 + 一颗圆形刷新
    expect(find.text('标完成'), findsOneWidget);
    expect(find.text('反馈'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    // 正文真的画出来了（不是错误态）
    expect(find.textContaining('侧边栏的逻辑仍然不对'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('meta 展开：领取时间与领取方出现', (tester) async {
    await boot(tester);

    expect(find.text('领取'), findsNothing);
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();

    expect(find.text('领取'), findsOneWidget);
    expect(find.textContaining('agent-laptop'), findsWidgets);
    // 箭头状态跟着变了
    await tester.tap(find.byIcon(Icons.expand_more_rounded));
    await tester.pumpAndSettle();
    expect(find.text('领取'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('轮次时间线：新旧两轮都在，反馈轮的标签是胶囊文案', (tester) async {
    await boot(tester);

    // 轮次在列表尾部，拖到可见
    await tester.scrollUntilVisible(
      find.textContaining('第 2 轮 · 验收反馈'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('第 1 轮 · 完成总结'), findsOneWidget);
    expect(find.textContaining('第 2 轮 · 验收反馈'), findsOneWidget);
    // 轮次正文（callout 的行）
    expect(find.textContaining('项目组的不要跳到项目去'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('附件卡：卡片化渲染 + PC 路径透出 + 取不到字节时不连累整页', (tester) async {
    await boot(tester);

    await tester.scrollUntilVisible(
      find.text('验收反馈-第2轮.md'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('验收反馈-第2轮.md'), findsOneWidget);
    expect(find.textContaining(r'PC 上：'), findsOneWidget);
    // 桩的 endpoint 打不通 —— 这条附件自己降级，不抛错
    expect(tester.takeException(), isNull);
  });

  testWidgets('点正文一段 → 引用面板出现，可以复制原文', (tester) async {
    await boot(tester);

    await tester.tap(find.textContaining('侧边栏的逻辑仍然不对').first);
    await tester.pumpAndSettle();

    // 面板：引文 + 两个动作
    expect(find.text('评价这一段'), findsOneWidget);
    expect(find.text('复制原文'), findsOneWidget);

    await tester.tap(find.text('复制原文'));
    await tester.pumpAndSettle();
    expect(find.text('评价这一段'), findsNothing, reason: '复制后面板关掉');
    expect(tester.takeException(), isNull);
  });
}

/// 网络入口全部悬空：只测渲染与交互，不为跑用例连桥。
class _Stub extends NxKvController {
  _Stub()
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
          endpoint: MnWsEndpoint(baseUrl: 'http://127.0.0.1:9', grantReader: () async => null),
        );

  @override
  Future<void> refresh() async {}

  @override
  Future<void> checkContract() async {}

  @override
  Future<void> loadTasks({String? status}) async {}

  @override
  Future<kv.LocaltaskGetOutput> task(int id, String? key) async => detail();
}
