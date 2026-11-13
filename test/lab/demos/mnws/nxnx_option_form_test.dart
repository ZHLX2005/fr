import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/api/mnws/nxnx/nxnx_models.dart';
import 'package:xiaodouzi_fr/lab/demos/mnws/nxnx/nxnx_option_form.dart';

/// 新建项目表单的**判定规则**。
///
/// 这些规则是服务端 `resolveVars` 的镜像 —— 面板判「够了」、服务端也得认。
/// 两边漂移的症状是「按钮能点但服务端报错」或「按钮恒灰但其实能生成」。
void main() {
  NxNxOption opt(
    String name, {
    String type = 'string',
    bool required = false,
    String label = '',
    List<String> values = const [],
    String? pattern,
    Object? defaultValue,
  }) =>
      NxNxOption(
        name: name,
        type: type,
        label: label,
        required: required,
        hint: '',
        values: values,
        pattern: pattern,
        defaultValue: defaultValue,
      );

  group('必填 / 可选分组', () {
    test('必填在前、可选在后，组内保持声明顺序', () {
      final split = nxNxSplitOptions([
        opt('letters', required: true),
        opt('desc'),
        opt('name', required: true),
        opt('port', type: 'number'),
      ]);
      expect(split.required.map((o) => o.name), ['letters', 'name']);
      expect(split.optional.map((o) => o.name), ['desc', 'port']);
    });
  });

  group('阻塞判定', () {
    test('缺必填 → 说清缺哪个', () {
      final issues = nxNxBlockingIssues([opt('name', required: true)], {});
      expect(issues, hasLength(1));
      expect(issues.first.isMissing, isTrue);
      expect(issues.first.message, contains('必填'));
      expect(nxNxDescribeIssues(issues), contains('还差必填项'));
    });

    test('有默认值 → 不算缺（服务端会落回默认值）', () {
      final issues = nxNxBlockingIssues(
        [opt('name', required: true, defaultValue: 'demo')],
        {},
      );
      expect(issues, isEmpty);
    });

    test('0 与 false 是合法取值，不算「没填」', () {
      expect(nxNxIsBlank(0), isFalse);
      expect(nxNxIsBlank(false), isFalse);
      expect(nxNxIsBlank(''), isTrue);
      expect(nxNxIsBlank(null), isTrue);
    });

    test('格式不对 → 归成 invalid，不是 missing', () {
      final issues = nxNxBlockingIssues(
        [opt('letters', type: 'letters', required: true)],
        {'letters': 'ABCDEF'},
      );
      expect(issues, hasLength(1));
      expect(issues.first.isMissing, isFalse);
      expect(issues.first.message, contains('1~5'));
    });

    test('枚举值不在范围 → 报错并列出可选值', () {
      final issues = nxNxBlockingIssues(
        [opt('lang', type: 'enum', values: ['ts', 'go'])],
        {'lang': 'rust'},
      );
      expect(issues, hasLength(1));
      expect(issues.first.message, contains('ts | go'));
    });

    test('模板声明的正则约束也认', () {
      final issues = nxNxBlockingIssues(
        [opt('lang', pattern: r'^[a-z]{2}$')],
        {'lang': 'TS'},
      );
      expect(issues, hasLength(1));
      expect(issues.first.message, contains('格式不符合'));
    });

    test('留空一律放行（刚打开面板不该满屏红字）', () {
      final issues = nxNxBlockingIssues(
        [opt('letters', type: 'letters', required: true)],
        {},
      );
      // 缺必填会被报 missing；但**格式**校验不报
      expect(issues.where((i) => !i.isMissing), isEmpty);
    });
  });

  group('项目名推导', () {
    test('letters 优先', () {
      final tpl = NxNxTemplate(
        id: 't',
        name: 't',
        description: '',
        nextSteps: const [],
        options: [opt('letters', required: true)],
        namePrefix: 'a_',
      );
      expect(nxNxSuggestProjectName(tpl, {'letters': 'ts'}), 'a_ts');
    });

    test('没有 letters 就用 name', () {
      final tpl = NxNxTemplate(
        id: 't',
        name: 't',
        description: '',
        nextSteps: const [],
        options: [opt('name', required: true)],
        namePrefix: 'nx-',
      );
      expect(nxNxSuggestProjectName(tpl, {'name': 'demo'}), 'nx-demo');
    });

    test('否则取第一个必填项的值', () {
      final tpl = NxNxTemplate(
        id: 't',
        name: 't',
        description: '',
        nextSteps: const [],
        options: [opt('lang', required: true)],
        namePrefix: 'a_',
      );
      expect(nxNxSuggestProjectName(tpl, {'lang': 'go'}), 'a_go');
    });

    test('推不出就留空 —— 宁可空着也不猜错', () {
      final tpl = NxNxTemplate(
        id: 't',
        name: 't',
        description: '',
        nextSteps: const [],
        options: [opt('letters', required: true)],
      );
      expect(nxNxSuggestProjectName(tpl, {}), '');
      expect(nxNxSuggestProjectName(tpl, {'letters': 'ts, go'}), '');
      expect(nxNxSuggestProjectName(null, {'letters': 'ts'}), '');
    });

    test('用户填了 prefix 就用用户的', () {
      final tpl = NxNxTemplate(
        id: 't',
        name: 't',
        description: '',
        nextSteps: const [],
        options: [opt('letters', required: true)],
        namePrefix: 'a_',
      );
      expect(nxNxSuggestProjectName(tpl, {'letters': 'ts', 'prefix': 'z_'}), 'z_ts');
    });
  });
}
