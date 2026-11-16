import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_boards.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_tree.dart';

/// 侧边栏行模型的**纯函数**用例。
///
/// 第 6 轮反馈：「当前和 nx-kv web 侧的语义完全不同 / 项目组就是项目组 /
/// 新建可以选择项目组下的绑定仓库 / 项目就是项目 / 项目组的不要跳到项目去」。
///
/// 于是这里钉的是**两条走向**（面板 `taskInBoard` / `projectPending` 同口径）：
///   · 组行 = 本组任务（frontmatter 的 board 归属）的计数，不是成员队列之和；
///   · 项目行 = 本项目队列里**剔除组任务**之后剩下的部分；
///   · 组成员表只用于「新建时选落点」，不是导航。
void main() {
  kv.LocaltaskListTopic topic({
    required String key,
    required String name,
    String cwd = '',
    String? repoKey,
    String? repoName,
    int pending = 0,
    int total = 0,
  }) =>
      kv.LocaltaskListTopic(
        key: key,
        name: name,
        cwd: cwd.isEmpty ? 'D:/w/$name' : cwd,
        summary: '',
        waiting: false,
        pending: pending,
        claimed: 0,
        done: 0,
        total: total,
        repo: repoKey == null
            ? null
            : kv.LocaltaskListTopicRepo(name: repoName ?? name, key: repoKey),
      );

  NxKvBoard board(String name, List<String> repos, {String desc = '', String id = ''}) =>
      NxKvBoard(
        id: id.isEmpty ? 'b_$name' : id,
        key: 'group/$name',
        name: name,
        desc: desc,
        repoKeys: repos,
      );

  /// 组任务：物理落在 [topicKey] 的队列，归属 [boardKey] 那个组。
  kv.LocaltaskBoardTasksBoardTask groupTask({
    required int id,
    required String topicKey,
    String project = 'fr',
    String status = 'pending',
  }) =>
      kv.LocaltaskBoardTasksBoardTask(
        id: id,
        status: status,
        title: '#$id',
        round: 1,
        ready: status == 'pending',
        project: project,
        topicKey: topicKey,
        createdAt: '',
        consumedAt: '',
        completedAt: '',
        claimedByName: '',
        roundSummary: '',
      );

  kv.LocaltaskBoardTasksBoard stats(
    NxKvBoard b,
    List<kv.LocaltaskBoardTasksBoardTask> tasks,
  ) =>
      kv.LocaltaskBoardTasksBoard(
        id: b.id,
        key: b.key,
        name: b.name,
        pending: tasks.where((t) => t.status == 'pending').length,
        total: tasks.length,
        tasks: tasks,
      );

  group('NxKvBoard.parse', () {
    test('认 {ok,data:{boards}} 这种被代理服务的信封，带上看板 id', () {
      final boards = NxKvBoard.parse({
        'ok': true,
        'data': {
          'boards': [
            {
              'id': 'b_mobile',
              'name': 'mobile',
              'key': 'group/mobile',
              'desc': '移动端',
              'repos': [
                {'key': 'github.com/zhlx2005/fr', 'id': 'r1'},
                {'id': 'r-placeholder'}, // 本机没登记的占位成员：没有 key，跳过
              ],
            },
          ],
        },
      });
      expect(boards, hasLength(1));
      expect(boards.single.id, 'b_mobile', reason: '新建组任务写进 frontmatter 的就是它');
      expect(boards.single.name, 'mobile');
      expect(boards.single.key, 'group/mobile');
      expect(boards.single.desc, '移动端');
      expect(boards.single.repoKeys, ['github.com/zhlx2005/fr']);
    });

    test('裸数组 / 垃圾输入都不炸', () {
      expect(NxKvBoard.parse([{'name': 'nx', 'repos': []}]).single.name, 'nx');
      expect(NxKvBoard.parse(null), isEmpty);
      expect(NxKvBoard.parse({'nope': 1}), isEmpty);
      expect(NxKvBoard.parse('不是 JSON 结构'), isEmpty);
    });
  });

  group('buildSideList — 组是组（组任务口径）', () {
    test('组行报本组任务数，不是成员队列之和', () {
      final mobile = board('mobile', ['r/fr', 'r/rt']);
      final side = buildSideList(
        topics: [
          // 两个成员队列：fr 的 4 条里 1 条是组任务，mn-rt 的 2 条全是项目任务
          topic(key: 'k-fr', name: 'fr', repoKey: 'r/fr', pending: 4, total: 4),
          topic(key: 'k-rt', name: 'mn-rt', repoKey: 'r/rt', pending: 2, total: 2),
        ],
        boards: [mobile],
        boardTasks: [
          stats(mobile, [
            groupTask(id: 18, topicKey: 'k-fr'),
            groupTask(id: 16, topicKey: 'k-fr', status: 'done'),
          ]),
        ],
        boardTasksKnown: true,
      );

      final g = side.groups.single;
      expect(g.pending, 1, reason: '组行只数**指向本组**的待领任务');
      expect(g.total, 2);
      expect(g.statsKnown, isTrue);
      // 组行不是可直达的队列（点它是换到组队列，不是进某个项目）
      expect(g.topicKey, isNull);
      expect(g.expandable, isFalse);
      expect(g.memberCount, 2);
      expect(g.groupId, 'b_mobile');
    });

    test('两种走向：组任务从项目侧剔除（待领与总数都剔）', () {
      final mobile = board('mobile', ['r/fr']);
      final side = buildSideList(
        topics: [topic(key: 'k-fr', name: 'fr', repoKey: 'r/fr', pending: 3, total: 5)],
        boards: [mobile],
        boardTasks: [
          stats(mobile, [
            groupTask(id: 1, topicKey: 'k-fr'),
            groupTask(id: 2, topicKey: 'k-fr', status: 'done'),
          ]),
        ],
        boardTasksKnown: true,
      );

      final fr = side.repos.single;
      expect(fr.pending, 2, reason: '3 条待领里 1 条是组任务 → 项目侧 2 条');
      expect(fr.total, 3, reason: '5 条里 2 条是组任务 → 项目侧 3 条');
      expect(side.groups.single.pending, 1);
    });

    test('组任务落在别的队列：不影响本队列的项目计数（按 topicKey 归位）', () {
      final mobile = board('mobile', ['r/fr', 'r/rt']);
      final side = buildSideList(
        topics: [
          topic(key: 'k-fr', name: 'fr', repoKey: 'r/fr', pending: 2, total: 2),
          topic(key: 'k-rt', name: 'mn-rt', repoKey: 'r/rt', pending: 2, total: 2),
        ],
        boards: [mobile],
        boardTasks: [
          stats(mobile, [groupTask(id: 9, topicKey: 'k-rt', project: 'mn-rt')]),
        ],
        boardTasksKnown: true,
      );

      // 只有 mn-rt 的队列里那条是组任务
      expect(side.repos.firstWhere((r) => r.label == 'fr').pending, 2);
      expect(side.repos.firstWhere((r) => r.label == 'mn-rt').pending, 1);
    });

    test('一个仓库挂两个组：项目仍只一行，两个组各数各的组任务', () {
      final mobile = board('mobile', ['r/fr']);
      final kvfr = board('kv_fr', ['r/fr']);
      final side = buildSideList(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr', pending: 3, total: 3)],
        boards: [mobile, kvfr],
        boardTasks: [
          stats(mobile, [groupTask(id: 1, topicKey: 'k')]),
          stats(kvfr, [groupTask(id: 2, topicKey: 'k'), groupTask(id: 3, topicKey: 'k')]),
        ],
        boardTasksKnown: true,
      );

      expect(side.repos, hasLength(1), reason: '项目是模块，不是组里的文件');
      expect(side.groups.map((g) => g.label), ['mobile', 'kv_fr']);
      expect(side.groups.map((g) => g.pending), [1, 2]);
      // 项目侧把两个组的组任务都剔掉
      expect(side.repos.single.pending, 0);
      // 成员表仍然只用于「新建时选落点」
      expect(side.membersOf(side.groups.first).single.label, 'fr');
      expect(side.membersOf(side.groups.last).single.label, 'fr');
    });

    test('组任务数拿不到：不假装 0，标 statsKnown=false', () {
      final mobile = board('mobile', ['r/fr']);
      final side = buildSideList(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr', pending: 2, total: 2)],
        boards: [mobile],
      );
      final g = side.groups.single;
      expect(g.statsKnown, isFalse);
      expect(g.pending, 0, reason: '没数就是 0，但界面靠 statsKnown 区分「没数」与「没有活」');
      // 项目侧也拿不到组任务可减：此时按队列原样报（宁可多算，不能把项目任务抹掉）
      expect(side.repos.single.pending, 2);
    });

    test('服务端回了组任务但看板表里没有这个组：只按看板出行（不凭空造行）', () {
      final mobile = board('mobile', ['r/fr']);
      final ghost = const kv.LocaltaskBoardTasksBoard(
        id: 'b_ghost',
        key: 'group/ghost',
        name: 'ghost',
        pending: 5,
        total: 5,
        tasks: [],
      );
      final side = buildSideList(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr')],
        boards: [mobile],
        boardTasks: [ghost],
        boardTasksKnown: true,
      );
      expect(side.groups.map((g) => g.label), ['mobile']);
      expect(side.groups.single.statsKnown, isFalse, reason: '这个组没有统计行');
    });
  });

  group('buildSideList — 结构（项目平铺）', () {
    test('单队列项目可直接进；多队列项目展开、队列保持服务端顺序', () {
      final side = buildSideList(
        topics: [
          topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
          topic(key: 'k2', name: 'fr-docs', repoKey: 'r/fr', pending: 3),
          topic(key: 'k3', name: 'mn-rt', repoKey: 'r/rt'),
        ],
        boards: [board('mobile', ['r/fr', 'r/rt'])],
      );

      final fr = side.repos.firstWhere((r) => r.label == 'fr');
      expect(fr.expandable, isTrue);
      expect(fr.queues.map((t) => t.name), ['fr', 'fr-docs'], reason: '重排会让「点项目」每次去别处');
      expect(fr.topicKey, 'k1', reason: '默认入口是第一条队列');
      expect(fr.pending, 3);
      expect(side.hostOf('k2')?.label, 'fr');

      final rt = side.repos.firstWhere((r) => r.label == 'mn-rt');
      expect(rt.expandable, isFalse, reason: '单队列不该画展开箭头');
      expect(rt.topicKey, 'k3');
    });

    test('没登记仓库的队列自己成一行 —— 抽屉是唯一入口，不能丢', () {
      final side = buildSideList(
        topics: [
          topic(key: 'a', name: 'proj-alpha', cwd: 'C:/tmp/proj-alpha'),
          topic(key: 'b', name: 'fr', repoKey: 'r/fr'),
        ],
        boards: [board('mobile', ['r/fr'])],
      );

      // 按名字序：fr 在前，纯本机目录跟在后面
      expect(side.repos.map((r) => r.label), ['fr', 'proj-alpha']);
      final local = side.repos.last;
      expect(local.repoKey, isEmpty);
      expect(local.topicKey, 'a');
      expect(local.hint, 'C:/tmp/proj-alpha');
      // 它不属于任何组，也不该出现在「新建落点」候选里
      expect(side.membersOf(side.groups.single).map((r) => r.label), ['fr']);
    });

    test('顺序按名字，不按待领数抖', () {
      final topics = [
        topic(key: 'k1', name: 'zeta', repoKey: 'r/z'),
        topic(key: 'k2', name: 'alpha', repoKey: 'r/a', pending: 9),
      ];
      final side = buildSideList(topics: topics);
      expect(side.repos.map((r) => r.label), ['alpha', 'zeta']);

      // 待领数变了（alpha 的活被领走），行序不动
      final after = buildSideList(topics: [
        topic(key: 'k1', name: 'zeta', repoKey: 'r/z', pending: 5),
        topic(key: 'k2', name: 'alpha', repoKey: 'r/a'),
      ]);
      expect(after.repos.map((r) => r.label), ['alpha', 'zeta']);
    });

    test('组里没有本机队列的成员：组行照出，落点候选里没有它', () {
      final side = buildSideList(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr')],
        boards: [board('mobile', ['r/fr', 'r/not-on-this-pc'])],
      );
      final g = side.groups.single;
      expect(g.memberCount, 2, reason: '成员数按注册表算，不看本机有没有队列');
      expect(side.membersOf(g).map((r) => r.label), ['fr']);
    });

    test('没有看板数据也能用：项目照常平铺', () {
      final side = buildSideList(topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr')]);
      expect(side.groups, isEmpty);
      expect(side.repos.single.label, 'fr');
    });
  });

  group('buildSideList — 搜索', () {
    final topics = [
      topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
      topic(key: 'k2', name: 'mn-rt', repoKey: 'r/rt'),
    ];
    final boards = [board('mobile', ['r/fr', 'r/rt'], desc: '手机与平板这一侧')];

    test('命中项目只留那一行（成员命中，组也跟着留下）', () {
      final side = buildSideList(topics: topics, boards: boards, query: 'rt');
      expect(side.repos.map((r) => r.label), ['mn-rt']);
      expect(side.groups.map((g) => g.label), ['mobile'],
          reason: '组代表它的成员：成员命中，组就该在');
      expect(side.matched, 2);
    });

    test('命中组名 / 组介绍：组行留下，项目不跟着铺开', () {
      final byName = buildSideList(topics: topics, boards: boards, query: 'mobi');
      expect(byName.rows.map((r) => r.label), ['mobile']);

      final byDesc = buildSideList(topics: topics, boards: boards, query: '平板');
      expect(byDesc.rows.map((r) => r.label), ['mobile']);
    });

    test('搜不到就是空清单', () {
      final side = buildSideList(topics: topics, boards: boards, query: 'zzz');
      expect(side.rows, isEmpty);
      expect(side.matched, 0);
    });
  });

  group('行清单的查询口', () {
    final side = buildSideList(
      topics: [
        topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
        topic(key: 'k2', name: 'fr-docs', repoKey: 'r/fr'),
      ],
      boards: [board('mobile', ['r/fr'])],
    );

    test('hostOf 找到队列所属的项目行', () {
      expect(side.hostOf('k2')?.label, 'fr');
      expect(side.hostOf('不存在'), isNull);
      expect(side.hostOf(null), isNull);
    });

    test('groupByKey 按组键或看板 id 都能找到组行', () {
      expect(side.groupByKey('group/mobile')?.label, 'mobile');
      expect(side.groupByKey('b_mobile')?.label, 'mobile');
      expect(side.groupByKey('group/nope'), isNull);
      expect(side.groupByKey(null), isNull);
    });
  });

  // 第 3 轮反馈「侧边栏的逻辑仍然不对 / 参考当前的 nx-kv 的侧边栏」：
  // 徽标口径与「谁是叶子、谁能展开」是面板侧栏里最容易被看出来的两处语义，
  // 全部收在行模型上，界面不再自己判一遍（否则两个端迟早分叉）。
  group('行尾徽标与展开箭头（对齐面板 .cnt / 组是叶子）', () {
    test('组行徽标：有组任务待领报待领数，一条都没有报成员数', () {
      final mobile = board('mobile', ['r/fr', 'r/rt']);
      final withTasks = buildSideList(
        topics: [topic(key: 'k1', name: 'fr', repoKey: 'r/fr', pending: 3, total: 5)],
        boards: [mobile],
        boardTasks: [
          stats(mobile, [
            groupTask(id: 1, topicKey: 'k1'),
            groupTask(id: 2, topicKey: 'k1'),
          ]),
        ],
        boardTasksKnown: true,
      );
      final g1 = withTasks.groups.single;
      expect(g1.badgeText, '2', reason: '组任务待领 2 条：报活，不报成员数');
      expect(g1.badgeEmphasized, isTrue);
      expect(g1.badgeHint, contains('组任务待领 2/2'));

      // 组里一条待领的活都没有 → 报成员数（「这个组挂着几个仓库」才是有效信息）
      final empty = buildSideList(
        topics: [topic(key: 'k1', name: 'fr', repoKey: 'r/fr', pending: 0, total: 0)],
        boards: [mobile],
        boardTasks: [stats(mobile, const [])],
        boardTasksKnown: true,
      );
      final g2 = empty.groups.single;
      expect(g2.badgeText, '2', reason: '没活时报成员数（面板 row.pending > 0 ? pending : count）');
      expect(g2.badgeEmphasized, isFalse);
    });

    test('组任务数拿不到：画 —，不画 0', () {
      final side = buildSideList(
        topics: [topic(key: 'k1', name: 'fr', repoKey: 'r/fr')],
        boards: [board('mobile', ['r/fr'])],
        boardTasksKnown: false,
      );
      final g = side.groups.single;
      expect(g.badgeText, '—');
      expect(g.badgeEmphasized, isFalse, reason: '「没数」不该被强调成「有活」');
      expect(g.badgeHint, contains('暂时拿不到'));
    });

    test('项目行徽标：0 待领不画（面板只在 pending > 0 时给 cnt）', () {
      final side = buildSideList(
        topics: [
          topic(key: 'k1', name: 'fr', repoKey: 'r/fr', pending: 0, total: 7),
          topic(key: 'k2', name: 'mn-rt', repoKey: 'r/rt', pending: 3, total: 4),
        ],
      );
      final fr = side.repos.firstWhere((r) => r.label == 'fr');
      final rt = side.repos.firstWhere((r) => r.label == 'mn-rt');
      expect(fr.badgeText, isNull, reason: '0 条待领时报 0 只是噪音');
      expect(rt.badgeText, '3');
      expect(rt.badgeEmphasized, isTrue);
      expect(rt.badgeHint, contains('项目待领 3/4'));
    });

    test('箭头只给多队列项目：组是叶子，单队列项目点行就进去了', () {
      final side = buildSideList(
        topics: [
          topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
          topic(key: 'k2', name: 'fr-docs', repoKey: 'r/fr'),
          topic(key: 'k3', name: 'mn-rt', repoKey: 'r/rt'),
        ],
        boards: [board('mobile', ['r/fr', 'r/rt'])],
      );
      expect(side.groups.single.hasChevron, isFalse, reason: '组没有下一层，画箭头就是在暗示「还能钻进去」');
      expect(side.repos.firstWhere((r) => r.label == 'fr').hasChevron, isTrue);
      expect(side.repos.firstWhere((r) => r.label == 'mn-rt').hasChevron, isFalse);
    });
  });

  // ── 显示序（fr #20）──────────────────────────────────────────
  //
  // 反馈原话：「当前 task 排序反了，应该时间最新的在最上面；未完成优先级 >
  // 已领取 > 已完成」。队列真相是追加序（seq），直接画就是「刚发的活在
  // 最底下」。这组用例钉住两件事：**分桶**与**桶内倒序**。
  group('显示序：未完成 → 已领取 → 已结，桶内最新在前', () {
    List<int> orderOf(List<NxKvTestTask> ts) => sortTasksForDisplay(
          ts,
          (t) => (
            bucket: nxKvTaskBucket(t.status),
            stamp: nxKvTaskStamp(
              createdAt: t.createdAt,
              consumedAt: t.consumedAt,
              completedAt: t.completedAt,
            ),
            id: t.id,
          ),
        ).map((t) => t.id).toList();

    test('分桶：待领取全在已领取上面，已领取全在已完成上面', () {
      final got = orderOf([
        NxKvTestTask(id: 1, status: 'done', createdAt: '2026-11-16 10:00:00', completedAt: '2026-11-16 11:00:00'),
        NxKvTestTask(id: 2, status: 'claimed', createdAt: '2026-11-16 09:00:00', consumedAt: '2026-11-16 09:30:00'),
        NxKvTestTask(id: 3, status: 'pending', createdAt: '2026-11-16 08:00:00'),
      ]);
      expect(got, [3, 2, 1], reason: '入队最久的待领取，也要压在最新完成的上面');
    });

    test('桶内倒序：待领取按入队时刻，最新的在最上面', () {
      final got = orderOf([
        NxKvTestTask(id: 10, status: 'pending', createdAt: '2026-11-16 08:00:00'),
        NxKvTestTask(id: 12, status: 'pending', createdAt: '2026-11-16 10:00:00'),
        NxKvTestTask(id: 11, status: 'pending', createdAt: '2026-11-16 09:00:00'),
      ]);
      expect(got, [12, 11, 10]);
    });

    test('桶内倒序按「最近一次变化」：已完成的是完成时刻说了算', () {
      // #20 是三天前入队、今天才完成的；#30 昨天入队、昨天就完成了。
      // 按入队时刻排会把 #20 埋到 #30 下面 —— 而人刚看见的是「今天完成的」。
      final got = orderOf([
        NxKvTestTask(id: 20, status: 'done', createdAt: '2026-11-13 08:00:00', completedAt: '2026-11-16 12:00:00'),
        NxKvTestTask(id: 30, status: 'done', createdAt: '2026-11-15 08:00:00', completedAt: '2026-11-15 09:00:00'),
      ]);
      expect(got, [20, 30]);
    });

    test('同一秒发布的两条：编号大的（后发的）在前', () {
      final got = orderOf([
        NxKvTestTask(id: 41, status: 'pending', createdAt: '2026-11-16 10:00:00'),
        NxKvTestTask(id: 42, status: 'pending', createdAt: '2026-11-16 10:00:00'),
      ]);
      expect(got, [42, 41]);
    });

    test('不认识的状态按终态沉底，不冒充「还有活」', () {
      final got = orderOf([
        NxKvTestTask(id: 51, status: 'blocked', createdAt: '2026-11-16 12:00:00'),
        NxKvTestTask(id: 52, status: 'pending', createdAt: '2026-11-16 08:00:00'),
      ]);
      expect(got, [52, 51]);
    });

    test('不改入参（视图可能还要按原序做别的事）', () {
      final src = [
        NxKvTestTask(id: 1, status: 'done', createdAt: '2026-11-16 10:00:00', completedAt: '2026-11-16 11:00:00'),
        NxKvTestTask(id: 2, status: 'pending', createdAt: '2026-11-16 08:00:00'),
      ];
      final out = sortTasksForDisplay(
        src,
        (t) => (
          bucket: nxKvTaskBucket(t.status),
          stamp: nxKvTaskStamp(createdAt: t.createdAt, consumedAt: t.consumedAt, completedAt: t.completedAt),
          id: t.id,
        ),
      );
      expect(out.map((t) => t.id), [2, 1]);
      expect(src.map((t) => t.id), [1, 2], reason: '排序必须是纯的');
    });
  });
}

/// 排序用例的最小任务形状：只带排序用得到的五个字段。
class NxKvTestTask {
  const NxKvTestTask({
    required this.id,
    required this.status,
    required this.createdAt,
    this.consumedAt = '',
    this.completedAt = '',
  });

  final int id;
  final String status;
  final String createdAt;
  final String consumedAt;
  final String completedAt;
}
