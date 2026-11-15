import 'package:flutter_test/flutter_test.dart';
import 'package:nx_kv_client/nx_kv_client.dart' as kv;
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_boards.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_tree.dart';

/// 侧边栏目录树（第 4 轮反馈第一条）的**纯函数**用例。
///
/// 树是这一轮唯一「有真实结构」的东西：组 → 项目 → 主题。UI 层只是照着它画，
/// 所以把规则钉在这里 —— 单队列项目压成一层、一个仓库只出现在一个组、
/// 搜索留下命中的分支、没有组数据时退化成「未分组」。
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

  NxKvBoard board(String name, List<String> repos) =>
      NxKvBoard(key: 'group/$name', name: name, repoKeys: repos);

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
      expect(boards.single.repoKeys, ['github.com/zhlx2005/fr']);
    });

    test('裸数组 / 垃圾输入都不炸', () {
      expect(NxKvBoard.parse([{'name': 'nx', 'repos': []}]).single.name, 'nx');
      expect(NxKvBoard.parse(null), isEmpty);
      expect(NxKvBoard.parse({'nope': 1}), isEmpty);
      expect(NxKvBoard.parse('不是 JSON 结构'), isEmpty);
    });
  });

  group('buildTopicTree', () {
    test('组 → 项目 → 主题：单队列项目压成一层，直接可选中', () {
      final nodes = buildTopicTree(
        topics: [
          topic(key: 'k-fr', name: 'fr', repoKey: 'github.com/zhlx2005/fr', pending: 1, total: 4),
          topic(key: 'k-rt', name: 'mn-rt', repoKey: 'github.com/zhlx2005/mn-rt', pending: 0, total: 2),
        ],
        boards: [
          board('mobile', ['github.com/zhlx2005/fr', 'github.com/zhlx2005/mn-rt']),
        ],
      );

      expect(nodes, hasLength(1));
      final mobile = nodes.single;
      expect(mobile.label, 'mobile');
      expect(mobile.level, NxKvTreeLevel.group);
      // 待领数从子节点冒泡上来
      expect(mobile.pending, 1);
      expect(mobile.children, hasLength(2));
      // 单队列 + 队列名 == 仓库名 → 项目节点本身就是叶子
      final fr = mobile.children.firstWhere((n) => n.label == 'fr');
      expect(fr.selectable, isTrue);
      expect(fr.topicKey, 'k-fr');
      expect(fr.children, isEmpty);
    });

    test('一个仓库有多条队列时才真的展开第三层', () {
      final nodes = buildTopicTree(
        topics: [
          topic(key: 'k1', name: 'fr', repoKey: 'r/fr', repoName: 'fr'),
          topic(key: 'k2', name: 'fr-docs', repoKey: 'r/fr', repoName: 'fr', pending: 2),
        ],
        boards: [board('mobile', ['r/fr'])],
      );

      final fr = nodes.single.children.single;
      expect(fr.label, 'fr');
      expect(fr.selectable, isFalse, reason: '容器节点不该被当成一条队列');
      expect(fr.children.map((c) => c.topicKey), ['k2', 'k1'],
          reason: '有待领的排前面：拉抽屉就是要看哪条该干');
      expect(fr.pending, 2);
    });

    test('没有组数据时全部落在「未分组」，且「未分组」排在最后', () {
      final nodes = buildTopicTree(
        topics: [
          topic(key: 'a', name: 'proj-alpha'),
          topic(key: 'b', name: 'fr', repoKey: 'r/fr'),
        ],
        boards: [board('mobile', ['r/fr'])],
      );
      expect(nodes.map((n) => n.label), ['mobile', kUngroupedLabel]);
      // 没登记仓库的主题：项目层就是它自己，可选、不重复画子节点
      final orphan = nodes.last.children.single;
      expect(orphan.label, 'proj-alpha');
      expect(orphan.topicKey, 'a');
      expect(orphan.children, isEmpty);
    });

    test('一个仓库属于两个组：只出现在第一个组里（不重复出现）', () {
      final nodes = buildTopicTree(
        topics: [topic(key: 'k', name: 'fr', repoKey: 'r/fr')],
        boards: [
          board('mobile', ['r/fr']),
          board('kv_fr', ['r/fr']),
        ],
      );
      expect(nodes.map((n) => n.label), ['mobile']);
    });

    test('搜索：命中子节点只留那条，命中组名整组留下', () {
      final topics = [
        topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
        topic(key: 'k2', name: 'mn-rt', repoKey: 'r/rt'),
      ];
      final boards = [board('mobile', ['r/fr', 'r/rt'])];

      final byTopic = buildTopicTree(topics: topics, boards: boards, query: 'rt');
      expect(byTopic.single.children.map((n) => n.label), ['mn-rt']);

      final byGroup = buildTopicTree(topics: topics, boards: boards, query: 'mobi');
      expect(byGroup.single.children.map((n) => n.label), ['fr', 'mn-rt']);

      expect(buildTopicTree(topics: topics, boards: boards, query: 'zzz'), isEmpty);
    });

    test('pathToKey 给出「组 → 项目 → 主题」的展开路径', () {
      final nodes = buildTopicTree(
        topics: [
          topic(key: 'k1', name: 'fr', repoKey: 'r/fr'),
          topic(key: 'k2', name: 'fr-docs', repoKey: 'r/fr', repoName: 'fr'),
        ],
        boards: [board('mobile', ['r/fr'])],
      );

      final path = pathToKey(nodes, 'k2');
      expect(path, hasLength(3), reason: '组 + 项目 + 主题，三层都要展开');
      expect(path.first, startsWith('g:'));
      expect(path.last, startsWith('t:'));
      // 选中项本身就在末端
      expect(nodes.first.children.single.children.any((n) => n.id == path.last), isTrue);
      expect(pathToKey(nodes, '不存在'), isEmpty);
    });
  });
}
