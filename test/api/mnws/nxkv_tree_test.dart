import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_boards.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_tree.dart';

/// 侧边栏行模型的**纯函数**用例。
///
/// 第 5 轮反馈「侧边栏的逻辑仍然不对，参考当前的 nx-kv 的侧边栏」之后，这里钉的是
/// nx-kv 面板的三条语义：**组是入口（叶子）**、**项目平铺（一个仓库一行）**、
/// **顺序稳定（名字序，不按待领数抖）**。UI 只照着这份行清单画。
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

  NxKvBoard board(String name, List<String> repos, {String desc = ''}) =>
      NxKvBoard(key: 'group/$name', name: name, desc: desc, repoKeys: repos);

  group('NxKvBoard.parse', () {
    test('认 {ok,data:{boards}} 这种被代理服务的信封', () {
      final boards = NxKvBoard.parse({
        'ok': true,
        'data': {
          'boards': [
            {
              'id': 'b1',
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

  group('buildSideList — 结构（组是入口，项目平铺）', () {
    test('组行是叶子：不装项目，项目自己一行', () {
      final side = buildSideList(
        topics: [
          topic(key: 'k-fr', name: 'fr', repoKey: 'r/fr', pending: 1, total: 4),
          topic(key: 'k-rt', name: 'mn-rt', repoKey: 'r/rt', total: 2),
        ],
        boards: [board('mobile', ['r/fr', 'r/rt'])],
      );

      // 渲染序：组在前，项目在后 —— 项目不是组的子行
      expect(side.rows.map((r) => r.kind), [
        NxKvRowKind.group,
        NxKvRowKind.repo,
        NxKvRowKind.repo,
      ]);
      expect(side.groups.single.label, 'mobile');
      // 组行没有队列可进：点它只会打开组视图
      expect(side.groups.single.topicKey, isNull);
      expect(side.groups.single.expandable, isFalse);
      expect(side.groups.single.memberCount, 2);
      // 待领从成员冒泡上来（手机拿不到「组任务」口径，这是成员队列之和）
      expect(side.groups.single.pending, 1);
      expect(side.repos.map((r) => r.label), ['fr', 'mn-rt']);
    });

    test('一个仓库挂两个组：项目仍只有一行，两个组都指得到它', () {
      final side = buildSideList(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr', pending: 2)],
        boards: [
          board('mobile', ['r/fr']),
          board('kv_fr', ['r/fr']),
        ],
      );

      expect(side.repos, hasLength(1), reason: '项目是模块，不是组里的文件');
      expect(side.groups.map((g) => g.label), ['mobile', 'kv_fr']);
      // 两条组行都把它算进成员与待领（组只是指针）
      expect(side.groups.every((g) => g.memberCount == 1), isTrue);
      expect(side.groups.every((g) => g.pending == 2), isTrue);
      expect(side.membersOf(side.groups.first).single.label, 'fr');
      expect(side.membersOf(side.groups.last).single.label, 'fr');
    });

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
      // 它不属于任何组，组视图里不会出现
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

    test('组里没有本机队列的成员：组行照出，只是点进去没东西', () {
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

    test('命中项目只留那一行（组按「成员命中」跟着留下）', () {
      final side = buildSideList(topics: topics, boards: boards, query: 'rt');
      expect(side.repos.map((r) => r.label), ['mn-rt']);
      expect(side.groups.map((g) => g.label), ['mobile'],
          reason: '组是成员的指针：成员命中，组就该在');
      expect(side.matched, 2);
    });

    test('命中组成员项目，组行也算命中（组代表成员）', () {
      final side = buildSideList(topics: topics, boards: boards, query: 'fr');
      expect(side.groups.map((g) => g.label), ['mobile']);
      expect(side.repos.map((r) => r.label), ['fr']);
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

    test('groupByKey 找到组行；空键返回 null', () {
      expect(side.groupByKey('group/mobile')?.label, 'mobile');
      expect(side.groupByKey('group/nope'), isNull);
      expect(side.groupByKey(null), isNull);
    });
  });
}
