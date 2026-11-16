import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/mnws/nxkv/nxkv_template.dart';

/// 任务模板（fr #23）：「新建任务的正文」两端只能有一套真相。
///
/// 分叉现场：端侧硬编码的 `## 背景 / ## 验收 / ## 约束` 是**面板的兜底骨架**，
/// 而面板正常路径取的是 `defaultId` 指向的模板（#137 之后是「ref 生成」的 SOP）。
/// 这几条钉住三件事：取哪一条、怎么渲染、兜底是谁。
void main() {
  group('renderNxKvTemplate：{{槽位}} → 值', () {
    test('有值就换进去', () {
      expect(
        renderNxKvTemplate('## 背景\n\n{{背景}}\n', const {'背景': '登录页白屏'}),
        '## 背景\n\n登录页白屏\n',
      );
    });

    test('没值留空 —— 绝不把裸标记塞进正文', () {
      expect(renderNxKvTemplate('A{{缺失}}B', const {}), 'AB');
    });

    test('标记里带空格也认（面板正则同样宽松）', () {
      expect(renderNxKvTemplate('{{ 背景 }}', const {'背景': 'x'}), 'x');
    });

    test('没有标记的正文原样返回（出厂 SOP 正文就是这种）', () {
      const body = '## 本轮问题\n\n---\n\n## 怎么干\n';
      expect(renderNxKvTemplate(body, const {'背景': 'x'}), body);
    });
  });

  group('NxKvTemplateSet.tryParse：三种信封', () {
    test('{ok,data:{defaultId,templates}}', () {
      final set = NxKvTemplateSet.tryParse({
        'ok': true,
        'data': {
          'defaultId': 'newtask.ref',
          'templates': [
            {'id': 'newtask.ref', 'name': 'ref 生成', 'body': '## 本轮问题'},
          ],
        },
      });
      expect(set!.defaultId, 'newtask.ref');
      expect(set.active!.name, 'ref 生成');
    });

    test('裸 {defaultId,templates}', () {
      final set = NxKvTemplateSet.tryParse({
        'defaultId': 'a',
        'templates': [
          {'id': 'a', 'body': 'x'},
        ],
      });
      expect(set!.active!.body, 'x');
    });

    test('认不出来给 null（不抛 —— 拉模板失败不该挡住派活）', () {
      expect(NxKvTemplateSet.tryParse(null), isNull);
      expect(NxKvTemplateSet.tryParse({'templates': 'oops'}), isNull);
      expect(NxKvTemplateSet.tryParse({}), isNull);
    });
  });

  group('nxKvNewTaskBody：取默认模板，取不到走兜底', () {
    test('defaultId 指向的那条优先，且渲染过槽位', () {
      final set = NxKvTemplateSet.tryParse({
        'defaultId': 'b',
        'templates': [
          {'id': 'a', 'body': 'A 的正文'},
          {'id': 'b', 'body': '## 背景\n{{背景}}', 'values': {'背景': '来自服务端的值'}},
        ],
      });
      expect(nxKvNewTaskBody(set), '## 背景\n来自服务端的值');
    });

    test('模板自带 values 覆盖内置默认值；显式空串仍是空', () {
      final set = NxKvTemplateSet.tryParse({
        'defaultId': 'a',
        'templates': [
          {
            'id': 'a',
            'body': '[{{背景}}][{{验收}}][{{附件}}]',
            'values': {'背景': '改了', '验收': ''},
          },
        ],
      });
      // 背景=模板值；验收=显式空 → 空；附件=没给 → 内置默认（''）
      expect(nxKvNewTaskBody(set), '[改了][][]');
    });

    test('老模板里的 {{背景}} 不落成裸标记，而是落成骨架文案', () {
      final set = NxKvTemplateSet.tryParse({
        'defaultId': 'old',
        'templates': [
          {'id': 'old', 'body': '## 背景\n\n{{背景}}\n\n## 验收\n- [ ] {{验收}}'},
        ],
      });
      final body = nxKvNewTaskBody(set);
      expect(body, contains('（一句话说清要改什么）'));
      expect(body, isNot(contains('{{')));
    });

    test('没有模板集 / defaultId 指空 / 正文空白 → 面板同款兜底', () {
      expect(nxKvNewTaskBody(null), nxKvNewTaskFallbackBody);
      expect(
        nxKvNewTaskBody(const NxKvTemplateSet(defaultId: '', items: [])),
        nxKvNewTaskFallbackBody,
      );
      expect(
        nxKvNewTaskBody(NxKvTemplateSet.tryParse({
          'defaultId': 'gone',
          'templates': [
            {'id': 'other', 'body': 'x'},
          ],
        })),
        nxKvNewTaskFallbackBody,
        reason: '默认模板被删了 → 兜底，不是用别人的正文',
      );
      expect(
        nxKvNewTaskBody(NxKvTemplateSet.tryParse({
          'defaultId': 'blank',
          'templates': [
            {'id': 'blank', 'body': '   \n\n '},
          ],
        })),
        nxKvNewTaskFallbackBody,
        reason: '空正文等于没模板（服务端 normalizeBody 也这么兜）',
      );
    });

    test('兜底正文与面板 NEW_TEMPLATE 逐字一致（防两端各自漂移）', () {
      // 面板：web/frontend/modules/md/md-parse.js 的 NEW_TEMPLATE
      const panel = '## 背景\n'
          '\n'
          '（一句话说清要改什么）\n'
          '\n'
          '## 验收\n'
          '- [ ] …\n'
          '\n'
          '## 约束\n'
          '- …\n'
          '\n'
          '## 附件\n';
      expect(nxKvNewTaskFallbackBody, panel);
    });
  });
}
