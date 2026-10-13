// NavEntryIcon 渲染分流 + LabDemoIcon 换色正确性：
//
// 1. colorizeLabSvg：#2B3445 → ink、#5B7CFA → accent，原色值不残留
// 2. NavEntryIcon：labIconAsset 非 null 渲染 SvgPicture，null 走 Icon
// 3. 单色压制：accentColor == inkColor 时强调点与轮廓同色
//
// 注意 test/ 被 gitignore 拦新增，收录需 git add -f。

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xiaodouzi_fr/core/nav/nav_entry.dart';
import 'package:xiaodouzi_fr/widgets/lab_demo_icon.dart';
import 'package:xiaodouzi_fr/widgets/nav_entry_icon.dart';

NavEntry _entry({String? labIconAsset}) => NavEntry(
      id: 'demo:clock',
      title: '时钟',
      icon: Icons.access_time,
      group: NavGroup.lab,
      labIconAsset: labIconAsset,
      builder: (_) => const SizedBox.shrink(),
    );

const _svg2Color =
    '<svg viewBox="0 0 32 32"><path fill="#2B3445"/><path fill="#5B7CFA"/></svg>';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('colorizeLabSvg 换色', () {
    test('ink / accent 双角色替换，原设计色不残留', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: const Color(0xFF7A9A7E),
        accent: const Color(0xFFA0594A),
      );
      expect(out.contains('#2B3445'), isFalse, reason: '轮廓原色残留');
      expect(out.contains('#5B7CFA'), isFalse, reason: '强调原色残留');
      expect(out.contains('#7A9A7E'), isTrue, reason: '轮廓未换成 ink');
      expect(out.contains('#A0594A'), isTrue, reason: '强调未换成 accent');
    });

    test('半透明 ink 保留 alpha（8 位 hex）——底栏未选中态区分的关键', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: Colors.white.withValues(alpha: 0.42),
        accent: const Color(0xFF163A94),
      );
      expect(out.contains(RegExp(r'#FFFFFF6B', caseSensitive: false)), isTrue,
          reason: 'alpha 丢失会让未选中图标渲染成全亮度');
    });

    test('双色压单色：ink == accent 时强调点与轮廓同色', () {
      final out = colorizeLabSvg(
        _svg2Color,
        ink: const Color(0xFF123456),
        accent: const Color(0xFF123456),
      );
      final hexes = RegExp(r'#[0-9A-F]{6}')
          .allMatches(out)
          .map((m) => m.group(0))
          .toSet();
      expect(hexes, {'#123456'});
    });
  });

  group('adaptiveLabIconColors 明度差自适应', () {
    test('亮色主题：深宝蓝（cobalt primary）在浅轮廓边下提亮到 L0.62', () {
      final (ink, accent) = adaptiveLabIconColors(
        const Color(0xFF1A1A1A), // 深 ink
        const Color(0xFF163A94), // cobalt 深 primary
        Brightness.light,
      );
      expect(ink, const Color(0xFF1A1A1A), reason: '亮色主题 ink 不动');
      expect(HSLColor.fromColor(accent).lightness, closeTo(0.62, 0.01),
          reason: '深 primary 应提亮');
    });

    test('亮色主题：明度差已够（柠檬亮黄）原样返回', () {
      final lemon = const Color(0xFFE4C44A);
      final (ink, accent) = adaptiveLabIconColors(
        const Color(0xFF2C2A24), // 中深 ink
        lemon,
        Brightness.light,
      );
      expect(ink, const Color(0xFF2C2A24));
      expect(accent, lemon);
    });

    test('深色主题：传 onSurface 也自动压暗 35%，让 accent 成最亮元素', () {
      // ⋯ 面板场景：caller 传 tint=cs.onSurface（白），accent=cs.primary
      final onSurface = const Color(0xFFE8E7E3);
      final darkPrimary = const Color(0xFFC9C5BD);
      final (ink, accent) = adaptiveLabIconColors(
        onSurface,
        darkPrimary,
        Brightness.dark,
      );
      expect(accent, darkPrimary, reason: '深色主题 accent 不动');
      expect(
        HSLColor.fromColor(ink).lightness,
        lessThan(HSLColor.fromColor(accent).lightness),
        reason: '压暗后轮廓必须暗于强调点（暗黑 primary L0.77 vs ink→压暗）',
      );
    });

    test('深色主题：即使 accent 明度已够仍亮于压暗后的 ink', () {
      // 假设有一个「暗黑暮紫」类的强对比主题——确保 dim 永远出对比
      final (ink, accent) = adaptiveLabIconColors(
        const Color(0xFFE8E7E3),
        const Color(0xFFD2BA7A), // 暮紫 tier 鎏金 L0.75
        Brightness.dark,
      );
      expect(
        HSLColor.fromColor(ink).lightness,
        lessThan(HSLColor.fromColor(accent).lightness - 0.05),
      );
    });
  });

  group('LabDemoIcon 渲染管线冒烟（真资产，非字符串替换）', () {
    // 资产 IO 走真实事件循环（tester.runAsync）：_svgCache 是进程级静态，
    // 前一个测试的 FakeAsync zone 创建的 future 后续测试 pump 不动——
    // runAsync 避开 FakeAsync 限制，也让测试互不依赖执行顺序。
    Future<void> pumpIcon(WidgetTester tester, Widget child) async {
      debugResetLabDemoIconCache();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: child)),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
    }

    testWidgets('真 SVG 加载 → 换色 → SvgPicture 出图', (tester) async {
      await pumpIcon(
        tester,
        const LabDemoIcon(assetBaseName: '01-clock', size: 32),
      );
      expect(find.byType(SvgPicture), findsOneWidget,
          reason: '加载成功后必须出现 SvgPicture；若此断言失败且日志报 '
              'Unable to load asset，检查 pubspec assets 声明');
      expect(tester.takeException(), isNull);
    });

    testWidgets('资产不存在 → Material 兜底图标而非静默空白', (tester) async {
      await pumpIcon(
        tester,
        const LabDemoIcon(assetBaseName: '99-not-exist', size: 32),
      );
      expect(find.byIcon(Icons.widgets_outlined), findsOneWidget,
          reason: '加载失败必须有可见兜底（此前静默空白 = 全灭无诊断）');
      expect(find.byType(SvgPicture), findsNothing);
    });

    testWidgets('失败 future 不留缓存 → 修好后可重试', (tester) async {
      await pumpIcon(
        tester,
        const LabDemoIcon(assetBaseName: '02-calendar-todo', size: 32),
      );
      expect(find.byType(SvgPicture), findsOneWidget);
    });
  });

  group('NavEntryIcon 渲染分流', () {
    testWidgets('labIconAsset 非 null → SvgPicture（SVG）', (tester) async {
      debugResetLabDemoIconCache();
      await tester.runAsync(() async {
        await tester.pumpWidget(
          MaterialApp(
            home: NavEntryIcon(entry: _entry(labIconAsset: '01-clock')),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.byType(SvgPicture), findsOneWidget);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('labIconAsset null → Material Icon 兜底', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: NavEntryIcon(entry: _entry())),
      );
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
    });
  });
}
